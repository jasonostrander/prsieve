import Foundation

actor LLMClient {
    private let session = URLSession(configuration: .default)
    private var endpoint: String
    private var apiKey: String
    private var model: String

    private let decoder = JSONDecoder()

    init(endpoint: String, apiKey: String, model: String) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
    }

    func updateConfig(endpoint: String, apiKey: String, model: String) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
    }

    struct ChatMessage: Encodable, Sendable {
        let role: String
        let content: String
    }

    struct ChatRequest: Encodable, Sendable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxTokens = "max_tokens"
        }
    }

    struct ChatResponse: Decodable, Sendable {
        let choices: [Choice]

        struct Choice: Decodable, Sendable {
            let message: ResponseMessage
        }
        struct ResponseMessage: Decodable, Sendable {
            let content: String
        }
    }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        guard !endpoint.isEmpty, !apiKey.isEmpty else {
            throw LLMError.notConfigured
        }

        let url = URL(string: endpoint.hasSuffix("/")
            ? "\(endpoint)chat/completions"
            : "\(endpoint)/chat/completions")!

        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt),
            ],
            temperature: 0,
            maxTokens: 200
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.requestFailed(String(data: data, encoding: .utf8) ?? "unknown")
        }

        let chatResponse = try decoder.decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }
        return content
    }
}

enum LLMError: Error, Sendable {
    case notConfigured
    case requestFailed(String)
    case emptyResponse
}
