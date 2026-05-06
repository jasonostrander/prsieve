import SwiftUI

@MainActor @Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case welcome
        case github
        case prompt
        case done

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    var step: Step = .welcome
    var githubUsername: String = ""
    var githubToken: String = ""
    var repos: [RepoConfig] = []
    var newRepoText: String = ""
    var codeownerContext: String = ""
    var saveError: String?

    private let persistence: PersistenceService

    init(persistence: PersistenceService) {
        self.persistence = persistence
    }

    func load() async {
        let settings = await persistence.loadSettings()
        githubUsername = settings.githubUsername
        repos = settings.repos
        codeownerContext = settings.codeownerContext
        githubToken = await persistence.loadToken(forKey: "github_token") ?? ""
    }

    func addRepo() {
        let repo = newRepoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, repo.contains("/") else { return }
        guard !repos.contains(where: { $0.repo == repo }) else { return }
        repos.append(RepoConfig(repo: repo))
        newRepoText = ""
    }

    func removeRepo(at offsets: IndexSet) {
        repos.remove(atOffsets: offsets)
    }

    var canAdvanceFromGitHub: Bool {
        !githubUsername.trimmingCharacters(in: .whitespaces).isEmpty
            && !githubToken.trimmingCharacters(in: .whitespaces).isEmpty
            && !repos.isEmpty
    }

    var canAdvanceFromPrompt: Bool {
        !codeownerContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func advance() async {
        await persist()
        if let next = step.next {
            step = next
        }
    }

    func goBack() {
        if let prev = step.previous {
            step = prev
        }
    }

    func finish() async {
        await persist()
    }

    private func persist() async {
        do {
            var settings = await persistence.loadSettings()
            settings.githubUsername = githubUsername.trimmingCharacters(in: .whitespaces)
            settings.repos = repos
            settings.codeownerContext = codeownerContext
            try await persistence.saveSettings(settings)
            await persistence.saveToken(githubToken.trimmingCharacters(in: .whitespaces), forKey: "github_token")
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
