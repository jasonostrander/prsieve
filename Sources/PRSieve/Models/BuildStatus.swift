import Foundation

enum BuildStatus: String, Codable, Sendable {
    case passed
    case failed
    case running
    case unknown

    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .running: "arrow.triangle.2.circlepath"
        case .unknown: "questionmark.circle"
        }
    }

    var colorName: String {
        switch self {
        case .passed: "green"
        case .failed: "red"
        case .running: "orange"
        case .unknown: "gray"
        }
    }
}
