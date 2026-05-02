import SwiftUI

struct PRListContent: View {
    @Bindable var viewModel: DashboardViewModel
    var compact: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                if !viewModel.review.isEmpty {
                    categorySection(.priority, prs: viewModel.review)
                }
                if !viewModel.watch.isEmpty {
                    categorySection(.low, prs: viewModel.watch)
                }
                if !viewModel.skip.isEmpty {
                    categorySection(.noise, prs: viewModel.skip)
                }

                if !viewModel.reviewed.isEmpty {
                    reviewedSection(prs: viewModel.reviewed)
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
                    .padding(.top, compact ? 20 : 40)
                }
            }
            .padding(compact ? 10 : 16)
        }
        .background(Color(.windowBackgroundColor))
    }

    private func categorySection(_ category: PRCategory, prs: [PullRequest]) -> some View {
        let isCollapsed = viewModel.collapsedSections.contains(category) && viewModel.searchText.isEmpty

        return VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            CategoryHeaderView(
                category: category,
                count: prs.count,
                isCollapsed: isCollapsed,
                onToggle: { viewModel.toggleSection(category) }
            )

            if isCollapsed {
                CollapsedSectionPreview(
                    prs: prs,
                    summary: viewModel.categorySummaries[category]
                )
            } else {
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
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }

    private func reviewedSection(prs: [PullRequest]) -> some View {
        let isCollapsed = viewModel.collapsedReviewed && viewModel.searchText.isEmpty

        return VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Button(action: { viewModel.collapsedReviewed.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.reviewedAccent)
                    Text("Reviewed")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(prs.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.reviewedAccent.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.reviewedAccent)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: isCollapsed)

            if !isCollapsed {
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
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }
}
