import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            githubTab
                .tabItem { Label("GitHub", systemImage: "person.crop.circle") }
            llmTab
                .tabItem { Label("LLM", systemImage: "brain") }
            preferencesTab
                .tabItem { Label("Preferences", systemImage: "gearshape") }
        }
        .padding(20)
        .frame(width: 550, height: 450)
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
        .overlay(alignment: .bottomTrailing) {
            Button("Done") { dismiss() }
                .keyboardShortcut(.return, modifiers: .command)
                .padding()
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

            Section("Your Code Ownership Context") {
                TextEditor(text: $viewModel.settings.codeownerContext)
                    .frame(minHeight: 100)
                    .font(.body.monospaced())
                Text("Describe which code you own, maintain, or have expertise in. This helps the LLM categorize PRs accurately.")
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

            Section("Notifications") {
                Toggle("Enable notifications for Must Review PRs", isOn: $viewModel.settings.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
