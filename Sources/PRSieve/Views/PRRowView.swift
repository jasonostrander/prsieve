import SwiftUI

struct PRCardView: View {
    let pr: PullRequest
    let onOverrideCategory: (PRCategory) -> Void
    let onToggleFlag: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + age
            HStack(alignment: .firstTextBaseline) {
                Text(pr.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if pr.isFlagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                Text(pr.ageDescription)
                    .font(.caption)
                    .foregroundStyle(ageColor)
                    .monospacedDigit()
            }

            // Compact metadata
            HStack(spacing: 6) {
                Text(pr.repoShortName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.quaternary)

                Text(pr.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let status = pr.buildStatus, status != .unknown {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Image(systemName: status.symbol)
                        .font(.caption2)
                        .foregroundStyle(buildStatusColor(status))
                }

                if pr.isDraft {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("Draft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PRTheme.cardBackground(for: pr.category))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(pr.isMerged ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
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

    private var ageColor: Color {
        let hours = pr.age / 3600
        if hours > 72 { return .red.opacity(0.8) }
        if hours > 24 { return .orange.opacity(0.8) }
        return .secondary
    }

    private func buildStatusColor(_ status: BuildStatus) -> Color {
        switch status {
        case .passed: .green
        case .failed: .red.opacity(0.8)
        case .running: .orange
        case .unknown: .gray
        }
    }
}
