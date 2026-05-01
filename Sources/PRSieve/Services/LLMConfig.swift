import Foundation

struct LLMConfig: Codable, Sendable, Equatable {
    let endpoint: String
    let apiKey: String
    let model: String

    static let empty = LLMConfig(endpoint: "", apiKey: "", model: "")

    static func loadFromBundle() -> LLMConfig {
        guard let url = Bundle.main.url(forResource: "llm_config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(LLMConfig.self, from: data) else {
            return .empty
        }
        return config
    }
}
