import Foundation

struct LLMConfig: Codable, Sendable, Equatable {
    let endpoint: String
    let apiKey: String
    let model: String

    enum CodingKeys: String, CodingKey {
        case endpoint
        case apiKey = "token"
        case model
    }

    static let empty = LLMConfig(endpoint: "", apiKey: "", model: "")

    static func loadFromBundle() -> LLMConfig {
        // Bundled as a binary plist (corporate DLP can strip plain JSON from DMGs)
        if let url = Bundle.main.url(forResource: "llm_config", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let config = try? PropertyListDecoder().decode(LLMConfig.self, from: data) {
            return config
        }
        if let url = Bundle.main.url(forResource: "llm_config", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            return config
        }
        return .empty
    }
}
