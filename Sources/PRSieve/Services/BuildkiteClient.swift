import Foundation

actor BuildkiteClient {
    private let session: URLSession
    private var token: String
    private var orgSlug: String
    private let baseURL = URL(string: "https://api.buildkite.com/v2")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(token: String, orgSlug: String) {
        self.token = token
        self.orgSlug = orgSlug
        self.session = URLSession(configuration: .default)
    }

    func updateCredentials(token: String, orgSlug: String) {
        self.token = token
        self.orgSlug = orgSlug
    }

    /// Fetch build status for a given branch in a pipeline.
    /// Pipeline slug defaults to repo name if not specified.
    func fetchBuildStatus(pipelineSlug: String, branch: String) async throws -> BuildStatus {
        guard !token.isEmpty, !orgSlug.isEmpty else { return .unknown }

        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("organizations")
                .appendingPathComponent(orgSlug)
                .appendingPathComponent("pipelines")
                .appendingPathComponent(pipelineSlug)
                .appendingPathComponent("builds"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "branch", value: branch),
            URLQueryItem(name: "per_page", value: "1"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return .unknown
        }

        let builds = try decoder.decode([BuildkiteBuild].self, from: data)
        guard let latest = builds.first else { return .unknown }

        switch latest.state {
        case "passed": return .passed
        case "failed", "canceled": return .failed
        case "running", "scheduled", "blocked": return .running
        default: return .unknown
        }
    }

    /// Derive pipeline slug from repo name. Convention: repo name is the pipeline slug.
    static func pipelineSlug(forRepo repo: String, override: String?) -> String {
        if let override, !override.isEmpty { return override }
        return repo.split(separator: "/").last.map(String.init) ?? repo
    }
}

// MARK: - Buildkite API Types

struct BuildkiteBuild: Decodable, Sendable {
    let id: String
    let number: Int
    let state: String
    let webUrl: String
    let branch: String
}
