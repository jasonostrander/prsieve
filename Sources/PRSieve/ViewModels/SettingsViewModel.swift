import SwiftUI

@MainActor @Observable
final class SettingsViewModel {
    var settings: AppSettings = .default
    var githubToken: String = ""
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
        if settings.llmModel.isEmpty {
            settings.llmModel = LLMConfig.loadFromBundle().model
        }
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
