import SwiftUI

enum LLMTestResult {
    case success
    case failure(String)
}

struct PromptTestResult: Identifiable, Sendable {
    var id: String { pr.id }
    let pr: PullRequest
    let originalCategory: PRCategory
    let originalReason: String?
    let newCategory: PRCategory
    let newReason: String

    var changed: Bool { originalCategory != newCategory }

    /// Sort order: changed results first, then by new category, then most-recently updated.
    static func defaultSort(_ lhs: PromptTestResult, _ rhs: PromptTestResult) -> Bool {
        if lhs.changed != rhs.changed { return lhs.changed && !rhs.changed }
        if lhs.newCategory != rhs.newCategory { return lhs.newCategory < rhs.newCategory }
        return lhs.pr.updatedAt > rhs.pr.updatedAt
    }
}

struct PromptTestProgress: Sendable, Equatable {
    var completed: Int
    var total: Int
}

@MainActor @Observable
final class SettingsViewModel {
    var settings: AppSettings = .default
    var githubToken: String = ""
    var newRepoText: String = ""
    var isSaving = false
    var saveError: String?
    var llmTestResult: LLMTestResult?
    var isTestingLLM = false
    var notificationAuthState: NotificationAuthState = .notDetermined
    var isRequestingNotifications = false

    var isRunningPromptTest = false
    var promptTestProgress: PromptTestProgress?
    var promptTestResults: [PromptTestResult] = []
    var promptTestError: String?
    var isPromptTestSheetPresented = false

    private let persistence: PersistenceService
    private var promptTestTask: Task<Void, Never>?

    init(persistence: PersistenceService) {
        self.persistence = persistence
    }

    func load() async {
        settings = await persistence.loadSettings()
        githubToken = await persistence.loadToken(forKey: "github_token") ?? ""
        if settings.llmModel.isEmpty {
            settings.llmModel = LLMConfig.loadFromBundle().model
        }
        // Auth state is fetched lazily by the view via refreshNotificationAuthState().
    }

    func refreshNotificationAuthState() async {
        notificationAuthState = await NotificationService.systemAuthorizationState()
    }

    func requestNotificationPermission() async {
        isRequestingNotifications = true
        notificationAuthState = await NotificationService.requestSystemAuthorization()
        isRequestingNotifications = false
    }

    func openNotificationSystemSettings() {
        NotificationService.openSystemSettings()
    }

    func save() async {
        isSaving = true
        saveError = nil
        do {
            try await persistence.saveSettings(settings)
            await persistence.saveToken(githubToken, forKey: "github_token")
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    func testLLMConfig() async {
        let bundleConfig = LLMConfig.loadFromBundle()
        let model = settings.llmModel
        guard !bundleConfig.endpoint.isEmpty, bundleConfig.apiKey != "sk-..." else {
            llmTestResult = .failure("LLM endpoint or API key not configured in llm_config.json.")
            return
        }
        isTestingLLM = true
        llmTestResult = nil
        let client = LLMClient(endpoint: bundleConfig.endpoint, apiKey: bundleConfig.apiKey, model: model)
        do {
            _ = try await client.complete(
                systemPrompt: "Reply with exactly: {\"category\":\"low\",\"reason\":\"ok\"}",
                userPrompt: "test"
            )
            llmTestResult = .success
        } catch let err as LLMError {
            switch err {
            case .notConfigured:
                llmTestResult = .failure("LLM is not configured.")
            case .requestFailed(let msg):
                let lower = msg.lowercased()
                if lower.contains("401") || lower.contains("unauthorized") {
                    llmTestResult = .failure("Authentication failed — check API key in llm_config.json.")
                } else if lower.contains("404") || lower.contains("not found") {
                    llmTestResult = .failure("Model \"\(model)\" not found.")
                } else if lower.contains("429") || lower.contains("rate limit") {
                    llmTestResult = .failure("Rate limit reached — try again in a moment.")
                } else {
                    llmTestResult = .failure("Request failed: \(msg)")
                }
            case .emptyResponse:
                llmTestResult = .failure("LLM returned an empty response.")
            }
        } catch {
            llmTestResult = .failure(error.localizedDescription)
        }
        isTestingLLM = false
    }

    func addRepo() {
        let repo = newRepoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, repo.contains("/") else { return }
        guard !settings.repos.contains(where: { $0.repo == repo }) else { return }
        settings.repos.append(RepoConfig(repo: repo))
        newRepoText = ""
    }

    func removeRepo(at offsets: IndexSet) {
        settings.repos.remove(atOffsets: offsets)
    }

    func removeRepo(_ repo: RepoConfig) {
        settings.repos.removeAll { $0.id == repo.id }
    }

    // MARK: - Prompt Test

    func startPromptTest() {
        guard !isRunningPromptTest else { return }
        isPromptTestSheetPresented = true
        promptTestTask?.cancel()
        promptTestTask = Task { await runPromptTest() }
    }

    func cancelPromptTest() {
        promptTestTask?.cancel()
        promptTestTask = nil
        isRunningPromptTest = false
    }

    private func runPromptTest() async {
        isRunningPromptTest = true
        promptTestError = nil
        promptTestResults = []
        promptTestProgress = PromptTestProgress(completed: 0, total: 0)
        defer {
            isRunningPromptTest = false
            promptTestTask = nil
        }

        let prs = await persistence.loadPullRequests()
            .filter { !$0.isClosed && !$0.isMerged }
        guard !prs.isEmpty else {
            promptTestError = "No PRs to test. Refresh from the dashboard first."
            promptTestProgress = nil
            return
        }

        let bundleConfig = LLMConfig.loadFromBundle()
        guard !bundleConfig.endpoint.isEmpty, bundleConfig.apiKey != "sk-..." else {
            promptTestError = "LLM endpoint or API key not configured in llm_config.json."
            promptTestProgress = nil
            return
        }
        let model = settings.llmModel.isEmpty ? bundleConfig.model : settings.llmModel
        let llm = LLMClient(endpoint: bundleConfig.endpoint, apiKey: bundleConfig.apiKey, model: model)
        let catService = CategorizationService(llmClient: llm)
        let userContext = settings.codeownerContext
        let username = settings.githubUsername

        var codeownersByRepo: [String: String?] = [:]
        for repo in Set(prs.map(\.repoFullName)) {
            let text = await persistence.loadCodeowners(forRepo: repo)
            codeownersByRepo[repo] = text.flatMap { $0.isEmpty ? nil : $0 }
        }
        let codeownersByRepoLocal = codeownersByRepo

        promptTestProgress = PromptTestProgress(completed: 0, total: prs.count)
        var results: [PromptTestResult] = []

        await withTaskGroup(of: PromptTestResult.self) { group in
            let maxConcurrency = 5
            var nextIdx = 0

            for _ in 0..<min(maxConcurrency, prs.count) {
                let pr = prs[nextIdx]
                nextIdx += 1
                group.addTask {
                    let codeowners = codeownersByRepoLocal[pr.repoFullName] ?? nil
                    let r = await catService.categorize(
                        pr: pr, codeowners: codeowners, userContext: userContext, username: username
                    )
                    return PromptTestResult(
                        pr: pr,
                        originalCategory: pr.category,
                        originalReason: pr.categoryReason,
                        newCategory: r.category,
                        newReason: r.reason
                    )
                }
            }

            for await result in group {
                if Task.isCancelled { break }
                results.append(result)
                if let p = promptTestProgress {
                    promptTestProgress = PromptTestProgress(completed: p.completed + 1, total: p.total)
                }
                if nextIdx < prs.count {
                    let pr = prs[nextIdx]
                    nextIdx += 1
                    group.addTask {
                        let codeowners = codeownersByRepoLocal[pr.repoFullName] ?? nil
                        let r = await catService.categorize(
                            pr: pr, codeowners: codeowners, userContext: userContext, username: username
                        )
                        return PromptTestResult(
                            pr: pr,
                            originalCategory: pr.category,
                            originalReason: pr.categoryReason,
                            newCategory: r.category,
                            newReason: r.reason
                        )
                    }
                }
            }
            group.cancelAll()
        }

        promptTestResults = results.sorted(by: PromptTestResult.defaultSort)
        promptTestProgress = nil
    }
}
