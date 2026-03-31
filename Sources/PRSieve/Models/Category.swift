import Foundation

enum PRCategory: String, Codable, CaseIterable, Comparable, Sendable {
    case priority = "priority"
    case low = "low"
    case noise = "noise"

    var displayName: String {
        switch self {
        case .priority: "Priority"
        case .low: "Low"
        case .noise: "Noise"
        }
    }

    var sortOrder: Int {
        switch self {
        case .priority: 0
        case .low: 1
        case .noise: 2
        }
    }

    static func < (lhs: PRCategory, rhs: PRCategory) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
