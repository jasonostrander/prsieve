import Foundation

// MARK: - Minimal Test Runner

@MainActor
final class TestRunner {
    var totalTests = 0
    var passedTests = 0
    var failedTests: [(String, String)] = []

    func check(_ condition: Bool, _ message: String, line: Int = #line) {
        totalTests += 1
        if condition {
            passedTests += 1
        } else {
            failedTests.append((message, "line \(line)"))
        }
    }

    func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, line: Int = #line) {
        totalTests += 1
        if a == b {
            passedTests += 1
        } else {
            failedTests.append((message, "expected \(b), got \(a) (line \(line))"))
        }
    }

    func report() {
        print("\n\(passedTests)/\(totalTests) tests passed")
        if !failedTests.isEmpty {
            print("\nFailed:")
            for (name, detail) in failedTests {
                print("  ✗ \(name): \(detail)")
            }
        } else {
            print("All tests passed!")
        }
    }
}

// MARK: - Test Helpers

actor MockLLMClient: LLMProvider {
    var response = #"{"category": "low", "reason": "Not in user's domain"}"#
    var shouldThrow = false
    var callCount = 0

    func setResponse(_ response: String) { self.response = response }
    func setShouldThrow(_ value: Bool) { shouldThrow = value }
    func getCallCount() -> Int { callCount }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        callCount += 1
        if shouldThrow { throw LLMError.notConfigured }
        return response
    }
}

func makePR(
    title: String = "Fix a bug",
    author: String = "someone",
    isDraft: Bool = false,
    labels: [String] = [],
    filesChanged: [String] = ["src/main.swift"],
    isMentioned: Bool = false,
    isRequestedReviewer: Bool = true
) -> PullRequest {
    PullRequest(
        repoFullName: "owner/repo",
        number: 1,
        title: title,
        author: author,
        authorAvatarURL: nil,
        htmlURL: URL(string: "https://github.com/owner/repo/pull/1")!,
        createdAt: Date().addingTimeInterval(-3600),
        updatedAt: Date(),
        isDraft: isDraft,
        labels: labels,
        headBranch: "feature",
        baseBranch: "main",
        body: "Some description",
        filesChanged: filesChanged,
        reviewers: [],
        humanCommentCount: 0,
        isRequestedReviewer: isRequestedReviewer,
        isMentioned: isMentioned,
        category: .low,
        categoryOverridden: false,
        categoryReason: "",
        buildStatus: nil,
        isMerged: false,
        isClosed: false,
        isFlagged: false,
        lastCategorizedAt: nil
    )
}

func makeReview(login: String, state: String) -> GitHubReview {
    GitHubReview(state: state, user: GitHubUser(login: login, avatarUrl: "https://example.com/\(login).png"))
}

// MARK: - Tests

@MainActor
func runAllTests() async {
    let t = TestRunner()

    // --- Pre-filter: Drafts ---

    do {
        let llm = MockLLMClient()
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(isDraft: true), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .noise, "draft → noise")
        t.checkEqual(result.reason, "Draft PR", "draft reason")
        let calls = await llm.getCallCount()
        t.checkEqual(calls, 0, "draft skips LLM")
    }

    // --- Pre-filter: Releases ---

    t.check(CategorizationService.isReleasePR(makePR(title: "[releases] v2.3.0")), "[releases] prefix")
    t.check(CategorizationService.isReleasePR(makePR(title: "[Release] Hotfix 1.2.3")), "[Release] prefix")
    t.check(CategorizationService.isReleasePR(makePR(title: "Release 4.0.0")), "Release space prefix")
    t.check(CategorizationService.isReleasePR(makePR(title: "Bump version for release", author: "deploy-machine-user")), "machine-user release")
    t.check(!CategorizationService.isReleasePR(makePR(title: "Fix released bug in cart")), "normal PR not release")
    t.check(!CategorizationService.isReleasePR(makePR(title: "Update deps", author: "deploy-machine-user")), "machine-user non-release")

    // --- Pre-filter: Strings/Translations ---

    t.check(CategorizationService.isStringsPR(makePR(title: "Update strings for checkout")), "title with strings")
    t.check(CategorizationService.isStringsPR(makePR(title: "Add French translations")), "title with translations")
    t.check(CategorizationService.isStringsPR(makePR(title: "l10n: Update Japanese locale")), "title with l10n")

    t.check(CategorizationService.isStringsPR(makePR(
        title: "Auto update",
        filesChanged: ["app/src/main/res/values/strings.xml", "app/src/main/res/values-es/strings.xml"]
    )), "all files are string resources")

    t.check(!CategorizationService.isStringsPR(makePR(
        title: "Update cart",
        filesChanged: ["app/src/main/res/values/strings.xml", "app/src/main/java/Cart.kt"]
    )), "mixed files not strings")

    t.check(!CategorizationService.isStringsPR(makePR(title: "Fix cart bug", filesChanged: ["src/Cart.swift"])), "normal PR not strings")

    t.check(CategorizationService.isStringsPR(makePR(
        title: "Auto update",
        filesChanged: ["Localizable.strings", "InfoPlist.stringsdict"]
    )), "iOS string files")

    t.check(CategorizationService.isStringsPR(makePR(
        title: "Auto update",
        filesChanged: ["translations/en.json", "translations/fr.json"]
    )), "translations directory")

    // --- Pre-filter: @Mentioned ---

    do {
        let llm = MockLLMClient()
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(isMentioned: true), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .priority, "mentioned → priority")
        t.check(result.reason.contains("@mentioned"), "mentioned reason")
        let calls = await llm.getCallCount()
        t.checkEqual(calls, 0, "mentioned skips LLM")
    }

    // --- LLM Categorization ---

    do {
        let llm = MockLLMClient()
        await llm.setResponse(#"{"category": "priority", "reason": "Touches cart module"}"#)
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(), codeowners: nil, userContext: "I own the cart module")
        t.checkEqual(result.category, .priority, "LLM returns priority")
        t.checkEqual(result.reason, "Touches cart module", "LLM reason preserved")
        let calls = await llm.getCallCount()
        t.checkEqual(calls, 1, "LLM called once")
    }

    do {
        let llm = MockLLMClient()
        await llm.setResponse("```json\n{\"category\": \"priority\", \"reason\": \"In user domain\"}\n```")
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .priority, "LLM code block parsed")
    }

    do {
        let llm = MockLLMClient()
        await llm.setShouldThrow(true)
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .low, "LLM failure → low")
        t.check(result.reason.contains("LLM unavailable"), "LLM failure reason")
    }

    do {
        let llm = MockLLMClient()
        await llm.setResponse("I don't know how to respond in JSON")
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .low, "unparsable → low")
        t.check(result.reason.contains("Could not parse"), "unparsable reason")
    }

    // --- Pre-filter Priority Order ---

    do {
        let llm = MockLLMClient()
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(isDraft: true, isMentioned: true), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .noise, "draft wins over mentioned")
    }

    do {
        let llm = MockLLMClient()
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(title: "[releases] v1.0", isMentioned: true), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .noise, "release wins over mentioned")
    }

    // --- Bot Detection ---

    t.check(GitHubClient.isBot("dependabot[bot]"), "bot: github [bot] suffix")
    t.check(GitHubClient.isBot("some-lint-bot"), "bot: -bot suffix")
    t.check(GitHubClient.isBot("deploy-machine-user"), "bot: machine-user")
    t.check(GitHubClient.isBot("dependabot"), "bot: dependabot")
    t.check(GitHubClient.isBot("renovate"), "bot: renovate")
    t.check(GitHubClient.isBot("codecov"), "bot: codecov")
    t.check(GitHubClient.isBot("github-actions"), "bot: github-actions")
    t.check(!GitHubClient.isBot("jasonostrander"), "human: jasonostrander")
    t.check(!GitHubClient.isBot("alice"), "human: alice")
    t.check(!GitHubClient.isBot("bob-smith"), "human: bob-smith")

    // --- Review Status ---

    t.checkEqual(GitHubClient.latestReviewStatus(from: []), .pending, "no reviews → pending")
    t.checkEqual(
        GitHubClient.latestReviewStatus(from: [makeReview(login: "alice", state: "APPROVED")]),
        .approved, "single approval"
    )
    t.checkEqual(
        GitHubClient.latestReviewStatus(from: [
            makeReview(login: "alice", state: "APPROVED"),
            makeReview(login: "bob", state: "CHANGES_REQUESTED"),
        ]),
        .changesRequested, "changes requested overrides"
    )
    t.checkEqual(
        GitHubClient.latestReviewStatus(from: [makeReview(login: "alice", state: "COMMENTED")]),
        .pending, "comment-only → pending"
    )
    t.checkEqual(
        GitHubClient.latestReviewStatus(from: [
            makeReview(login: "alice", state: "CHANGES_REQUESTED"),
            makeReview(login: "alice", state: "APPROVED"),
        ]),
        .approved, "later approval wins"
    )

    // --- Per-Reviewer Status ---

    do {
        let reviewers = GitHubClient.perReviewerStatus(from: [
            makeReview(login: "alice", state: "APPROVED"),
            makeReview(login: "bob", state: "CHANGES_REQUESTED"),
        ])
        t.checkEqual(reviewers.count, 2, "two reviewers")
        t.checkEqual(reviewers.first { $0.login == "alice" }?.state, .approved, "alice approved")
        t.checkEqual(reviewers.first { $0.login == "bob" }?.state, .changesRequested, "bob changes requested")
    }

    do {
        let reviewers = GitHubClient.perReviewerStatus(from: [
            makeReview(login: "alice", state: "CHANGES_REQUESTED"),
            makeReview(login: "alice", state: "APPROVED"),
        ])
        t.checkEqual(reviewers.count, 1, "deduped to one reviewer")
        t.checkEqual(reviewers[0].state, .approved, "latest review wins")
    }

    do {
        let reviewers = GitHubClient.perReviewerStatus(from: [
            makeReview(login: "alice", state: "APPROVED"),
            makeReview(login: "codecov[bot]", state: "COMMENTED"),
            makeReview(login: "some-lint-bot", state: "COMMENTED"),
        ])
        t.checkEqual(reviewers.count, 1, "bots filtered")
        t.checkEqual(reviewers[0].login, "alice", "only human remains")
    }

    do {
        let reviewers = GitHubClient.perReviewerStatus(from: [makeReview(login: "alice", state: "COMMENTED")])
        t.checkEqual(reviewers[0].state, .commented, "commented state preserved")
    }

    do {
        let reviewers = GitHubClient.perReviewerStatus(from: [makeReview(login: "alice", state: "APPROVED")])
        t.checkEqual(reviewers[0].avatarURL?.absoluteString, "https://example.com/alice.png", "avatar URL preserved")
    }

    // --- BuildStatus ---

    do {
        t.checkEqual(BuildStatus.passed.symbol, "checkmark.circle.fill", "passed symbol")
        t.checkEqual(BuildStatus.failed.symbol, "xmark.circle.fill", "failed symbol")
        t.checkEqual(BuildStatus.running.symbol, "arrow.triangle.2.circlepath", "running symbol")
    }

    // GitHubCombinedStatus decoding
    do {
        let json = #"{"state": "success", "total_count": 3}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try! decoder.decode(GitHubCombinedStatus.self, from: json.data(using: .utf8)!)
        t.checkEqual(status.state, "success", "combined status state")
        t.checkEqual(status.totalCount, 3, "combined status total count")
    }

    do {
        let json = #"{"state": "pending", "total_count": 0}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try! decoder.decode(GitHubCombinedStatus.self, from: json.data(using: .utf8)!)
        t.checkEqual(status.state, "pending", "pending state")
        t.checkEqual(status.totalCount, 0, "no checks pending")
    }

    // Build status on PR model
    do {
        var pr = makePR()
        t.check(pr.buildStatus == nil, "default buildStatus is nil")
        pr.buildStatus = .passed
        t.checkEqual(pr.buildStatus, .passed, "buildStatus can be set to passed")
        pr.buildStatus = .failed
        t.checkEqual(pr.buildStatus, .failed, "buildStatus can be set to failed")
    }

    // --- PullRequest Model ---

    do {
        let pr = makePR()
        t.checkEqual(pr.id, "owner/repo#1", "PR id format")
        t.checkEqual(pr.repoShortName, "repo", "repo short name")
        t.checkEqual(pr.ageDescription, "1h", "age description")
    }

    // --- Report ---
    t.report()
    if !t.failedTests.isEmpty {
        _Exit(1)
    }
}

@main
struct TestEntry {
    static func main() async {
        await runAllTests()
    }
}
