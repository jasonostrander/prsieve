import Foundation

enum PRCategory: String, Codable, CaseIterable, Comparable, Sendable {
    case mustReview = "must-review"
    case shouldKnow = "should-know"
    case fyi = "fyi"

    var displayName: String {
        switch self {
        case .mustReview: "Must Review"
        case .shouldKnow: "Should Know"
        case .fyi: "FYI"
        }
    }

    var sortOrder: Int {
        switch self {
        case .mustReview: 0
        case .shouldKnow: 1
        case .fyi: 2
        }
    }

    static func < (lhs: PRCategory, rhs: PRCategory) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
