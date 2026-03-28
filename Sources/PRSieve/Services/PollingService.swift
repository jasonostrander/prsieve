import Foundation

actor PollingService {
    private let persistence: PersistenceService
    private let githubClient: GitHubClient
    private let buildkiteClient: BuildkiteClient
    private let categorizationService: CategorizationService
    private var settings: AppSettings
    private var isPolling = false

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

        // Cache CODEOWNERS per repo
        var codeownersCache: [String: String?] = [:]

        var allPRs: [PullRequest] = []

        for repoConfig in settings.repos {
            let repo = repoConfig.repo

            // Fetch CODEOWNERS (cached)
            if codeownersCache[repo] == nil {
                let cached = await persistence.loadCodeowners(forRepo: repo)
                if let cached {
                    codeownersCache[repo] = cached
                } else {
                    let fetched = try? await githubClient.fetchCodeowners(repo: repo)
                    codeownersCache[repo] = fetched
                    if let fetched {
                        try? await persistence.saveCodeowners(fetched, forRepo: repo)
                    }
                }
            }

            // Fetch review requests
            let fetchedPRs = try await githubClient.fetchReviewRequests(
                repo: repo,
                username: settings.githubUsername
            )

            for var pr in fetchedPRs {
                pr.isRequestedReviewer = true

                // Check if mentioned
                let isMentioned = (try? await githubClient.isUserMentioned(
                    repo: repo,
                    number: pr.number,
                    username: settings.githubUsername
                )) ?? false
                pr.isMentioned = isMentioned

                // Preserve user overrides from existing data
                if let existing = existingByID[pr.id] {
                    pr.isFlagged = existing.isFlagged
                    if existing.categoryOverridden {
                        pr.category = existing.category
                        pr.categoryOverridden = true
                        pr.categoryReason = existing.categoryReason
                        pr.lastCategorizedAt = existing.lastCategorizedAt
                    }
                }

                // Categorize if not already overridden
                if !pr.categoryOverridden {
                    let result = await categorizationService.categorize(
                        pr: pr,
                        codeowners: codeownersCache[repo] ?? nil,
                        userContext: settings.codeownerContext
                    )
                    pr.category = result.category
                    pr.categoryReason = result.reason
                    pr.lastCategorizedAt = Date()
                }

                // Fetch build status
                let pipelineSlug = BuildkiteClient.pipelineSlug(
                    forRepo: repo,
                    override: repoConfig.buildkitePipeline
                )
                pr.buildStatus = try? await buildkiteClient.fetchBuildStatus(
                    pipelineSlug: pipelineSlug,
                    branch: pr.headBranch
                )

                allPRs.append(pr)
            }
        }

        // Mark previously-known PRs as merged/closed if they disappeared
        for (id, existing) in existingByID {
            if !allPRs.contains(where: { $0.id == id }) {
                var merged = existing
                merged.isMerged = true
                // Keep flagged merged PRs
                if merged.isFlagged {
                    allPRs.append(merged)
                }
            }
        }

        // Save
        try await persistence.savePullRequests(allPRs)

        return allPRs
    }
}
