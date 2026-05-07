import SwiftUI

@MainActor @Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case welcome
        case github
        case prompt
        case notifications
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
    var notificationsEnabled: Bool = true
    var notificationAuthState: NotificationAuthState = .notDetermined
    var isRequestingNotifications = false
    var launchAtLogin: Bool = false
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
        notificationsEnabled = settings.notificationsEnabled
        launchAtLogin = settings.launchAtLogin
        githubToken = await persistence.loadToken(forKey: "github_token") ?? ""
        // Auth state is fetched lazily by the notifications step via
        // refreshNotificationAuthState() — UNUserNotificationCenter does
        // not behave reliably outside a real .app bundle (e.g. in tests).
    }

    /// Registers/unregisters the login item via SMAppService and stores the
    /// actual resulting state (the call can fail silently — e.g. user revokes
    /// in System Settings — so we trust the OS-reported value).
    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLoginService.setEnabled(enabled)
    }

    /// Triggers the system notification permission prompt. If the user already
    /// granted or denied, this just refreshes the cached state — macOS won't
    /// reshow the dialog. The view should fall back to "Open System Settings"
    /// in the denied case.
    func requestNotificationPermission() async {
        isRequestingNotifications = true
        notificationAuthState = await NotificationService.requestSystemAuthorization()
        isRequestingNotifications = false
    }

    func openNotificationSystemSettings() {
        NotificationService.openSystemSettings()
    }

    func refreshNotificationAuthState() async {
        notificationAuthState = await NotificationService.systemAuthorizationState()
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
            settings.notificationsEnabled = notificationsEnabled
            settings.launchAtLogin = launchAtLogin
            try await persistence.saveSettings(settings)
            await persistence.saveToken(githubToken.trimmingCharacters(in: .whitespaces), forKey: "github_token")
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
