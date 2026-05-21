import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: SettingsViewModel
    var updater: UpdaterServicing? = nil
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Label("GitHub", systemImage: "person.crop.circle").tag(0)
                Label("Prompt", systemImage: "text.bubble").tag(1)
                Label("Preferences", systemImage: "gearshape").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: githubTab
                case 1: promptTab
                default: preferencesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 650, height: 580)
        .sheet(isPresented: $viewModel.isPromptTestSheetPresented) {
            PromptTestSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.load()
            await viewModel.refreshNotificationAuthState()
        }
        .onChange(of: viewModel.settings) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.githubToken) { _, _ in
            Task { await viewModel.save() }
        }
    }

    // MARK: - GitHub Tab

    private var githubTab: some View {
        Form {
            Section("Account") {
                TextField("Username", text: $viewModel.settings.githubUsername)
                    .onChange(of: viewModel.settings.githubUsername) { _, _ in
                        viewModel.githubTestResult = nil
                    }
                HStack {
                    SecureField("Personal Access Token", text: $viewModel.githubToken)
                        .textContentType(.password)
                        .onChange(of: viewModel.githubToken) { _, _ in
                            viewModel.githubTestResult = nil
                        }
                    Button {
                        Task { await viewModel.testGitHubAuth() }
                    } label: {
                        if viewModel.isTestingGitHub {
                            ProgressView().scaleEffect(0.6).frame(width: 32)
                        } else {
                            Text("Test")
                        }
                    }
                    .disabled(viewModel.isTestingGitHub || viewModel.githubToken.isEmpty)
                    .frame(width: 44)
                }
                if let result = viewModel.githubTestResult {
                    switch result {
                    case .success(let login, let matches):
                        if matches {
                            Label("Authenticated as \(login)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label("Token works but belongs to \(login), not the configured username", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    case .failure(let msg):
                        Label(msg, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            Section("Repositories") {
                if viewModel.settings.repos.isEmpty {
                    Text("No repositories added yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.settings.repos) { repo in
                        HStack {
                            Text(repo.repo)
                                .font(.body.monospaced())
                            Spacer()
                            Button {
                                viewModel.removeRepo(repo)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(repo.repo)")
                        }
                    }
                }

                HStack {
                    TextField("owner/repo", text: $viewModel.newRepoText)
                        .onSubmit { viewModel.addRepo() }
                    Button("Add") { viewModel.addRepo() }
                        .disabled(viewModel.newRepoText.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Prompt Tab

    private var promptTab: some View {
        Form {
            Section {
                HStack {
                    TextField("Model name", text: $viewModel.settings.llmModel)
                        .font(.body.monospaced())
                        .onChange(of: viewModel.settings.llmModel) { _, _ in
                            viewModel.llmTestResult = nil
                        }
                    Button {
                        Task { await viewModel.testLLMConfig() }
                    } label: {
                        if viewModel.isTestingLLM {
                            ProgressView().scaleEffect(0.6).frame(width: 32)
                        } else {
                            Text("Test")
                        }
                    }
                    .disabled(viewModel.isTestingLLM || viewModel.settings.llmModel.isEmpty)
                    .frame(width: 44)
                }
                if let result = viewModel.llmTestResult {
                    switch result {
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .failure(let msg):
                        Label(msg, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("The model used for PR categorization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Describe what code you own or maintain. Focus on your areas of responsibility — the LLM handles categorization logic and PR age separately.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                TextEditor(text: $viewModel.settings.codeownerContext)
                    .frame(minHeight: 180)
                    .font(.body.monospaced())
                HStack {
                    Spacer()
                    Button {
                        viewModel.startPromptTest()
                    } label: {
                        Label("Test against my PRs", systemImage: "play.circle")
                    }
                    .disabled(viewModel.settings.llmModel.isEmpty)
                    .help("Run the current prompt against your currently loaded PRs and see how each would be categorized")
                }
            } header: {
                Text("Your Code Ownership Context")
            } footer: {
                Text("Test runs the prompt against PRs already loaded in the dashboard. Refresh first if you want fresh data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Preferences Tab

    private var preferencesTab: some View {
        Form {
            Section("Polling") {
                Picker("Refresh interval", selection: $viewModel.settings.pollingIntervalSeconds) {
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("15 minutes").tag(900)
                }
            }

            Section("Display") {
                Toggle("Hide draft PRs", isOn: $viewModel.settings.hideDraftPRs)
                Toggle("Keep unreviewed Review PRs visible for 3 days after merge", isOn: $viewModel.settings.keepUnreviewedPriorityAfterMerge)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
            }

            Section {
                Toggle("Notify when Review PRs pass CI", isOn: $viewModel.settings.notificationsEnabled)
                notificationAuthRow
            } header: {
                Text("Notifications")
            } footer: {
                Text("PRSieve uses macOS system notifications. If you previously denied permission, allow it again in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("e.g. danger/danger, lint", text: ignoredCIChecksText)
                    .help("Comma-separated check names to ignore when computing CI status")
            } header: {
                Text("Ignored CI Checks")
            } footer: {
                Text("If all remaining checks pass, CI is considered green.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let updater {
                Section("Updates") {
                    Toggle("Automatically check for updates", isOn: automaticUpdatesBinding(updater: updater))
                    Button("Check for Updates Now") {
                        updater.checkForUpdates()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var notificationAuthRow: some View {
        HStack(spacing: 8) {
            switch viewModel.notificationAuthState {
            case .authorized:
                Label("System permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Spacer()
                Button("Open System Settings") {
                    viewModel.openNotificationSystemSettings()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            case .denied:
                Label("Blocked in System Settings", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Spacer()
                Button("Open System Settings") {
                    viewModel.openNotificationSystemSettings()
                }
                .controlSize(.small)
                Button("Recheck") {
                    Task { await viewModel.refreshNotificationAuthState() }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            case .notDetermined:
                Label("Permission not yet requested", systemImage: "bell.badge")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button {
                    Task { await viewModel.requestNotificationPermission() }
                } label: {
                    if viewModel.isRequestingNotifications {
                        ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                    } else {
                        Text("Enable")
                    }
                }
                .controlSize(.small)
                .disabled(viewModel.isRequestingNotifications)
            }
        }
    }

    private func automaticUpdatesBinding(updater: UpdaterServicing) -> Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }

    private var ignoredCIChecksText: Binding<String> {
        Binding(
            get: { viewModel.settings.ignoredCIChecks.joined(separator: ", ") },
            set: {
                viewModel.settings.ignoredCIChecks = $0
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var versionText: String {
        "v\(BuildInfo.appVersion) · \(BuildInfo.gitHash) · \(BuildInfo.buildDate)"
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.launchAtLogin },
            set: { newValue in
                let actual = LaunchAtLoginService.setEnabled(newValue)
                viewModel.settings.launchAtLogin = actual
            }
        )
    }
}
