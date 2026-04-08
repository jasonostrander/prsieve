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

                    Toggle(isOn: $viewModel.showMerged) {
                        Image(systemName: "archivebox")
                    }
                    .help("Show merged PRs")

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
            if let error = viewModel.error {
                errorBanner(error)
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
