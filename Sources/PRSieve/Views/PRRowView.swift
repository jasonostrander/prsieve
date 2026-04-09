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
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("·")
                    .foregroundStyle(.quaternary)

                Text(pr.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if pr.isDraft {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("Draft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                reviewSummary
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

    private var reviewSummary: some View {
        HStack(spacing: 6) {
            buildStatusPill
            reviewStatusPill

            if pr.humanCommentCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "text.bubble")
                        .font(.caption2)
                    Text("\(pr.humanCommentCount)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            if !pr.reviewers.isEmpty {
                HStack(spacing: -4) {
                    ForEach(pr.reviewers.prefix(5)) { reviewer in
                        ReviewerAvatarView(reviewer: reviewer)
                    }
                }
                if pr.reviewers.count > 5 {
                    Text("+\(pr.reviewers.count - 5)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewStatusPill: some View {
        let approvals = pr.reviewers.filter { $0.state == .approved }.count
        let changesRequested = pr.reviewers.contains { $0.state == .changesRequested }

        if changesRequested {
            statusPill(
                icon: "exclamationmark.circle.fill",
                text: "Changes requested",
                foreground: .pillChangesText,
                background: .pillChangesBg
            )
        } else if approvals > 0 {
            statusPill(
                icon: "checkmark.circle.fill",
                text: approvals == 1 ? "Approved" : "\(approvals) approved",
                foreground: .pillApprovedText,
                background: .pillApprovedBg
            )
        } else if pr.reviewers.contains(where: { $0.state == .commented }) {
            statusPill(
                icon: "bubble.left.fill",
                text: "Reviewed",
                foreground: .pillCommentedText,
                background: .pillCommentedBg
            )
        }
    }

    private func statusPill(icon: String, text: String, foreground: Color, background: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(foreground)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var buildStatusPill: some View {
        switch pr.buildStatus {
        case .passed:
            statusPill(
                icon: "checkmark.circle.fill",
                text: "CI passed",
                foreground: .pillCIPassedText,
                background: .pillCIPassedBg
            )
        case .failed:
            statusPill(
                icon: "xmark.circle.fill",
                text: "CI failing",
                foreground: .pillCIFailedText,
                background: .pillCIFailedBg
            )
        case .running:
            statusPill(
                icon: "arrow.triangle.2.circlepath",
                text: "CI running",
                foreground: .pillCIRunningText,
                background: .pillCIRunningBg
            )
        default:
            EmptyView()
        }
    }

    private var ageColor: Color {
        let hours = pr.age / 3600
        if hours > 72 { return .red.opacity(0.8) }
        if hours > 24 { return .orange.opacity(0.8) }
        return .secondary
    }
}

// MARK: - Reviewer Avatar

struct ReviewerAvatarView: View {
    let reviewer: ReviewerInfo
    private let size: CGFloat = 20

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: reviewer.avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    initialsView
                default:
                    initialsView
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(statusBorderColor, lineWidth: 1.5)
            )

            statusBadge
                .offset(x: 2, y: 2)
        }
        .help("\(reviewer.login): \(statusLabel)")
    }

    private var initialsView: some View {
        Circle()
            .fill(.gray.opacity(0.3))
            .overlay(
                Text(String(reviewer.login.prefix(1)).uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }

    private var statusConfig: (icon: String, color: Color, borderColor: Color, label: String)? {
        switch reviewer.state {
        case .approved: ("checkmark.circle.fill", .green, .green.opacity(0.5), "Approved")
        case .changesRequested: ("xmark.circle.fill", .red, .red.opacity(0.5), "Changes requested")
        case .commented: ("ellipsis.circle.fill", .orange, .orange.opacity(0.3), "Commented")
        case .dismissed: nil
        case .pending: nil
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let config = statusConfig {
            Image(systemName: config.icon)
                .font(.system(size: 9))
                .foregroundStyle(config.color)
                .background(Circle().fill(.white).frame(width: 7, height: 7))
        }
    }

    private var statusBorderColor: Color {
        statusConfig?.borderColor ?? .clear
    }

    private var statusLabel: String {
        statusConfig?.label ?? (reviewer.state == .dismissed ? "Dismissed" : "Pending")
    }
}
