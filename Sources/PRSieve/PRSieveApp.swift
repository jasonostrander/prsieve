import SwiftUI

@main
struct PRSieveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene kept as a placeholder; actual settings window managed by AppDelegate
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let viewModel = DashboardViewModel()
    let appState = AppState()
    private var statusBarController: StatusBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
        statusBarController?.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        Task {
            await appState.initialize(viewModel: viewModel)
        }
    }

    func openSettings() {
        // If window exists and is visible, just bring it forward
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let persistence = viewModel.persistence else { return }

        let settingsVM = SettingsViewModel(persistence: persistence)
        let settingsView = SettingsView(viewModel: settingsVM)

        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hostingController)
        window.title = "PRSieve Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        settingsWindow = nil
        Task {
            await appState.reinitialize(viewModel: viewModel)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - App State

@MainActor @Observable
final class AppState {
    private var persistence: PersistenceService?
    private var githubClient: GitHubClient?
    private var buildkiteClient: BuildkiteClient?
    private var llmClient: LLMClient?
    private var notificationService: NotificationService?

    func initialize(viewModel: DashboardViewModel) async {
        guard persistence == nil else { return }

        do {
            let persistence = try PersistenceService()
            self.persistence = persistence
            viewModel.setup(persistence: persistence, pollingService: nil)
            await viewModel.loadCached()
            await buildAndStartServices(viewModel: viewModel, persistence: persistence)
        } catch {
            viewModel.error = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    func reinitialize(viewModel: DashboardViewModel) async {
        guard let persistence else { return }
        viewModel.stopPolling()
        await buildAndStartServices(viewModel: viewModel, persistence: persistence)
    }

    private func buildAndStartServices(viewModel: DashboardViewModel, persistence: PersistenceService) async {
        let settings = await persistence.loadSettings()
        viewModel.hideDrafts = settings.hideDraftPRs
        viewModel.githubUsername = settings.githubUsername
        viewModel.keepUnreviewedPriorityAfterMerge = settings.keepUnreviewedPriorityAfterMerge

        // Sync launch-at-login registration with the saved setting
        LaunchAtLoginService.setEnabled(settings.launchAtLogin)
        let githubToken = await persistence.loadToken(forKey: "github_token") ?? ""
        let buildkiteToken = await persistence.loadToken(forKey: "buildkite_token") ?? ""
        let llmAPIKey = await persistence.loadToken(forKey: "llm_api_key") ?? ""

        if let existing = githubClient {
            await existing.updateToken(githubToken)
            await existing.updateIgnoredCIChecks(settings.ignoredCIChecks)
        } else {
            githubClient = GitHubClient(token: githubToken)
            await githubClient!.updateIgnoredCIChecks(settings.ignoredCIChecks)
        }

        if let existing = buildkiteClient {
            await existing.updateCredentials(token: buildkiteToken, orgSlug: settings.buildkiteOrgSlug)
        } else {
            buildkiteClient = BuildkiteClient(token: buildkiteToken, orgSlug: settings.buildkiteOrgSlug)
        }

        if let existing = llmClient {
            await existing.updateConfig(endpoint: settings.llmEndpoint, apiKey: llmAPIKey, model: settings.llmModel)
        } else {
            llmClient = LLMClient(endpoint: settings.llmEndpoint, apiKey: llmAPIKey, model: settings.llmModel)
        }

        let categorizationService = CategorizationService(llmClient: llmClient!)
        let pollingService = PollingService(
            persistence: persistence,
            githubClient: githubClient!,
            buildkiteClient: buildkiteClient!,
            categorizationService: categorizationService,
            settings: settings
        )

        viewModel.updatePollingService(pollingService)
        viewModel.updateLLMProvider(llmClient!)

        if settings.notificationsEnabled {
            if notificationService == nil {
                notificationService = NotificationService(persistence: persistence)
            }
            await notificationService!.requestAuthorization()
            viewModel.notificationService = notificationService
        } else {
            viewModel.notificationService = nil
        }

        if !settings.githubUsername.isEmpty && !githubToken.isEmpty {
            viewModel.startPolling(intervalSeconds: settings.pollingIntervalSeconds)
        }
    }
}
