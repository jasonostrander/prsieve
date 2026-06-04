import Foundation

enum ReviewStatus: String, Codable, Sendable {
    case pending
    case approved
    case changesRequested = "changes_requested"
    case commented
    case dismissed

    /// Map from GitHub API review state strings (e.g. "APPROVED") to our enum.
    init(githubState: String) {
        switch githubState {
        case "APPROVED": self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        case "COMMENTED": self = .commented
        case "DISMISSED": self = .dismissed
        default: self = .pending
        }
    }
}

struct ReviewerInfo: Codable, Sendable, Identifiable {
    var id: String { login }
    let login: String
    let avatarURL: URL?
    let state: ReviewStatus
}

struct PullRequest: Identifiable, Codable, Sendable {
    /// Unique identifier: "owner/repo#number"
    var id: String { "\(repoFullName)#\(number)" }

    let repoFullName: String
    let number: Int
    let title: String
    let author: String
    let authorAvatarURL: URL?
    let htmlURL: URL
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let labels: [String]
    let headBranch: String
    let baseBranch: String
    /// HEAD commit SHA. Lets polling refresh CI status on its own (one
    /// `/commits/{sha}/status` call) without a full detail fetch when a PR's
    /// `updatedAt` is unchanged but its CI may still be in flight. `nil` for PRs
    /// persisted before this field existed (forces a one-time full re-fetch).
    let headSHA: String?
    let body: String?
    let filesChanged: [String]

    var reviewers: [ReviewerInfo]
    var humanCommentCount: Int
    var isRequestedReviewer: Bool
    var isDirectCodeowner: Bool
    var isMentioned: Bool
    var isSoleHumanReviewer: Bool
    var category: PRCategory
    var categoryOverridden: Bool
    var categoryReason: String
    var buildStatus: BuildStatus?
    var isMerged: Bool
    var isClosed: Bool
    var isFlagged: Bool
    var lastCategorizedAt: Date?

    /// Fingerprint of the categorization inputs (system prompt, ownership context,
    /// username, codeowner/reviewer flags) used the last time this PR was
    /// categorized. Lets polling skip re-running categorization — and the LLM call
    /// it implies — when nothing that could change the verdict has changed.
    /// `nil` for PRs categorized before this field existed, forcing one recompute.
    var categorizationContextHash: String?

    var age: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }

    var ageDescription: String {
        let hours = Int(age / 3600)
        if hours < 1 { return "< 1h" }
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days == 1 { return "1 day" }
        return "\(days) days"
    }

    var repoShortName: String {
        repoFullName.split(separator: "/").last.map(String.init) ?? repoFullName
    }
}
