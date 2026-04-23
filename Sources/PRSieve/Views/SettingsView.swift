import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: SettingsViewModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Label("GitHub", systemImage: "person.crop.circle").tag(0)
                Label("LLM", systemImage: "brain").tag(1)
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
                case 1: llmTab
                default: preferencesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 650, height: 580)
        .task { await viewModel.load() }
        .onChange(of: viewModel.settings) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.githubToken) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.llmAPIKey) { _, _ in
            Task { await viewModel.save() }
        }
    }

    // MARK: - GitHub Tab

    private var githubTab: some View {
        Form {
            Section("Account") {
                TextField("Username", text: $viewModel.settings.githubUsername)
                SecureField("Personal Access Token", text: $viewModel.githubToken)
                    .textContentType(.password)
            }

            Section("Repositories") {
                List {
                    ForEach(viewModel.settings.repos) { repo in
                        Text(repo.repo)
                            .font(.body.monospaced())
                    }
                    .onDelete(perform: viewModel.removeRepo)
                }
                .frame(minHeight: 80)

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

    // MARK: - LLM Tab

    private var llmTab: some View {
        Form {
            Section("OpenAI-Compatible API") {
                TextField("Endpoint URL", text: $viewModel.settings.llmEndpoint)
                    .help("Base URL for the chat completions API (e.g., https://api.openai.com/v1)")
                SecureField("API Key", text: $viewModel.llmAPIKey)
                    .textContentType(.password)
                TextField("Model", text: $viewModel.settings.llmModel)
                    .help("Model name (e.g., gpt-4o-mini)")
            }

            Section {
                Text("Describe what code you own or maintain. Focus on your areas of responsibility — the LLM handles categorization logic and PR age separately.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                TextEditor(text: $viewModel.settings.codeownerContext)
                    .frame(minHeight: 160)
                    .font(.body.monospaced())
            } header: {
                Text("Your Code Ownership Context")
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
                Toggle("Keep unreviewed priority PRs visible for 3 days after merge", isOn: $viewModel.settings.keepUnreviewedPriorityAfterMerge)
            }

            Section("Notifications") {
                Toggle("Notify when priority PRs pass CI", isOn: $viewModel.settings.notificationsEnabled)
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
        }
        .formStyle(.grouped)
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
}
