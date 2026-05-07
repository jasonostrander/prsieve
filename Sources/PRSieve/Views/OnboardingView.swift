import SwiftUI

struct OnboardingView: View {
    @State var viewModel: OnboardingViewModel
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 8)

            Group {
                switch viewModel.step {
                case .welcome:       welcomeStep
                case .github:        githubStep
                case .prompt:        promptStep
                case .notifications: notificationsStep
                case .done:          doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 560, height: 540)
        .task { await viewModel.load() }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= viewModel.step.rawValue
                          ? Color.accentColor
                          : Color.secondary.opacity(0.25))
                    .frame(width: step == viewModel.step ? 28 : 18, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.step)
            }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to PRSieve")
                .font(.largeTitle.weight(.semibold))

            Text("PRSieve watches your GitHub review requests and uses an LLM to surface the PRs that actually matter to you — so you can stop drowning in fallthrough codeowner pings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 10) {
                bullet("Pulls open PRs awaiting your review")
                bullet("Categorizes them as Review, Watch, or Skip")
                bullet("Notifies you when Review PRs pass CI")
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
            Text(text)
            Spacer()
        }
    }

    // MARK: - GitHub

    private var githubStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect to GitHub")
                    .font(.title2.weight(.semibold))

                Text("PRSieve needs a personal access token to read your review requests, reviews, CODEOWNERS files, and CI status.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub username")
                        .font(.subheadline.weight(.medium))
                    TextField("octocat", text: $viewModel.githubUsername)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Personal access token")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Link(destination: tokenURL) {
                            HStack(spacing: 3) {
                                Text("Create token")
                                Image(systemName: "arrow.up.forward.square")
                            }
                            .font(.caption)
                        }
                    }
                    SecureField("ghp_...", text: $viewModel.githubToken)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                    Text("Needs **repo** and **read:org** scopes. Token is stored locally with file permissions 0600.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Repositories to watch")
                        .font(.subheadline.weight(.medium))
                    HStack {
                        TextField("owner/repo", text: $viewModel.newRepoText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { viewModel.addRepo() }
                        Button("Add") { viewModel.addRepo() }
                            .disabled(viewModel.newRepoText.isEmpty || !viewModel.newRepoText.contains("/"))
                    }
                    if viewModel.repos.isEmpty {
                        Text("Add at least one repository in `owner/repo` form.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(viewModel.repos) { repo in
                                HStack {
                                    Text(repo.repo)
                                        .font(.body.monospaced())
                                    Spacer()
                                    Button {
                                        if let idx = viewModel.repos.firstIndex(where: { $0.id == repo.id }) {
                                            viewModel.removeRepo(at: IndexSet(integer: idx))
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var tokenURL: URL {
        URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org&description=PRSieve")!
    }

    // MARK: - Prompt

    private var promptStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Describe what you own")
                .font(.title2.weight(.semibold))

            Text("Tell the LLM which code you maintain. PRSieve uses this — along with the changed file paths — to decide whether a PR needs your attention.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $viewModel.codeownerContext)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .frame(minHeight: 220)

            Text("Example: \"I own the iOS checkout flow — files under `apps/ios/Checkout/`, and the payment SDK in `Libraries/Payments/`. I do NOT review marketing or analytics code.\"")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Notifications

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stay in the loop")
                .font(.title2.weight(.semibold))

            Text("PRSieve can post a macOS notification when a Review PR's CI turns green, and start automatically when you log in so it's always watching.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Notify me when Review PRs pass CI", isOn: $viewModel.notificationsEnabled)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    statusBadge
                    Text(statusDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }

                HStack(spacing: 10) {
                    switch viewModel.notificationAuthState {
                    case .notDetermined:
                        Button {
                            Task { await viewModel.requestNotificationPermission() }
                        } label: {
                            if viewModel.isRequestingNotifications {
                                ProgressView().scaleEffect(0.6).frame(height: 16)
                            } else {
                                Text("Enable Notifications")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.notificationsEnabled || viewModel.isRequestingNotifications)
                    case .denied:
                        Button("Open System Settings") {
                            viewModel.openNotificationSystemSettings()
                        }
                        .buttonStyle(.bordered)
                        Button("Recheck") {
                            Task { await viewModel.refreshNotificationAuthState() }
                        }
                        .buttonStyle(.borderless)
                    case .authorized:
                        EmptyView()
                    }
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            .opacity(viewModel.notificationsEnabled ? 1 : 0.5)
            .disabled(!viewModel.notificationsEnabled)

            Divider()
                .padding(.vertical, 4)

            Toggle(isOn: launchAtLoginBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch PRSieve at login")
                    Text("Recommended — PRSieve has to be running to surface review requests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("You can change everything here later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 8)
        .task { await viewModel.refreshNotificationAuthState() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLogin },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch viewModel.notificationAuthState {
        case .authorized:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .notDetermined:
            Image(systemName: "bell.badge")
                .foregroundStyle(.tint)
        }
    }

    private var statusDescription: String {
        switch viewModel.notificationAuthState {
        case .authorized:
            return "Notifications are enabled for PRSieve."
        case .denied:
            return "Notifications are blocked in System Settings. Open Settings to allow them."
        case .notDetermined:
            return "macOS hasn't asked yet. Click Enable Notifications to grant permission."
        }
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're all set")
                .font(.largeTitle.weight(.semibold))

            Text("PRSieve will start fetching your review requests in the background. The menu bar icon turns orange when Review PRs are ready to merge.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Text("You can adjust everything later from Settings.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if viewModel.step != .welcome && viewModel.step != .done {
                Button("Back") {
                    viewModel.goBack()
                }
            }
            Spacer()
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch viewModel.step {
        case .welcome:
            Button("Get Started") {
                Task { await viewModel.advance() }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        case .github:
            Button("Next") {
                Task { await viewModel.advance() }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canAdvanceFromGitHub)
        case .prompt:
            Button("Next") {
                Task { await viewModel.advance() }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canAdvanceFromPrompt)
        case .notifications:
            Button("Continue") {
                Task { await viewModel.advance() }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        case .done:
            Button("Done") {
                Task {
                    await viewModel.finish()
                    onFinish()
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
    }
}
