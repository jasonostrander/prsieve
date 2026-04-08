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
                    prList
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh now")
                    .disabled(viewModel.isLoading)

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

    private var prList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !viewModel.priority.isEmpty {
                    categorySection(.priority, prs: viewModel.priority)
                }
                if !viewModel.low.isEmpty {
                    categorySection(.low, prs: viewModel.low)
                }
                if !viewModel.noise.isEmpty {
                    categorySection(.noise, prs: viewModel.noise)
                }

                if viewModel.totalCount == 0 {
                    ContentUnavailableView(
                        "No PRs match",
                        systemImage: "magnifyingglass",
                        description: Text(viewModel.searchText.isEmpty
                            ? "No open PRs requiring your review right now."
                            : "Try a different search term.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor))
    }

    private func categorySection(_ category: PRCategory, prs: [PullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CategoryHeaderView(category: category, count: prs.count)

            ForEach(prs) { pr in
                PRCardView(
                    pr: pr,
                    onOverrideCategory: { cat in
                        viewModel.overrideCategory(prID: pr.id, to: cat)
                    },
                    onToggleFlag: {
                        viewModel.toggleFlag(prID: pr.id)
                    }
                )
                .onTapGesture {
                    NSWorkspace.shared.open(pr.htmlURL)
                }
            }
        }
    }

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

    private var subtitle: String {
        if let last = viewModel.lastRefresh {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "\(viewModel.totalCount) PRs · Updated \(formatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "\(viewModel.totalCount) PRs"
    }
}
