import Foundation

enum ReviewStatus: String, Codable, Sendable {
    case pending
    case approved
    case changesRequested = "changes_requested"
    case dismissed
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
    let body: String?
    let filesChanged: [String]

    var reviewStatus: ReviewStatus
    var isRequestedReviewer: Bool
    var isMentioned: Bool
    var category: PRCategory
    var categoryOverridden: Bool
    var categoryReason: String
    var buildStatus: BuildStatus?
    var isMerged: Bool
    var isClosed: Bool
    var isFlagged: Bool
    var lastCategorizedAt: Date?

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
