import SwiftUI

struct MenuBarPRListView: View {
    @Bindable var viewModel: DashboardViewModel
    var onOpenSettings: (() -> Void)?
    var onOpenOnboarding: (() -> Void)?

    @State private var showSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        if viewModel.needsOnboarding {
            setupView
        } else {
            mainView
        }
    }

    private var setupView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Welcome to PRSieve")
                .font(.title2.weight(.semibold))

            Text("Connect your GitHub account to start triaging review requests.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Button {
                onOpenOnboarding?()
            } label: {
                Text("Set Up")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
            HStack {
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 420, height: 580)
        .focusEffectDisabled()
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PRSieve")
                    .font(.headline)

                Spacer()

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
                .buttonStyle(.plain)
                .help("Refresh now")
                .disabled(viewModel.isLoading)

                Toggle(isOn: $viewModel.showReadyToMerge) {
                    Image(systemName: "checkmark.diamond")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show only PRs with passing CI")

                Toggle(isOn: $viewModel.showMerged) {
                    Image(systemName: "archivebox")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show merged PRs")

                Button {
                    showSearch.toggle()
                    if showSearch {
                        searchFocused = true
                    } else {
                        viewModel.searchText = ""
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("Search")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if showSearch {
                Divider()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($searchFocused)
                        .onExitCommand {
                            showSearch = false
                            viewModel.searchText = ""
                        }
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            if let llm = viewModel.llmErrorDescription {
                llmErrorBanner(llm)
            }

            // PR list
            PRListContent(viewModel: viewModel, compact: true)

            Divider()

            // Footer
            HStack {
                Button {
                    onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 420, height: 580)
        .focusEffectDisabled()
    }

    private func llmErrorBanner(_ info: (title: String, suggestion: String)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title)
                    .font(.caption.weight(.semibold))
                Text(info.suggestion)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onOpenSettings?()
            } label: {
                Text("Settings")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            Button {
                viewModel.llmError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.red.opacity(0.07))
    }

    private var subtitleText: String {
        if let last = viewModel.lastRefresh {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "\(viewModel.totalCount) PRs \u{00B7} \(formatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "\(viewModel.totalCount) PRs"
    }
}
