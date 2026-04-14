import Foundation

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

    /// Perform a full refresh: fetch PRs, categorize new ones, fetch build status.
    func refresh() async throws -> [PullRequest] {
        guard !settings.githubUsername.isEmpty else { return [] }

        let existingPRs = await persistence.loadPullRequests()
        var existingByID: [String: PullRequest] = [:]
        for pr in existingPRs {
            existingByID[pr.id] = pr
        }

        // Cache CODEOWNERS per repo (empty string = confirmed no CODEOWNERS file)
        var codeownersCache: [String: String] = [:]

        var allPRs: [PullRequest] = []

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

            // Fetch review requests
            let fetchedPRs = try await githubClient.fetchReviewRequests(
                repo: repo,
                username: settings.githubUsername
            )

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

            for var pr in fetchedPRs {
                pr.isRequestedReviewer = true

                // Check if user is a direct (non-catch-all) codeowner
                if let parser {
                    pr.isDirectCodeowner = parser.isDirectOwner(
                        username: settings.githubUsername,
                        files: pr.filesChanged
                    )
                }

                if let existing = existingByID[pr.id] {
                    pr.isFlagged = existing.isFlagged
                    if existing.categoryOverridden {
                        pr.category = existing.category
                        pr.categoryOverridden = true
                        pr.categoryReason = existing.categoryReason
                        pr.lastCategorizedAt = existing.lastCategorizedAt
                    }
                }

                let idx = prsForRepo.count
                prsForRepo.append(pr)

                if !pr.categoryOverridden {
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

                    if idx < needsCategorization.count {
                        let (nextPrIdx, nextPr) = needsCategorization[idx]
                        idx += 1
                        group.addTask {
                            let result = await catService.categorize(pr: nextPr, codeowners: codeowners, userContext: userContext)
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
                        if existing.categoryOverridden {
                            pr.category = existing.category
                            pr.categoryOverridden = true
                            pr.categoryReason = existing.categoryReason
                            pr.lastCategorizedAt = existing.lastCategorizedAt
                        } else {
                            // Re-categorize
                            let codeowners = codeownersCache[existing.repoFullName].flatMap { $0.isEmpty ? nil : $0 }
                            let parser: CodeownersParser? = parserCache[existing.repoFullName]
                            if let parser {
                                pr.isDirectCodeowner = parser.isDirectOwner(
                                    username: settings.githubUsername,
                                    files: pr.filesChanged
                                )
                            }
                            let result = await categorizationService.categorize(
                                pr: pr, codeowners: codeowners, userContext: settings.codeownerContext,
                                username: settings.githubUsername
                            )
                            pr.category = result.category
                            pr.categoryReason = result.reason
                            pr.lastCategorizedAt = Date()
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

        return allPRs
    }
}
