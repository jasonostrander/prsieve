import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    var onSettingsDismissed: (() -> Void)?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isInitialLoad && viewModel.pullRequests.isEmpty {
                    emptyState
                } else {
                    PRListContent(viewModel: viewModel)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        ZStack {
                            Image(systemName: "arrow.clockwise")
                                .opacity(viewModel.isLoading ? 0 : 1)
                            ProgressView()
                                .scaleEffect(0.5)
                                .opacity(viewModel.isLoading ? 1 : 0)
                        }
                        .frame(width: 16, height: 16)
                    }
                    .help("Refresh now")
                    .disabled(viewModel.isLoading)

                    Toggle(isOn: $viewModel.showReadyToMerge) {
                        Image(systemName: "checkmark.diamond")
                    }
                    .help("Show only PRs with passing CI")

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Filter PRs...")
            .navigationTitle("PRSieve")
            .navigationSubtitle(subtitle)
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            onSettingsDismissed?()
        }) {
            if let persistence = viewModel.persistence {
                SettingsView(viewModel: SettingsViewModel(persistence: persistence))
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                if let llm = viewModel.llmErrorDescription {
                    llmErrorBanner(llm, onSettings: { showSettings = true })
                }
                if !viewModel.repoErrors.isEmpty {
                    repoErrorBanner(viewModel.repoErrors, onSettings: { showSettings = true })
                }
                if let error = viewModel.error {
                    errorBanner(error)
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Welcome to PRSieve", systemImage: "tray.full")
        } description: {
            Text("Configure your GitHub settings to start triaging PRs.")
        } actions: {
            Button("Open Settings") {
                showSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func llmErrorBanner(_ info: (title: String, suggestion: String), onSettings: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title)
                    .font(.caption.weight(.semibold))
                Text(info.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings") { onSettings() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
            Button {
                viewModel.llmError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private func repoErrorBanner(_ errors: [RepoFetchError], onSettings: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(errors.count == 1
                     ? "Couldn't fetch \(errors[0].repo)"
                     : "Couldn't fetch \(errors.count) repos")
                    .font(.caption.weight(.semibold))
                Text(errors.map { "\($0.repo): \($0.message)" }.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings") { onSettings() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
            Button {
                viewModel.repoErrors = []
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
            Spacer()
            Button("Dismiss") {
                viewModel.error = nil
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(10)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var subtitle: String {
        if let last = viewModel.lastRefresh {
            return "\(viewModel.totalCount) PRs · Updated \(Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "\(viewModel.totalCount) PRs"
    }
}
