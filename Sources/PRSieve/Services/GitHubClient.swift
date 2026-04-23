import Foundation

actor GitHubClient {
    private let session: URLSession
    private var token: String
    private var ignoredCIChecks: Set<String> = ["danger/danger"]
    private let baseURL = URL(string: "https://api.github.com")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        self.session = URLSession(configuration: config)
    }

    func updateToken(_ token: String) {
        self.token = token
    }

    func updateIgnoredCIChecks(_ checks: [String]) {
        ignoredCIChecks = Set(checks)
    }

    // MARK: - Fetch PRs requesting review from user

    func fetchReviewRequests(repo: String, username: String) async throws -> [PullRequest] {
        let searchQuery = "repo:\(repo) is:pr is:open review-requested:\(username)"
        let teamQuery = "repo:\(repo) is:pr is:open user-review-requested:\(username)"

        // Run both searches in parallel
        async let items1 = searchItems(query: searchQuery)
        async let items2 = searchItems(query: teamQuery)

        // Dedup by PR number before fetching details (avoids duplicate API calls)
        var seen = Set<Int>()
        var uniqueItems: [GitHubSearchItem] = []
        for item in try await items1 + items2 {
            if seen.insert(item.number).inserted {
                uniqueItems.append(item)
            }
        }

        // Fetch PR details concurrently (bounded to 5 at a time)
        return try await fetchDetailsConcurrently(items: uniqueItems, username: username)
    }

    private func searchItems(query: String) async throws -> [GitHubSearchItem] {
        var components = URLComponents(url: baseURL.appendingPathComponent("search/issues"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "sort", value: "updated"),
        ]

        let data = try await fetch(components.url!)
        let searchResult = try decoder.decode(GitHubSearchResult.self, from: data)
        return searchResult.items
    }

    private func fetchDetailsConcurrently(items: [GitHubSearchItem], username: String) async throws -> [PullRequest] {
        try await withThrowingTaskGroup(of: PullRequest?.self) { group in
            let maxConcurrency = 5
            var results: [PullRequest] = []
            var index = 0

            // Seed initial batch
            for _ in 0..<min(maxConcurrency, items.count) {
                let item = items[index]
                index += 1
                group.addTask {
                    try? await self.fetchPRDetail(repo: item.repoFullName, number: item.number, username: username)
                }
            }

            // As each completes, start the next
            for try await pr in group {
                if let pr { results.append(pr) }
                if index < items.count {
                    let item = items[index]
                    index += 1
                    group.addTask {
                        try? await self.fetchPRDetail(repo: item.repoFullName, number: item.number, username: username)
                    }
                }
            }

            return results
        }
    }

    // MARK: - URL Helpers

    /// Build a URL path without percent-encoding slashes in repo names.
    private func repoURL(_ repo: String, path: String = "") -> URL {
        // repo is "owner/repo", path is e.g. "/pulls/123"
        let urlString = "\(baseURL)/repos/\(repo)\(path)"
        return URL(string: urlString)!
    }

    // MARK: - Fetch full PR detail

    func fetchPRDetail(repo: String, number: Int, username: String? = nil) async throws -> PullRequest {
        let url = repoURL(repo, path: "/pulls/\(number)")
        let data = try await fetch(url)
        let ghPR = try decoder.decode(GitHubPR.self, from: data)

        // Fetch supplemental data in parallel
        async let filesData = fetch(repoURL(repo, path: "/pulls/\(number)/files"))
        async let reviewsData = fetch(repoURL(repo, path: "/pulls/\(number)/reviews"))
        async let reviewCommentsData = fetch(repoURL(repo, path: "/pulls/\(number)/comments"))
        async let issueCommentsData = fetch(repoURL(repo, path: "/issues/\(number)/comments"))
        async let statusResult = fetchCombinedStatus(repo: repo, ref: ghPR.head.sha)

        let files = try decoder.decode([GitHubFile].self, from: try await filesData)
        let reviews = try decoder.decode([GitHubReview].self, from: try await reviewsData)
        let reviewComments = try decoder.decode([GitHubComment].self, from: try await reviewCommentsData)
        let issueComments = try decoder.decode([GitHubComment].self, from: try await issueCommentsData)
        let buildStatus = try await statusResult

        let reviewers = Self.perReviewerStatus(from: reviews)

        let humanCommentCount = (reviewComments + issueComments)
            .filter { !Self.isBot($0.user.login) }
            .filter { $0.user.login != ghPR.user.login }
            .count

        // Check if user is mentioned (avoids a separate API call later)
        let isMentioned: Bool
        if let username {
            let mention = "@\(username)"
            isMentioned = issueComments.contains { $0.body.contains(mention) }
        } else {
            isMentioned = false
        }

        return PullRequest(
            repoFullName: repo,
            number: ghPR.number,
            title: ghPR.title,
            author: ghPR.user.login,
            authorAvatarURL: URL(string: ghPR.user.avatarUrl),
            htmlURL: URL(string: ghPR.htmlUrl)!,
            createdAt: ghPR.createdAt,
            updatedAt: ghPR.updatedAt,
            isDraft: ghPR.draft ?? false,
            labels: ghPR.labels.map(\.name),
            headBranch: ghPR.head.ref,
            baseBranch: ghPR.base.ref,
            body: String(ghPR.body?.prefix(1000) ?? ""),
            filesChanged: files.map(\.filename),
            reviewers: reviewers,
            humanCommentCount: humanCommentCount,
            isRequestedReviewer: false,
            isDirectCodeowner: false,
            isMentioned: isMentioned,
            category: .low,
            categoryOverridden: false,
            categoryReason: "",
            buildStatus: buildStatus,
            isMerged: ghPR.merged ?? false,
            isClosed: ghPR.state == "closed",
            isFlagged: false,
            lastCategorizedAt: nil
        )
    }

    // MARK: - Combined CI Status

    func fetchCombinedStatus(repo: String, ref: String) async throws -> BuildStatus {
        let url = repoURL(repo, path: "/commits/\(ref)/status")
        do {
            let data = try await fetch(url)
            let status = try decoder.decode(GitHubCombinedStatus.self, from: data)

            // If no ignored checks configured, use the pre-rolled state from GitHub
            if ignoredCIChecks.isEmpty {
                switch status.state {
                case "success": return .passed
                case "failure", "error": return .failed
                case "pending": return status.totalCount == 0 ? .unknown : .running
                default: return .unknown
                }
            }

            // Filter out ignored checks and recompute state from the remaining ones
            let relevant = status.statuses.filter { !ignoredCIChecks.contains($0.context) }

            if relevant.isEmpty {
                // All checks were ignored (or no checks at all)
                return status.statuses.isEmpty ? .unknown : .passed
            }

            if relevant.contains(where: { $0.state == "failure" || $0.state == "error" }) {
                return .failed
            }
            if relevant.contains(where: { $0.state == "pending" }) {
                return .running
            }
            if relevant.allSatisfy({ $0.state == "success" }) {
                return .passed
            }
            return .unknown
        } catch {
            return .unknown
        }
    }

    // MARK: - Fetch open PRs the user has previously reviewed/commented on

    func fetchReviewedByUser(repo: String, username: String) async throws -> [PullRequest] {
        let query = "repo:\(repo) is:pr is:open reviewed-by:\(username)"
        let items = try await searchItems(query: query)
        return try await fetchDetailsConcurrently(items: items, username: username)
    }

    // MARK: - Lightweight PR state check

    /// Fetch only the state of a PR (open/closed/merged) without supplemental data.
    func fetchPRState(repo: String, number: Int) async throws -> (isMerged: Bool, isClosed: Bool) {
        let url = repoURL(repo, path: "/pulls/\(number)")
        let data = try await fetch(url)
        let ghPR = try decoder.decode(GitHubPRState.self, from: data)
        return (isMerged: ghPR.merged ?? false, isClosed: ghPR.state == "closed")
    }

    // MARK: - CODEOWNERS

    func fetchCodeowners(repo: String) async throws -> String? {
        let paths = [".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS"]
        for path in paths {
            let url = repoURL(repo, path: "/contents/\(path)")
            do {
                let data = try await fetch(url)
                let file = try decoder.decode(GitHubContentFile.self, from: data)
                if let content = file.content,
                   let decoded = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: "")) {
                    return String(data: decoded, encoding: .utf8)
                }
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Check if user is mentioned in PR comments

    func isUserMentioned(repo: String, number: Int, username: String) async throws -> Bool {
        let url = repoURL(repo, path: "/issues/\(number)/comments")
        let data = try await fetch(url)
        let comments = try decoder.decode([GitHubComment].self, from: data)
        let mention = "@\(username)"
        return comments.contains { $0.body.contains(mention) }
    }

    // MARK: - Networking

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.httpError(http.statusCode, String(data: data, encoding: .utf8))
        }
        return data
    }

    // MARK: - Review Status Logic

    static func latestReviewStatus(from reviews: [GitHubReview]) -> ReviewStatus {
        let meaningful = reviews.filter { $0.state != "COMMENTED" }
        guard let latest = meaningful.last else { return .pending }
        return ReviewStatus(githubState: latest.state)
    }

    /// Build per-reviewer status from all reviews, taking each reviewer's latest state.
    static func perReviewerStatus(from reviews: [GitHubReview]) -> [ReviewerInfo] {
        let humanReviews = reviews.filter { !isBot($0.user.login) }

        var latestByLogin: [String: GitHubReview] = [:]
        for review in humanReviews {
            latestByLogin[review.user.login] = review
        }

        return latestByLogin.values
            .sorted { $0.user.login < $1.user.login }
            .map { review in
                ReviewerInfo(
                    login: review.user.login,
                    avatarURL: URL(string: review.user.avatarUrl),
                    state: ReviewStatus(githubState: review.state)
                )
            }
    }

    static func isBot(_ login: String) -> Bool {
        let lowered = login.lowercased()
        return lowered.hasSuffix("[bot]")
            || lowered.hasSuffix("-bot")
            || lowered.contains("machine-user")
            || lowered == "dependabot"
            || lowered == "renovate"
            || lowered == "codecov"
            || lowered == "sonarcloud"
            || lowered == "github-actions"
    }
}

// MARK: - GitHub API Response Types

enum GitHubError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub: Invalid response"
        case .httpError(401, _):
            return "GitHub: Authentication failed — check your token"
        case .httpError(403, let body):
            if body?.contains("rate limit") == true {
                return "GitHub: Rate limit exceeded — try again later"
            }
            return "GitHub: Forbidden (403) — check token scopes (needs repo access)"
        case .httpError(404, _):
            return "GitHub: Not found (404) — check repo name"
        case .httpError(422, let body):
            return "GitHub: Validation error (422) — \(body?.prefix(200) ?? "unknown")"
        case .httpError(let code, let body):
            return "GitHub: HTTP \(code) — \(body?.prefix(200) ?? "unknown")"
        }
    }
}

// Search API
struct GitHubSearchResult: Decodable, Sendable {
    let totalCount: Int
    let items: [GitHubSearchItem]
}

struct GitHubSearchItem: Decodable, Sendable {
    let number: Int
    let repositoryUrl: String

    var repoFullName: String {
        // repositoryUrl is like "https://api.github.com/repos/owner/repo"
        let parts = repositoryUrl.split(separator: "/")
        guard parts.count >= 2 else { return "" }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }
}

// PR detail
struct GitHubPR: Decodable, Sendable {
    let number: Int
    let title: String
    let body: String?
    let state: String
    let draft: Bool?
    let merged: Bool?
    let htmlUrl: String
    let createdAt: Date
    let updatedAt: Date
    let user: GitHubUser
    let head: GitHubRef
    let base: GitHubRef
    let labels: [GitHubLabel]
    let requestedReviewers: [GitHubUser]?
}

struct GitHubUser: Decodable, Sendable {
    let login: String
    let avatarUrl: String
}

struct GitHubRef: Decodable, Sendable {
    let ref: String
    let sha: String
}

struct GitHubLabel: Decodable, Sendable {
    let name: String
}

struct GitHubFile: Decodable, Sendable {
    let filename: String
}

struct GitHubReview: Decodable, Sendable {
    let state: String
    let user: GitHubUser
}

struct GitHubComment: Decodable, Sendable {
    let body: String
    let user: GitHubUser
}

struct GitHubContentFile: Decodable, Sendable {
    let content: String?
    let encoding: String?
}

// Lightweight PR state (for checking merged/closed without full detail fetch)
struct GitHubPRState: Decodable, Sendable {
    let state: String
    let merged: Bool?
}

// Combined commit status
struct GitHubCombinedStatus: Decodable, Sendable {
    let state: String  // "success", "failure", "error", "pending"
    let totalCount: Int
    let statuses: [GitHubStatusContext]

    enum CodingKeys: String, CodingKey {
        case state, statuses, totalCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(String.self, forKey: .state)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        statuses = try container.decodeIfPresent([GitHubStatusContext].self, forKey: .statuses) ?? []
    }
}

struct GitHubStatusContext: Decodable, Sendable {
    let state: String   // "success", "failure", "error", "pending"
    let context: String // e.g. "Buildkite", "danger/danger"
}
