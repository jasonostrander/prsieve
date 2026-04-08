import SwiftUI

struct PRListContent: View {
    @Bindable var viewModel: DashboardViewModel
    var compact: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 12 : 20) {
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
}
