import SwiftUI

struct MenuBarPRListView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PRSieve")
                    .font(.headline)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }

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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // PR list
            PRListContent(viewModel: viewModel, compact: true)

            Divider()

            // Footer
            HStack {
                Button {
                    showSettings = true
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
        .sheet(isPresented: $showSettings) {
            if let persistence = viewModel.persistence {
                SettingsView(viewModel: SettingsViewModel(persistence: persistence))
            }
        }
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
