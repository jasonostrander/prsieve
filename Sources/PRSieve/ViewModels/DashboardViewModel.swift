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

    private var pollingService: PollingService?
    private(set) var persistence: PersistenceService?
    private var pollingTask: Task<Void, Never>?

    var mustReview: [PullRequest] { filtered(.mustReview) }
    var shouldKnow: [PullRequest] { filtered(.shouldKnow) }
    var fyi: [PullRequest] { filtered(.fyi) }

    var totalCount: Int { mustReview.count + shouldKnow.count + fyi.count }

    private func filtered(_ category: PRCategory) -> [PullRequest] {
        pullRequests
            .filter { $0.category == category }
            .filter { showMerged || !$0.isMerged }
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

    func setup(persistence: PersistenceService, pollingService: PollingService) {
        self.persistence = persistence
        self.pollingService = pollingService
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
