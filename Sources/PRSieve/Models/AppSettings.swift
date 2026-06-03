import Foundation

struct RepoConfig: Codable, Sendable, Identifiable, Hashable {
    var id: String { repo }
    let repo: String  // "owner/repo"
    var buildkitePipeline: String?  // optional override for pipeline slug
}

struct AppSettings: Codable, Sendable, Equatable {
    var githubUsername: String = ""
    var repos: [RepoConfig] = []
    var buildkiteOrgSlug: String = ""
    var codeownerContext: String = ""
    var llmModel: String = ""
    var pollingIntervalSeconds: Int = 1800
    var hideDraftPRs: Bool = true
    var notificationsEnabled: Bool = true
    var keepUnreviewedPriorityAfterMerge: Bool = true
    var ignoredCIChecks: [String] = ["danger/danger"]
    var launchAtLogin: Bool = false

    /// Bumped whenever a one-time settings migration must run on load. Persisted so
    /// each migration fires exactly once per user. Files written before this field
    /// existed decode as 0, which triggers every migration gated above it.
    var schemaVersion: Int = AppSettings.currentSchemaVersion

    /// Current settings schema version.
    /// v1: force the polling interval to the new 30-minute default for users
    /// upgrading from a build with the retired 1/2/5/10-minute options.
    static let currentSchemaVersion = 1

    static let `default` = AppSettings()

    /// Default refresh interval (30 minutes) and the values offered in Settings.
    static let defaultPollingInterval = 1800
    static let allowedPollingIntervals = [900, 1800, 3600, 7200]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        githubUsername = try container.decodeIfPresent(String.self, forKey: .githubUsername) ?? ""
        repos = try container.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
        buildkiteOrgSlug = try container.decodeIfPresent(String.self, forKey: .buildkiteOrgSlug) ?? ""
        codeownerContext = try container.decodeIfPresent(String.self, forKey: .codeownerContext) ?? ""
        llmModel = try container.decodeIfPresent(String.self, forKey: .llmModel) ?? ""
        hideDraftPRs = try container.decodeIfPresent(Bool.self, forKey: .hideDraftPRs) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        keepUnreviewedPriorityAfterMerge = try container.decodeIfPresent(Bool.self, forKey: .keepUnreviewedPriorityAfterMerge) ?? true
        ignoredCIChecks = try container.decodeIfPresent([String].self, forKey: .ignoredCIChecks) ?? ["danger/danger"]
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false

        // Files predating `schemaVersion` decode as 0, so any migration runs once.
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        let decodedInterval = try container.decodeIfPresent(Int.self, forKey: .pollingIntervalSeconds) ?? AppSettings.defaultPollingInterval

        if decodedSchemaVersion < 1 {
            // v1 migration: upgraders polled far too often — reset everyone to 30 min.
            pollingIntervalSeconds = AppSettings.defaultPollingInterval
        } else if AppSettings.allowedPollingIntervals.contains(decodedInterval) {
            pollingIntervalSeconds = decodedInterval
        } else {
            // A current-schema file with an unexpected value (hand-edited/corrupt).
            pollingIntervalSeconds = AppSettings.defaultPollingInterval
        }

        schemaVersion = AppSettings.currentSchemaVersion
    }
}
