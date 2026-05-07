import SwiftUI

enum LLMTestResult {
    case success
    case failure(String)
}

@MainActor @Observable
final class SettingsViewModel {
    var settings: AppSettings = .default
    var githubToken: String = ""
    var newRepoText: String = ""
    var isSaving = false
    var saveError: String?
    var llmTestResult: LLMTestResult?
    var isTestingLLM = false
    var notificationAuthState: NotificationAuthState = .notDetermined
    var isRequestingNotifications = false

    private let persistence: PersistenceService

    init(persistence: PersistenceService) {
        self.persistence = persistence
    }

    func load() async {
        settings = await persistence.loadSettings()
        githubToken = await persistence.loadToken(forKey: "github_token") ?? ""
        if settings.llmModel.isEmpty {
            settings.llmModel = LLMConfig.loadFromBundle().model
        }
        // Auth state is fetched lazily by the view via refreshNotificationAuthState().
    }

    func refreshNotificationAuthState() async {
        notificationAuthState = await NotificationService.systemAuthorizationState()
    }

    func requestNotificationPermission() async {
        isRequestingNotifications = true
        notificationAuthState = await NotificationService.requestSystemAuthorization()
        isRequestingNotifications = false
    }

    func openNotificationSystemSettings() {
        NotificationService.openSystemSettings()
    }

    func save() async {
        isSaving = true
        saveError = nil
        do {
            try await persistence.saveSettings(settings)
            await persistence.saveToken(githubToken, forKey: "github_token")
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    func testLLMConfig() async {
        let bundleConfig = LLMConfig.loadFromBundle()
        let model = settings.llmModel
        guard !bundleConfig.endpoint.isEmpty, bundleConfig.apiKey != "sk-..." else {
            llmTestResult = .failure("LLM endpoint or API key not configured in llm_config.json.")
            return
        }
        isTestingLLM = true
        llmTestResult = nil
        let client = LLMClient(endpoint: bundleConfig.endpoint, apiKey: bundleConfig.apiKey, model: model)
        do {
            _ = try await client.complete(
                systemPrompt: "Reply with exactly: {\"category\":\"low\",\"reason\":\"ok\"}",
                userPrompt: "test"
            )
            llmTestResult = .success
        } catch let err as LLMError {
            switch err {
            case .notConfigured:
                llmTestResult = .failure("LLM is not configured.")
            case .requestFailed(let msg):
                let lower = msg.lowercased()
                if lower.contains("401") || lower.contains("unauthorized") {
                    llmTestResult = .failure("Authentication failed — check API key in llm_config.json.")
                } else if lower.contains("404") || lower.contains("not found") {
                    llmTestResult = .failure("Model \"\(model)\" not found.")
                } else if lower.contains("429") || lower.contains("rate limit") {
                    llmTestResult = .failure("Rate limit reached — try again in a moment.")
                } else {
                    llmTestResult = .failure("Request failed: \(msg)")
                }
            case .emptyResponse:
                llmTestResult = .failure("LLM returned an empty response.")
            }
        } catch {
            llmTestResult = .failure(error.localizedDescription)
        }
        isTestingLLM = false
    }

    func addRepo() {
        let repo = newRepoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, repo.contains("/") else { return }
        guard !settings.repos.contains(where: { $0.repo == repo }) else { return }
        settings.repos.append(RepoConfig(repo: repo))
        newRepoText = ""
    }

    func removeRepo(at offsets: IndexSet) {
        settings.repos.remove(atOffsets: offsets)
    }
}
