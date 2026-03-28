import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
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
        .sheet(isPresented: $showSettings) {
            if let persistence = viewModel.persistence {
                SettingsView(viewModel: SettingsViewModel(persistence: persistence))
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.error {
                errorBanner(error)
            }
        }
    }

    // MARK: - Subviews

    private var prList: some View {
        List {
            if !viewModel.mustReview.isEmpty {
                Section {
                    ForEach(viewModel.mustReview) { pr in
                        prRow(pr)
                    }
                } header: {
                    CategoryHeaderView(category: .mustReview, count: viewModel.mustReview.count)
                }
            }

            if !viewModel.shouldKnow.isEmpty {
                Section {
                    ForEach(viewModel.shouldKnow) { pr in
                        prRow(pr)
                    }
                } header: {
                    CategoryHeaderView(category: .shouldKnow, count: viewModel.shouldKnow.count)
                }
            }

            if !viewModel.fyi.isEmpty {
                Section {
                    ForEach(viewModel.fyi) { pr in
                        prRow(pr)
                    }
                } header: {
                    CategoryHeaderView(category: .fyi, count: viewModel.fyi.count)
                }
            }

            if viewModel.totalCount == 0 {
                ContentUnavailableView(
                    "No PRs match",
                    systemImage: "magnifyingglass",
                    description: Text(viewModel.searchText.isEmpty
                        ? "No open PRs requiring your review right now."
                        : "Try a different search term.")
                )
            }
        }
        .listStyle(.sidebar)
    }

    private func prRow(_ pr: PullRequest) -> some View {
        PRRowView(
            pr: pr,
            onOverrideCategory: { category in
                viewModel.overrideCategory(prID: pr.id, to: category)
            },
            onToggleFlag: {
                viewModel.toggleFlag(prID: pr.id)
            }
        )
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(pr.htmlURL)
        }
        .opacity(pr.isMerged ? 0.6 : 1.0)
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
        .padding()
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
