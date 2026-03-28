import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    let onOverrideCategory: (PRCategory) -> Void
    let onToggleFlag: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Build status indicator
            buildStatusBadge
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack(alignment: .firstTextBaseline) {
                    Text(pr.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    Spacer()

                    if pr.isFlagged {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                // Metadata row
                HStack(spacing: 8) {
                    Text(pr.repoShortName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Label(pr.author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(pr.ageDescription, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(ageColor)

                    Text("#\(pr.number)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)

                    reviewStatusBadge

                    if pr.isDraft {
                        Text("Draft")
                            .font(.caption)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    // Labels
                    ForEach(pr.labels.prefix(3), id: \.self) { label in
                        Text(label)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                // Category reason
                if !pr.categoryReason.isEmpty {
                    Text(pr.categoryReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open in Browser") {
                NSWorkspace.shared.open(pr.htmlURL)
            }

            Divider()

            Menu("Set Category") {
                ForEach(PRCategory.allCases, id: \.self) { category in
                    Button {
                        onOverrideCategory(category)
                    } label: {
                        HStack {
                            Text(category.displayName)
                            if pr.category == category {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Button(pr.isFlagged ? "Remove Flag" : "Flag for Later") {
                onToggleFlag()
            }
        }
    }

    // MARK: - Subviews

    private var buildStatusBadge: some View {
        Group {
            if let status = pr.buildStatus {
                Image(systemName: status.symbol)
                    .foregroundStyle(buildStatusColor(status))
                    .help("Build: \(status.rawValue)")
            } else {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.quaternary)
            }
        }
        .font(.body)
    }

    private var reviewStatusBadge: some View {
        Group {
            switch pr.reviewStatus {
            case .approved:
                Label("Approved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .changesRequested:
                Label("Changes Requested", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case .dismissed:
                Label("Dismissed", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            case .pending:
                EmptyView()
            }
        }
        .font(.caption)
    }

    private var ageColor: Color {
        let hours = pr.age / 3600
        if hours > 72 { return .red }
        if hours > 24 { return .orange }
        return .secondary
    }

    private func buildStatusColor(_ status: BuildStatus) -> Color {
        switch status {
        case .passed: .green
        case .failed: .red
        case .running: .orange
        case .unknown: .gray
        }
    }
}
