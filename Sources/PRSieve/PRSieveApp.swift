import SwiftUI

@main
struct PRSieveApp: App {
    @State private var viewModel = DashboardViewModel()
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: viewModel, onSettingsDismissed: {
                    Task { await appState.reinitialize(viewModel: viewModel) }
                })
                .frame(minWidth: 700, minHeight: 500)
                .task {
                    await appState.initialize(viewModel: viewModel)
                }
                .onDisappear {
                    viewModel.stopPolling()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            if let persistence = viewModel.persistence {
                SettingsView(viewModel: SettingsViewModel(persistence: persistence))
                    .onDisappear {
                        // Reinitialize services when settings close, picking up new tokens
                        Task {
                            await appState.reinitialize(viewModel: viewModel)
                        }
                    }
            } else {
                ProgressView("Loading...")
                    .frame(width: 400, height: 200)
            }
        }
    }
}

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

        // Create or update clients
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

        // Start polling if configured
        if !settings.githubUsername.isEmpty && !githubToken.isEmpty {
            viewModel.startPolling(intervalSeconds: settings.pollingIntervalSeconds)
        }
    }
}
