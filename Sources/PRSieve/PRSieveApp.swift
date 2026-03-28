import SwiftUI

@main
struct PRSieveApp: App {
    @State private var viewModel = DashboardViewModel()
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: viewModel)
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

    func initialize(viewModel: DashboardViewModel) async {
        guard persistence == nil else { return }

        do {
            let persistence = try PersistenceService()
            self.persistence = persistence

            let settings = await persistence.loadSettings()
            let githubToken = await persistence.loadToken(forKey: "github_token") ?? ""
            let buildkiteToken = await persistence.loadToken(forKey: "buildkite_token") ?? ""
            let llmAPIKey = await persistence.loadToken(forKey: "llm_api_key") ?? ""

            let githubClient = GitHubClient(token: githubToken)
            let buildkiteClient = BuildkiteClient(
                token: buildkiteToken,
                orgSlug: settings.buildkiteOrgSlug
            )
            let llmClient = LLMClient(
                endpoint: settings.llmEndpoint,
                apiKey: llmAPIKey,
                model: settings.llmModel
            )
            let categorizationService = CategorizationService(llmClient: llmClient)
            let pollingService = PollingService(
                persistence: persistence,
                githubClient: githubClient,
                buildkiteClient: buildkiteClient,
                categorizationService: categorizationService,
                settings: settings
            )

            viewModel.setup(persistence: persistence, pollingService: pollingService)
            await viewModel.loadCached()

            // Start polling if configured
            if !settings.githubUsername.isEmpty && !githubToken.isEmpty {
                viewModel.startPolling(intervalSeconds: settings.pollingIntervalSeconds)
            }
        } catch {
            viewModel.error = "Failed to initialize: \(error.localizedDescription)"
        }
    }
}
