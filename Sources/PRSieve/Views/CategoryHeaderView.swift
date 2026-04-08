import SwiftUI

struct CategoryHeaderView: View {
    let category: PRCategory
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                Image(systemName: PRTheme.icon(for: category))
                    .foregroundStyle(PRTheme.accent(for: category))
                Text(category.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(PRTheme.accent(for: category).opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(PRTheme.accent(for: category))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }
}

struct CollapsedSectionPreview: View {
    let prs: [PullRequest]
    let summary: String?

    var body: some View {
        HStack(spacing: 10) {
            authorAvatars

            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Summarizing...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var authorAvatars: some View {
        let uniqueAuthors = uniqueAuthorAvatars()
        return HStack(spacing: -5) {
            ForEach(Array(uniqueAuthors.prefix(8).enumerated()), id: \.offset) { _, author in
                AsyncImage(url: author.avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Circle()
                            .fill(.gray.opacity(0.3))
                            .overlay(
                                Text(String(author.login.prefix(1)).uppercased())
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())
                .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
            if uniqueAuthors.count > 8 {
                Text("+\(uniqueAuthors.count - 8)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func uniqueAuthorAvatars() -> [(login: String, avatarURL: URL?)] {
        var seen = Set<String>()
        var result: [(login: String, avatarURL: URL?)] = []
        for pr in prs {
            if seen.insert(pr.author).inserted {
                result.append((login: pr.author, avatarURL: pr.authorAvatarURL))
            }
        }
        return result
    }
}
