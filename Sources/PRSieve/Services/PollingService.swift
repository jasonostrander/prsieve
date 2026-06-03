import Foundation

struct RepoFetchError: Sendable, Equatable {
    let repo: String
    let message: String
}

struct RefreshResult: Sendable {
    let prs: [PullRequest]
    let llmError: LLMError?
    let repoErrors: [RepoFetchError]
}

actor PollingService {
    private let persistence: PersistenceService
    private let githubClient: GitHubClient
    private let buildkiteClient: BuildkiteClient
    private let categorizationService: CategorizationService
    private var settings: AppSettings
    private var isPolling = false
    private var parserCache: [String: CodeownersParser] = [:]

    init(
        persistence: PersistenceService,
        githubClient: GitHubClient,
        buildkiteClient: BuildkiteClient,
        categorizationService: CategorizationService,
        settings: AppSettings
    ) {
        self.persistence = persistence
        self.githubClient = githubClient
        self.buildkiteClient = buildkiteClient
        self.categorizationService = categorizationService
        self.settings = settings
    }

    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Categorization caching

    /// Deterministic fingerprint of the categorization inputs that are *not*
    /// reflected by a PR's `updatedAt` (the LLM system prompt, the user's ownership
    /// context, their username, and the codeowner/reviewer flags). When this is
    /// unchanged and the PR hasn't been touched, re-categorizing would produce the
    /// same answer, so we can reuse the stored verdict and skip the LLM call.
    ///
    /// Uses FNV-1a so the value is stable across launches (Swift's `Hasher` is
    /// per-run randomized and would invalidate the cache on every restart).
    static func categorizationFingerprint(
        systemPrompt: String,
        userContext: String,
        username: String,
        codeowners: String,
        isDirectCodeowner: Bool,
        isRequestedReviewer: Bool
    ) -> String {
        // U+001F (unit separator) can't appear in the inputs, so fields can't bleed.
        let input = [
            isDirectCodeowner ? "1" : "0",
            isRequestedReviewer ? "1" : "0",
            username,
            userContext,
            codeowners,
            systemPrompt
        ].joined(separator: "\u{1f}")

        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Whether a freshly-fetched PR can keep its previously-computed category
    /// instead of being re-categorized. Safe only when the PR hasn't changed since
    /// it was last categorized (`updatedAt` not advanced past `lastCategorizedAt`)
    /// and every input outside `updatedAt` is identical (matching fingerprint).
    /// Manual overrides are handled separately and never reuse via this path.
    static func canReuseCategorization(
        existing: PullRequest,
        fresh: PullRequest,
        currentFingerprint: String
    ) -> Bool {
        guard !existing.categoryOverridden,
              let lastAt = existing.lastCategorizedAt,
              fresh.updatedAt <= lastAt,
              let storedFingerprint = existing.categorizationContextHash,
              storedFingerprint == currentFingerprint
        else { return false }
        return true
    }

    /// Perform a full refresh: fetch PRs, categorize new ones, fetch build status.
    func refresh() async throws -> RefreshResult {
        guard !settings.githubUsername.isEmpty else { return RefreshResult(prs: [], llmError: nil, repoErrors: []) }

        let existingPRs = await persistence.loadPullRequests()
        var existingByID: [String: PullRequest] = [:]
        for pr in existingPRs {
            existingByID[pr.id] = pr
        }

        // Cache CODEOWNERS per repo (empty string = confirmed no CODEOWNERS file)
        var codeownersCache: [String: String] = [:]

        var allPRs: [PullRequest] = []
        var repoErrors: [RepoFetchError] = []

        for repoConfig in settings.repos {
            let repo = repoConfig.repo

            // Fetch CODEOWNERS (cached)
            if codeownersCache[repo] == nil {
                let cached = await persistence.loadCodeowners(forRepo: repo)
                if let cached {
                    codeownersCache[repo] = cached
                } else {
                    if let fetched = try? await githubClient.fetchCodeowners(repo: repo) {
                        codeownersCache[repo] = fetched
                        try? await persistence.saveCodeowners(fetched, forRepo: repo)
                    } else {
                        codeownersCache[repo] = "" // mark as checked
                    }
                }
            }

            // Fetch review requests and PRs previously reviewed by user (in parallel).
            // A failure for one repo must NOT abort the whole refresh — other repos
            // (and disappeared-PR recovery below) still need to run.
            let mergedPRs: [(pr: PullRequest, isRequested: Bool)]
            do {
                async let requestedPRs = githubClient.fetchReviewRequests(
                    repo: repo,
                    username: settings.githubUsername
                )
                async let reviewedPRs = githubClient.fetchReviewedByUser(
                    repo: repo,
                    username: settings.githubUsername
                )

                // Merge: review-requested PRs take precedence; reviewed-by fills in the rest
                var seenIDs = Set<String>()
                var merged: [(pr: PullRequest, isRequested: Bool)] = []
                for pr in (try await requestedPRs) {
                    if seenIDs.insert(pr.id).inserted {
                        merged.append((pr, true))
                    }
                }
                for pr in (try await reviewedPRs) {
                    if seenIDs.insert(pr.id).inserted {
                        merged.append((pr, false))
                    }
                }
                mergedPRs = merged
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                NSLog("PRSieve: failed to fetch PRs for \(repo): \(message)")
                repoErrors.append(RepoFetchError(repo: repo, message: message))
                // Preserve any cached PRs for this repo so they don't disappear from the UI.
                for (_, existing) in existingByID where existing.repoFullName == repo {
                    allPRs.append(existing)
                }
                continue
            }

            // Apply overrides and collect PRs needing categorization
            var prsForRepo: [PullRequest] = []
            var needsCategorization: [(Int, PullRequest)] = [] // (index, pr)

            // Use cached parser, or create one if CODEOWNERS content is available
            let parser: CodeownersParser? = parserCache[repo] ?? {
                guard let text = codeownersCache[repo], !text.isEmpty else { return nil }
                let p = CodeownersParser(content: text)
                parserCache[repo] = p
                return p
            }()

            for (var pr, isRequested) in mergedPRs {
                pr.isRequestedReviewer = isRequested

                // Check if user is a direct (non-catch-all) codeowner
                if let parser {
                    pr.isDirectCodeowner = parser.isDirectOwner(
                        username: settings.githubUsername,
                        files: pr.filesChanged
                    )
                }

                let fingerprint = Self.categorizationFingerprint(
                    systemPrompt: llmSystemPrompt,
                    userContext: settings.codeownerContext,
                    username: settings.githubUsername,
                    codeowners: codeownersCache[repo] ?? "",
                    isDirectCodeowner: pr.isDirectCodeowner,
                    isRequestedReviewer: pr.isRequestedReviewer
                )

                if let existing = existingByID[pr.id] {
                    pr.isFlagged = existing.isFlagged
                    if existing.categoryOverridden,
                       let overriddenAt = existing.lastCategorizedAt,
                       pr.updatedAt <= overriddenAt {
                        // PR hasn't changed since override was set — keep it
                        pr.category = existing.category
                        pr.categoryOverridden = true
                        pr.categoryReason = existing.categoryReason
                        pr.lastCategorizedAt = existing.lastCategorizedAt
                        pr.categorizationContextHash = existing.categorizationContextHash
                    } else if Self.canReuseCategorization(existing: existing, fresh: pr, currentFingerprint: fingerprint) {
                        // Nothing affecting the verdict changed → reuse the stored
                        // category and skip categorization (and its LLM call).
                        pr.category = existing.category
                        pr.categoryReason = existing.categoryReason
                        pr.lastCategorizedAt = existing.lastCategorizedAt
                        pr.categorizationContextHash = existing.categorizationContextHash
                    }
                    // else: new/updated PR or changed inputs → re-categorize below
                }

                let idx = prsForRepo.count
                prsForRepo.append(pr)

                // A reused or overridden PR carries a non-nil lastCategorizedAt;
                // anything still nil needs (re)categorization.
                if !pr.categoryOverridden && pr.lastCategorizedAt == nil {
                    needsCategorization.append((idx, pr))
                }
            }

            // Categorize concurrently (bounded to 5 at a time)
            let codeowners = codeownersCache[repo].flatMap { $0.isEmpty ? nil : $0 }
            let userContext = settings.codeownerContext
            let username = settings.githubUsername
            let catService = categorizationService

            await withTaskGroup(of: (Int, CategorizationService.CategorizationResult).self) { group in
                let maxConcurrency = 5
                var idx = 0

                for _ in 0..<min(maxConcurrency, needsCategorization.count) {
                    let (prIdx, pr) = needsCategorization[idx]
                    idx += 1
                    group.addTask {
                        let result = await catService.categorize(pr: pr, codeowners: codeowners, userContext: userContext, username: username)
                        return (prIdx, result)
                    }
                }

                for await (prIdx, result) in group {
                    prsForRepo[prIdx].category = result.category
                    prsForRepo[prIdx].categoryReason = result.reason
                    prsForRepo[prIdx].lastCategorizedAt = Date()
                    prsForRepo[prIdx].categorizationContextHash = Self.categorizationFingerprint(
                        systemPrompt: llmSystemPrompt,
                        userContext: userContext,
                        username: username,
                        codeowners: codeowners ?? "",
                        isDirectCodeowner: prsForRepo[prIdx].isDirectCodeowner,
                        isRequestedReviewer: prsForRepo[prIdx].isRequestedReviewer
                    )

                    if idx < needsCategorization.count {
                        let (nextPrIdx, nextPr) = needsCategorization[idx]
                        idx += 1
                        group.addTask {
                            let result = await catService.categorize(pr: nextPr, codeowners: codeowners, userContext: userContext, username: username)
                            return (nextPrIdx, result)
                        }
                    }
                }
            }

            allPRs.append(contentsOf: prsForRepo)
        }

        // Handle PRs that disappeared from search results.
        // The search API can miss team/CODEOWNERS-based review requests, so we
        // re-fetch disappeared PRs to check their actual state.
        let mergedRetention: TimeInterval = 7 * 24 * 3600
        let currentIDs = Set(allPRs.map(\.id))
        let disappeared = existingByID.filter { !currentIDs.contains($0.key) }
        for (_, existing) in disappeared {
            if let state = try? await githubClient.fetchPRState(repo: existing.repoFullName, number: existing.number) {
                if state.isMerged || state.isClosed {
                    // Actually merged/closed — keep in list for "show merged" toggle
                    var updated = existing
                    updated.isMerged = state.isMerged
                    updated.isClosed = state.isClosed
                    if updated.isFlagged || Date().timeIntervalSince(updated.updatedAt) < mergedRetention {
                        allPRs.append(updated)
                    }
                } else {
                    // Still open — search API missed it. Re-fetch full details.
                    if let refreshed = try? await githubClient.fetchPRDetail(
                        repo: existing.repoFullName,
                        number: existing.number,
                        username: settings.githubUsername
                    ) {
                        var pr = refreshed
                        pr.isRequestedReviewer = true
                        pr.isFlagged = existing.isFlagged
                        // Recompute the codeowner flag so the fingerprint and any
                        // re-categorization see the current value.
                        let codeowners = codeownersCache[existing.repoFullName].flatMap { $0.isEmpty ? nil : $0 }
                        if let parser = parserCache[existing.repoFullName] {
                            pr.isDirectCodeowner = parser.isDirectOwner(
                                username: settings.githubUsername,
                                files: pr.filesChanged
                            )
                        }
                        let fingerprint = Self.categorizationFingerprint(
                            systemPrompt: llmSystemPrompt,
                            userContext: settings.codeownerContext,
                            username: settings.githubUsername,
                            codeowners: codeowners ?? "",
                            isDirectCodeowner: pr.isDirectCodeowner,
                            isRequestedReviewer: pr.isRequestedReviewer
                        )

                        if existing.categoryOverridden,
                           let overriddenAt = existing.lastCategorizedAt,
                           pr.updatedAt <= overriddenAt {
                            pr.category = existing.category
                            pr.categoryOverridden = true
                            pr.categoryReason = existing.categoryReason
                            pr.lastCategorizedAt = existing.lastCategorizedAt
                            pr.categorizationContextHash = existing.categorizationContextHash
                        } else if Self.canReuseCategorization(existing: existing, fresh: pr, currentFingerprint: fingerprint) {
                            // Unchanged since last categorization → reuse, skip the LLM.
                            pr.category = existing.category
                            pr.categoryReason = existing.categoryReason
                            pr.lastCategorizedAt = existing.lastCategorizedAt
                            pr.categorizationContextHash = existing.categorizationContextHash
                        } else {
                            // Re-categorize
                            let result = await categorizationService.categorize(
                                pr: pr, codeowners: codeowners, userContext: settings.codeownerContext,
                                username: settings.githubUsername
                            )
                            pr.category = result.category
                            pr.categoryReason = result.reason
                            pr.lastCategorizedAt = Date()
                            pr.categorizationContextHash = fingerprint
                        }
                        allPRs.append(pr)
                    }
                }
            } else {
                // API call failed — preserve existing PR to avoid data loss
                allPRs.append(existing)
            }
        }

        // Save
        try await persistence.savePullRequests(allPRs)

        let llmError = await categorizationService.consumeLastLLMError()
        return RefreshResult(prs: allPRs, llmError: llmError, repoErrors: repoErrors)
    }
}
