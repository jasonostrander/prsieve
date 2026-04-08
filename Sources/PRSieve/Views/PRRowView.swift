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

                Spacer()

                // Review activity
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
        HStack(spacing: 4) {
            // Reviewer avatars with status
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

            // Comment count
            if pr.humanCommentCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "text.bubble")
                        .font(.caption2)
                    Text("\(pr.humanCommentCount)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
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

            // Status badge
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

    @ViewBuilder
    private var statusBadge: some View {
        switch reviewer.state {
        case .approved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green)
                .background(Circle().fill(.white).frame(width: 7, height: 7))
        case .changesRequested:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.red)
                .background(Circle().fill(.white).frame(width: 7, height: 7))
        case .commented:
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
                .background(Circle().fill(.white).frame(width: 7, height: 7))
        default:
            EmptyView()
        }
    }

    private var statusBorderColor: Color {
        switch reviewer.state {
        case .approved: .green.opacity(0.5)
        case .changesRequested: .red.opacity(0.5)
        case .commented: .orange.opacity(0.3)
        default: .clear
        }
    }

    private var statusLabel: String {
        switch reviewer.state {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .commented: "Commented"
        case .dismissed: "Dismissed"
        case .pending: "Pending"
        }
    }
}
