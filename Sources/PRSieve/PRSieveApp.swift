import SwiftUI

@main
struct PRSieveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            if let persistence = appDelegate.viewModel.persistence {
                SettingsView(viewModel: SettingsViewModel(persistence: persistence))
                    .onDisappear {
                        Task {
                            await appDelegate.appState.reinitialize(viewModel: appDelegate.viewModel)
                        }
                    }
            } else {
                ProgressView("Loading...")
                    .frame(width: 400, height: 200)
            }
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = DashboardViewModel()
    let appState = AppState()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
        statusBarController?.onOpenSettings = {
            // Open the Settings scene via standard Cmd+, action
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        Task {
            await appState.initialize(viewModel: viewModel)
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
        let githubToken = await persistence.loadToken(forKey: "github_token") ?? ""
        let buildkiteToken = await persistence.loadToken(forKey: "buildkite_token") ?? ""
        let llmAPIKey = await persistence.loadToken(forKey: "llm_api_key") ?? ""

        if let existing = githubClient {
            await existing.updateToken(githubToken)
        } else {
            githubClient = GitHubClient(token: githubToken)
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

        if !settings.githubUsername.isEmpty && !githubToken.isEmpty {
            viewModel.startPolling(intervalSeconds: settings.pollingIntervalSeconds)
        }
    }
}
