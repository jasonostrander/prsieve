import SwiftUI

@MainActor @Observable
final class SettingsViewModel {
    var settings: AppSettings = .default
    var githubToken: String = ""
    var buildkiteToken: String = ""
    var llmAPIKey: String = ""
    var newRepoText: String = ""
    var isSaving = false
    var saveError: String?

    private let persistence: PersistenceService

    init(persistence: PersistenceService) {
        self.persistence = persistence
    }

    func load() async {
        settings = await persistence.loadSettings()
        githubToken = await persistence.loadToken(forKey: "github_token") ?? ""
        buildkiteToken = await persistence.loadToken(forKey: "buildkite_token") ?? ""
        llmAPIKey = await persistence.loadToken(forKey: "llm_api_key") ?? ""
    }

    func save() async {
        isSaving = true
        saveError = nil
        do {
            try await persistence.saveSettings(settings)
            await persistence.saveToken(githubToken, forKey: "github_token")
            await persistence.saveToken(buildkiteToken, forKey: "buildkite_token")
            await persistence.saveToken(llmAPIKey, forKey: "llm_api_key")
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
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
