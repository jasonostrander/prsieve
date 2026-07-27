import Foundation

enum RequiredChecksStatus: String, Codable, Sendable, Equatable {
    case passed
    case failed
    case running
    case unknown
}

enum MergeableState: String, Codable, Sendable, Equatable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

enum MergeStateStatus: String, Codable, Sendable, Equatable {
    case behind = "BEHIND"
    case blocked = "BLOCKED"
    case clean = "CLEAN"
    case dirty = "DIRTY"
    case draft = "DRAFT"
    case hasHooks = "HAS_HOOKS"
    case unstable = "UNSTABLE"
    case unknown = "UNKNOWN"
}

enum ReviewDecision: String, Codable, Sendable, Equatable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum ReadinessOutcome: String, Codable, Sendable, Equatable {
    case ready
    case blocked
    case unknown
}

enum ReadinessBlocker: String, Codable, Sendable, Equatable {
    case closed
    case draft
    case checksFailed
    case checksRunning
    case checksUnknown
    case mergeConflict
    case branchBehind
    case changesRequested
    case approvalAlreadySatisfied
    case reviewNotRequired
    case restrictedFiles
    case unsupportedRule
    case missingRequiredCheck
    case headChanged
    case githubStateUnknown
}

struct PRReadiness: Codable, Sendable, Equatable {
    var outcome: ReadinessOutcome
    var requiredChecksStatus: RequiredChecksStatus
    var mergeableState: MergeableState
    var mergeStateStatus: MergeStateStatus
    var reviewDecision: ReviewDecision?
    var blocker: ReadinessBlocker?
    var checkedAt: Date

    static func unknown(_ blocker: ReadinessBlocker = .githubStateUnknown) -> PRReadiness {
        PRReadiness(
            outcome: .unknown,
            requiredChecksStatus: .unknown,
            mergeableState: .unknown,
            mergeStateStatus: .unknown,
            reviewDecision: nil,
            blocker: blocker,
            checkedAt: Date()
        )
    }
}

enum CheckResult: Sendable, Equatable {
    case passed
    case failed
    case running
    case unknown
}

struct CheckContext: Sendable, Equatable {
    let name: String
    let isRequired: Bool
    let result: CheckResult
}

struct ActiveBranchRules: Sendable, Equatable {
    let requiredCheckNames: Set<String>
    let strictRequiredChecks: Bool
    let restrictedFilePatterns: [String]
    let hasUnsupportedBlockingRules: Bool

    static let none = ActiveBranchRules(
        requiredCheckNames: [],
        strictRequiredChecks: false,
        restrictedFilePatterns: [],
        hasUnsupportedBlockingRules: false
    )
}

enum ReadinessEvaluator {
    static func requiredChecksStatus(
        contexts: [CheckContext],
        rules: ActiveBranchRules
    ) -> (status: RequiredChecksStatus, missingRequiredCheck: Bool) {
        let required = contexts.filter(\.isRequired)
        let presentNames = Set(required.map(\.name))
        let missing = !rules.requiredCheckNames.isSubset(of: presentNames)

        if required.contains(where: { $0.result == .failed }) {
            return (.failed, missing)
        }
        if missing || required.contains(where: { $0.result == .running }) {
            return (.running, missing)
        }
        if required.contains(where: { $0.result == .unknown }) {
            return (.unknown, missing)
        }
        return (.passed, missing)
    }

    static func evaluate(
        state: String,
        isDraft: Bool,
        mergeableState: MergeableState,
        mergeStateStatus: MergeStateStatus,
        reviewDecision: ReviewDecision?,
        contexts: [CheckContext],
        rules: ActiveBranchRules,
        filesChanged: [String],
        headMatches: Bool,
        checkedAt: Date = Date()
    ) -> PRReadiness {
        let checks = requiredChecksStatus(contexts: contexts, rules: rules)

        func result(_ outcome: ReadinessOutcome, _ blocker: ReadinessBlocker?) -> PRReadiness {
            PRReadiness(
                outcome: outcome,
                requiredChecksStatus: checks.status,
                mergeableState: mergeableState,
                mergeStateStatus: mergeStateStatus,
                reviewDecision: reviewDecision,
                blocker: blocker,
                checkedAt: checkedAt
            )
        }

        guard headMatches else { return result(.unknown, .headChanged) }
        guard state == "OPEN" else { return result(.blocked, .closed) }
        guard !isDraft else { return result(.blocked, .draft) }
        guard !rules.hasUnsupportedBlockingRules else {
            return result(.unknown, .unsupportedRule)
        }
        guard !touchesRestrictedFile(filesChanged, patterns: rules.restrictedFilePatterns) else {
            return result(.blocked, .restrictedFiles)
        }

        switch mergeableState {
        case .conflicting:
            return result(.blocked, .mergeConflict)
        case .unknown:
            return result(.unknown, .githubStateUnknown)
        case .mergeable:
            break
        }

        switch mergeStateStatus {
        case .unknown:
            return result(.unknown, .githubStateUnknown)
        case .dirty:
            return result(.blocked, .mergeConflict)
        case .draft:
            return result(.blocked, .draft)
        case .behind where rules.strictRequiredChecks:
            return result(.blocked, .branchBehind)
        default:
            break
        }

        switch checks.status {
        case .failed:
            return result(.blocked, .checksFailed)
        case .running:
            return result(.blocked, checks.missingRequiredCheck ? .missingRequiredCheck : .checksRunning)
        case .unknown:
            return result(.unknown, .checksUnknown)
        case .passed:
            break
        }

        switch reviewDecision {
        case .reviewRequired:
            return result(.ready, nil)
        case .changesRequested:
            return result(.blocked, .changesRequested)
        case .approved:
            return result(.blocked, .approvalAlreadySatisfied)
        case nil:
            return result(.blocked, .reviewNotRequired)
        }
    }

    static func touchesRestrictedFile(_ files: [String], patterns: [String]) -> Bool {
        files.contains { path in patterns.contains { glob($0, matches: path) } }
    }

    private static func glob(_ pattern: String, matches path: String) -> Bool {
        var regex = "^"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"
                    index = pattern.index(after: next)
                    continue
                }
                regex += "[^/]*"
            } else if character == "?" {
                regex += "[^/]"
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = pattern.index(after: index)
        }
        regex += "$"
        return path.range(of: regex, options: .regularExpression) != nil
    }
}
