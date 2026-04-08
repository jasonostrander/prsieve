import SwiftUI

@MainActor @Observable
final class DashboardViewModel {
    var pullRequests: [PullRequest] = []
    var isLoading = false
    var isInitialLoad = true
    var lastRefresh: Date?
    var error: String?
    var searchText = ""
    var showMerged = false
    var showReadyToMerge = false
    var hideDrafts = true

    var collapsedSections: Set<PRCategory> = []
    var categorySummaries: [PRCategory: String] = [:]

    private var pollingService: PollingService?
    private(set) var persistence: PersistenceService?
    private(set) var llmProvider: (any LLMProvider)?
    var notificationService: NotificationService?
    private var pollingTask: Task<Void, Never>?
    private var summaryTasks: [PRCategory: Task<Void, Never>] = [:]

    var priority: [PullRequest] { filtered(.priority) }
    var low: [PullRequest] { filtered(.low) }
    var noise: [PullRequest] { filtered(.noise) }

    var totalCount: Int { priority.count + low.count + noise.count }

    private func filtered(_ category: PRCategory) -> [PullRequest] {
        pullRequests
            .filter { $0.category == category }
            .filter { showMerged || !$0.isMerged }
            .filter { !hideDrafts || !$0.isDraft }
            .filter { !showReadyToMerge || $0.buildStatus == .passed }
            .filter { searchText.isEmpty || matchesSearch($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func matchesSearch(_ pr: PullRequest) -> Bool {
        let query = searchText.lowercased()
        return pr.title.lowercased().contains(query)
            || pr.author.lowercased().contains(query)
            || pr.repoFullName.lowercased().contains(query)
            || pr.labels.contains { $0.lowercased().contains(query) }
    }

    func setup(persistence: PersistenceService, pollingService: PollingService?) {
        self.persistence = persistence
        self.pollingService = pollingService
    }

    func updatePollingService(_ pollingService: PollingService) {
        self.pollingService = pollingService
    }

    func updateLLMProvider(_ provider: any LLMProvider) {
        self.llmProvider = provider
    }

    func loadCached() async {
        guard let persistence else { return }
        pullRequests = await persistence.loadPullRequests()
        isInitialLoad = pullRequests.isEmpty
    }

    func refresh() async {
        guard let pollingService else { return }
        isLoading = true
        error = nil
        do {
            pullRequests = try await pollingService.refresh()
            lastRefresh = Date()
            isInitialLoad = false
            invalidateSummaries()

            // Send notifications for new priority PRs with passing CI
            notificationService?.notifyIfNeeded(prs: pullRequests)
            notificationService?.pruneNotified(currentPRIDs: Set(pullRequests.map(\.id)))
            // Re-generate summaries for collapsed sections
            for category in collapsedSections {
                generateSummaryIfNeeded(for: category)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func startPolling(intervalSeconds: Int) {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func toggleSection(_ category: PRCategory) {
        if collapsedSections.contains(category) {
            collapsedSections.remove(category)
        } else {
            collapsedSections.insert(category)
            generateSummaryIfNeeded(for: category)
        }
    }

    func generateSummaryIfNeeded(for category: PRCategory) {
        guard categorySummaries[category] == nil else { return }
        guard let llmProvider else { return }

        let prs = filtered(category)
        guard !prs.isEmpty else { return }

        summaryTasks[category]?.cancel()
        summaryTasks[category] = Task {
            let summary = await Self.generateSummary(prs: prs, category: category, llm: llmProvider)
            if !Task.isCancelled {
                categorySummaries[category] = summary
            }
        }
    }

    func invalidateSummaries() {
        for task in summaryTasks.values { task.cancel() }
        summaryTasks.removeAll()
        categorySummaries.removeAll()
    }

    private static func generateSummary(prs: [PullRequest], category: PRCategory, llm: any LLMProvider) async -> String {
        let prList = prs.prefix(15).map { "- \($0.title) (\($0.repoShortName) by \($0.author))" }.joined(separator: "\n")
        let prompt = """
            Summarize these \(prs.count) \(category.displayName) PRs in one brief sentence (under 80 chars). \
            Focus on the themes or areas of code being changed. No preamble, just the summary.

            \(prList)
            """

        do {
            let result = try await llm.complete(
                systemPrompt: "You write ultra-concise PR summaries. One sentence, no markdown.",
                userPrompt: prompt
            )
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "\(prs.count) pull requests"
        }
    }

    func overrideCategory(prID: String, to category: PRCategory) {
        guard let idx = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        pullRequests[idx].category = category
        pullRequests[idx].categoryOverridden = true
        pullRequests[idx].categoryReason = "Manually set to \(category.displayName)"
        Task {
            try? await persistence?.savePullRequests(pullRequests)
        }
    }

    func toggleFlag(prID: String) {
        guard let idx = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        pullRequests[idx].isFlagged.toggle()
        Task {
            try? await persistence?.savePullRequests(pullRequests)
        }
    }
}
