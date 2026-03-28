import Foundation

actor GitHubClient {
    private let session: URLSession
    private var token: String
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

    // MARK: - Fetch PRs requesting review from user

    func fetchReviewRequests(repo: String, username: String) async throws -> [PullRequest] {
        // Get PRs where user is a requested reviewer
        let searchQuery = "repo:\(repo) is:pr is:open review-requested:\(username)"
        let prs = try await searchPRs(query: searchQuery)

        // Also get PRs assigned to user as reviewer via team
        let teamQuery = "repo:\(repo) is:pr is:open user-review-requested:\(username)"
        let teamPRs = try await searchPRs(query: teamQuery)

        // Merge, deduplicate by number
        var seen = Set<String>()
        var result: [PullRequest] = []
        for pr in prs + teamPRs {
            if seen.insert(pr.id).inserted {
                result.append(pr)
            }
        }
        return result
    }

    private func searchPRs(query: String) async throws -> [PullRequest] {
        var components = URLComponents(url: baseURL.appendingPathComponent("search/issues"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "sort", value: "updated"),
        ]

        let data = try await fetch(components.url!)
        let searchResult = try decoder.decode(GitHubSearchResult.self, from: data)

        // Search API returns minimal data; we need to fetch full PR details
        var pullRequests: [PullRequest] = []
        for item in searchResult.items {
            if let pr = try? await fetchPRDetail(repo: item.repoFullName, number: item.number) {
                pullRequests.append(pr)
            }
        }
        return pullRequests
    }

    // MARK: - Fetch full PR detail

    func fetchPRDetail(repo: String, number: Int) async throws -> PullRequest {
        let url = baseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repo)
            .appendingPathComponent("pulls")
            .appendingPathComponent("\(number)")
        let data = try await fetch(url)
        let ghPR = try decoder.decode(GitHubPR.self, from: data)

        // Fetch files changed
        let filesURL = url.appendingPathComponent("files")
        let filesData = try await fetch(filesURL)
        let files = try decoder.decode([GitHubFile].self, from: filesData)

        // Fetch reviews to determine review status
        let reviewsURL = url.appendingPathComponent("reviews")
        let reviewsData = try await fetch(reviewsURL)
        let reviews = try decoder.decode([GitHubReview].self, from: reviewsData)

        let reviewStatus = Self.latestReviewStatus(from: reviews)

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
            reviewStatus: reviewStatus,
            isRequestedReviewer: false, // will be set by caller
            isMentioned: false, // will be determined separately
            category: .fyi, // default, will be categorized
            categoryOverridden: false,
            categoryReason: "",
            buildStatus: nil,
            isMerged: ghPR.merged ?? false,
            isClosed: ghPR.state == "closed",
            isFlagged: false,
            lastCategorizedAt: nil
        )
    }

    // MARK: - CODEOWNERS

    func fetchCodeowners(repo: String) async throws -> String? {
        let paths = [".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS"]
        for path in paths {
            let url = baseURL
                .appendingPathComponent("repos")
                .appendingPathComponent(repo)
                .appendingPathComponent("contents")
                .appendingPathComponent(path)
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
        let url = baseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repo)
            .appendingPathComponent("issues")
            .appendingPathComponent("\(number)")
            .appendingPathComponent("comments")
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

    private static func latestReviewStatus(from reviews: [GitHubReview]) -> ReviewStatus {
        // Get the most recent non-comment review
        let meaningful = reviews.filter { $0.state != "COMMENTED" }
        guard let latest = meaningful.last else { return .pending }
        switch latest.state {
        case "APPROVED": return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "DISMISSED": return .dismissed
        default: return .pending
        }
    }
}

// MARK: - GitHub API Response Types

enum GitHubError: Error, Sendable {
    case invalidResponse
    case httpError(Int, String?)
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
