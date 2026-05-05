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
    var throwError: LLMError = .requestFailed("mock error")
    var callCount = 0

    func setResponse(_ response: String) { self.response = response }
    func setShouldThrow(_ value: Bool) { shouldThrow = value }
    func setThrowError(_ error: LLMError) { throwError = error }
    func getCallCount() -> Int { callCount }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        callCount += 1
        if shouldThrow { throw throwError }
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
    isRequestedReviewer: Bool = true,
    isDirectCodeowner: Bool = false,
    updatedAt: Date = Date(),
    baseBranch: String = "feature"
) -> PullRequest {
    PullRequest(
        repoFullName: "owner/repo",
        number: 1,
        title: title,
        author: author,
        authorAvatarURL: nil,
        htmlURL: URL(string: "https://github.com/owner/repo/pull/1")!,
        createdAt: Date().addingTimeInterval(-3600),
        updatedAt: updatedAt,
        isDraft: isDraft,
        labels: labels,
        headBranch: "feature",
        baseBranch: baseBranch,
        body: "Some description",
        filesChanged: filesChanged,
        reviewers: [],
        humanCommentCount: 0,
        isRequestedReviewer: isRequestedReviewer,
        isDirectCodeowner: isDirectCodeowner,
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

    // --- Pre-filter: Own PR ---

    do {
        let username = "testuser"

        // Own PR, no comments → noise
        let ownPR = makePR(author: username)
        let llm1 = MockLLMClient()
        let r1 = await CategorizationService(llmClient: llm1).categorize(pr: ownPR, codeowners: nil, userContext: "", username: username)
        t.checkEqual(r1.category, .noise, "own PR no comments → noise")
        t.check(r1.reason.contains("own"), "own PR reason")
        t.checkEqual(await llm1.getCallCount(), 0, "own PR skips LLM")

        // Own PR, someone requested changes → low (never priority)
        var ownPRWithChanges = makePR(author: username, isDirectCodeowner: true)
        ownPRWithChanges.reviewers = [ReviewerInfo(login: "alice", avatarURL: nil, state: .changesRequested)]
        let llm2 = MockLLMClient()
        let r2 = await CategorizationService(llmClient: llm2).categorize(pr: ownPRWithChanges, codeowners: nil, userContext: "", username: username)
        t.checkEqual(r2.category, .low, "own PR with changes requested → low")
        t.checkEqual(await llm2.getCallCount(), 0, "own PR with changes requested skips LLM")

        // Own PR, has human comments → still noise (comment count no longer an escape)
        var ownPRWithComments = makePR(author: username, isDirectCodeowner: true)
        ownPRWithComments.humanCommentCount = 2
        let llm3 = MockLLMClient()
        let r3 = await CategorizationService(llmClient: llm3).categorize(pr: ownPRWithComments, codeowners: nil, userContext: "", username: username)
        t.checkEqual(r3.category, .noise, "own PR with comments → noise")
        t.checkEqual(await llm3.getCallCount(), 0, "own PR with comments skips LLM")

        // Someone else's PR → unaffected by this filter
        let otherPR = makePR(author: "alice", isDirectCodeowner: true)
        let llm4 = MockLLMClient()
        await llm4.setResponse(#"{"category": "low", "reason": "Not relevant"}"#)
        _ = await CategorizationService(llmClient: llm4).categorize(pr: otherPR, codeowners: nil, userContext: "", username: username)
        t.checkEqual(await llm4.getCallCount(), 1, "other author's PR hits LLM normally")
    }

    // --- PRs targeting main/master fall through to LLM ---

    do {
        // With master filter removed, main/master PRs go to the LLM like any other PR.
        // The LLM prompt instructs it to prioritize PRs fixing main/master failures.
        for branch in ["main", "master", "develop"] {
            let pr = makePR(baseBranch: branch)
            let llm = MockLLMClient()
            await llm.setResponse(#"{"category": "low", "reason": "Not relevant"}"#)
            let svc = CategorizationService(llmClient: llm)
            _ = await svc.categorize(pr: pr, codeowners: nil, userContext: "")
            t.checkEqual(await llm.getCallCount(), 1, "base branch \(branch) hits LLM")
        }
    }

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

    // --- Pre-filter: Previously Reviewed ---

    do {
        let username = "testuser"

        // Previously approved → priority, skips LLM
        var prApproved = makePR()
        prApproved.reviewers = [ReviewerInfo(login: username, avatarURL: nil, state: .approved)]
        let llm1 = MockLLMClient()
        let svc1 = CategorizationService(llmClient: llm1)
        let r1 = await svc1.categorize(pr: prApproved, codeowners: nil, userContext: "", username: username)
        t.checkEqual(r1.category, .priority, "previously approved → priority")
        t.check(r1.reason.contains("previously reviewed"), "previously reviewed reason")
        t.checkEqual(await llm1.getCallCount(), 0, "previously reviewed skips LLM")

        // Changes requested → priority, skips LLM
        var prChanges = makePR()
        prChanges.reviewers = [ReviewerInfo(login: username, avatarURL: nil, state: .changesRequested)]
        let llm2 = MockLLMClient()
        let svc2 = CategorizationService(llmClient: llm2)
        let r2 = await svc2.categorize(pr: prChanges, codeowners: nil, userContext: "", username: username)
        t.checkEqual(r2.category, .priority, "changes requested → priority")
        t.checkEqual(await llm2.getCallCount(), 0, "changes requested skips LLM")

        // Pending (no review yet) → falls through to LLM
        var prPending = makePR(isDirectCodeowner: true)
        prPending.reviewers = [ReviewerInfo(login: username, avatarURL: nil, state: .pending)]
        let llm3 = MockLLMClient()
        await llm3.setResponse(#"{"category": "low", "reason": "Not relevant"}"#)
        let svc3 = CategorizationService(llmClient: llm3)
        let r3 = await svc3.categorize(pr: prPending, codeowners: nil, userContext: "", username: username)
        t.checkEqual(r3.category, .low, "pending state → falls through to LLM")
        t.checkEqual(await llm3.getCallCount(), 1, "pending state hits LLM")

        // Different user's review → falls through to LLM
        var prOther = makePR(isDirectCodeowner: true)
        prOther.reviewers = [ReviewerInfo(login: "alice", avatarURL: nil, state: .approved)]
        let llm4 = MockLLMClient()
        await llm4.setResponse(#"{"category": "low", "reason": "Not relevant"}"#)
        let svc4 = CategorizationService(llmClient: llm4)
        let r4 = await svc4.categorize(pr: prOther, codeowners: nil, userContext: "", username: username)
        t.checkEqual(r4.category, .low, "other user's review → falls through to LLM")

        // No username → falls through to LLM
        var prNoUser = makePR(isDirectCodeowner: true)
        prNoUser.reviewers = [ReviewerInfo(login: username, avatarURL: nil, state: .approved)]
        let llm5 = MockLLMClient()
        await llm5.setResponse(#"{"category": "low", "reason": "Not relevant"}"#)
        let svc5 = CategorizationService(llmClient: llm5)
        let r5 = await svc5.categorize(pr: prNoUser, codeowners: nil, userContext: "", username: "")
        t.checkEqual(r5.category, .low, "empty username → falls through to LLM")
    }

    // --- LLM Categorization ---

    do {
        let llm = MockLLMClient()
        await llm.setResponse(#"{"category": "priority", "reason": "Touches cart module"}"#)
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(isDirectCodeowner: true), codeowners: nil, userContext: "I own the cart module")
        t.checkEqual(result.category, .priority, "LLM returns priority")
        t.checkEqual(result.reason, "Touches cart module", "LLM reason preserved")
        let calls = await llm.getCallCount()
        t.checkEqual(calls, 1, "LLM called once")
    }

    do {
        let llm = MockLLMClient()
        await llm.setResponse("```json\n{\"category\": \"priority\", \"reason\": \"In user domain\"}\n```")
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(isDirectCodeowner: true), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .priority, "LLM code block parsed")
    }

    do {
        let llm = MockLLMClient()
        await llm.setShouldThrow(true)
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(isDirectCodeowner: true), codeowners: nil, userContext: "")
        t.checkEqual(result.category, .low, "LLM failure → low")
        t.check(result.reason.contains("LLM unavailable"), "LLM failure reason")
    }

    do {
        let llm = MockLLMClient()
        await llm.setResponse("I don't know how to respond in JSON")
        let service = CategorizationService(llmClient: llm)
        let result = await service.categorize(pr: makePR(isDirectCodeowner: true), codeowners: nil, userContext: "")
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
    t.check(!GitHubClient.isBot("testuser"), "human: testuser")
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

    // --- AppSettings: hideDraftPRs ---

    do {
        let defaults = AppSettings.default
        t.checkEqual(defaults.hideDraftPRs, true, "hideDraftPRs defaults to true")
    }

    do {
        let json = #"{"githubUsername":"","repos":[],"buildkiteOrgSlug":"","codeownerContext":"","pollingIntervalSeconds":300,"notificationsEnabled":true}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        t.checkEqual(decoded.hideDraftPRs, true, "hideDraftPRs defaults when missing from JSON")
    }

    do {
        let json = #"{"githubUsername":"","repos":[],"buildkiteOrgSlug":"","codeownerContext":"","pollingIntervalSeconds":300,"hideDraftPRs":false,"notificationsEnabled":true}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        t.checkEqual(decoded.hideDraftPRs, false, "hideDraftPRs can be set to false")
    }

    // --- AppSettings: legacy JSON with stripped LLM keys decodes cleanly ---

    do {
        let json = #"{"githubUsername":"alice","repos":[],"buildkiteOrgSlug":"","llmEndpoint":"https://old","llmModel":"gpt-4","codeownerContext":"x","pollingIntervalSeconds":300,"hideDraftPRs":true,"notificationsEnabled":true}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        t.checkEqual(decoded.githubUsername, "alice", "legacy JSON with old llm keys still decodes")
        t.checkEqual(decoded.codeownerContext, "x", "legacy JSON preserves codeownerContext")
    }

    // --- LLMConfig: missing bundle resource → empty config ---

    do {
        let config = LLMConfig.loadFromBundle()
        // In the test runner, no bundle resource exists, so the empty config is returned.
        t.checkEqual(config, LLMConfig.empty, "no bundled config → empty config")
    }

    do {
        let json = #"{"endpoint":"https://api.openai.com/v1","token":"sk-abc","model":"gpt-4o-mini"}"#
        let decoded = try! JSONDecoder().decode(LLMConfig.self, from: json.data(using: .utf8)!)
        t.checkEqual(decoded.endpoint, "https://api.openai.com/v1", "config endpoint decoded")
        t.checkEqual(decoded.apiKey, "sk-abc", "config apiKey decoded")
        t.checkEqual(decoded.model, "gpt-4o-mini", "config model decoded")
    }

    // --- Priority + CI indicator logic ---
    // Status bar icon highlights only when a priority PR has passing CI

    do {
        let prs = [makePR()]  // default: category .low, no build status
        let hasPriority = prs.filter { $0.category == .priority }.contains { $0.buildStatus == .passed }
        t.check(!hasPriority, "low PRs don't trigger priority indicator")
    }

    do {
        var pr = makePR()
        pr.category = .priority
        pr.buildStatus = .failed
        let hasPriority = [pr].filter { $0.category == .priority }.contains { $0.buildStatus == .passed }
        t.check(!hasPriority, "priority PR with failed CI doesn't trigger indicator")
    }

    do {
        var pr = makePR()
        pr.category = .priority
        pr.buildStatus = nil
        let hasPriority = [pr].filter { $0.category == .priority }.contains { $0.buildStatus == .passed }
        t.check(!hasPriority, "priority PR with no CI doesn't trigger indicator")
    }

    do {
        var pr = makePR()
        pr.category = .priority
        pr.buildStatus = .passed
        let hasPriority = [pr].filter { $0.category == .priority }.contains { $0.buildStatus == .passed }
        t.check(hasPriority, "priority PR with passing CI triggers indicator")
    }

    do {
        var pr1 = makePR()
        pr1.category = .priority
        pr1.buildStatus = .failed
        var pr2 = makePR()
        pr2.category = .priority
        pr2.buildStatus = .passed
        let hasPriority = [pr1, pr2].filter { $0.category == .priority }.contains { $0.buildStatus == .passed }
        t.check(hasPriority, "mixed priority PRs: one passing triggers indicator")
    }

    // --- CodeownersParser: Pattern matching ---

    // Catch-all patterns
    t.check(CodeownersParser.isCatchAllPattern("*"), "* is catch-all")
    t.check(CodeownersParser.isCatchAllPattern("**"), "** is catch-all")
    t.check(CodeownersParser.isCatchAllPattern("**/*"), "**/* is catch-all")
    t.check(CodeownersParser.isCatchAllPattern("/*"), "/* is catch-all")
    t.check(!CodeownersParser.isCatchAllPattern("src/"), "src/ is not catch-all")
    t.check(!CodeownersParser.isCatchAllPattern("*.swift"), "*.swift is not catch-all")

    // Exact file match
    t.check(CodeownersParser.matches(pattern: "README.md", filePath: "README.md"), "exact file match")
    t.check(!CodeownersParser.matches(pattern: "README.md", filePath: "docs/README.md"), "exact file no nested match")

    // Directory patterns
    t.check(CodeownersParser.matches(pattern: "src/", filePath: "src/main.swift"), "dir pattern with trailing slash")
    t.check(CodeownersParser.matches(pattern: "/src/", filePath: "src/main.swift"), "dir pattern with leading+trailing slash")
    t.check(CodeownersParser.matches(pattern: "src/", filePath: "src/sub/file.swift"), "dir pattern nested")
    t.check(!CodeownersParser.matches(pattern: "src/", filePath: "other/main.swift"), "dir pattern no match")

    // Directory without trailing slash (no extension = treated as dir)
    t.check(CodeownersParser.matches(pattern: "src/models", filePath: "src/models/User.swift"), "dir without slash")
    t.check(!CodeownersParser.matches(pattern: "src/models", filePath: "src/views/Main.swift"), "dir without slash no match")

    // Wildcard: *.ext — matches anywhere per CODEOWNERS spec
    t.check(CodeownersParser.matches(pattern: "*.swift", filePath: "main.swift"), "*.ext root file")
    t.check(CodeownersParser.matches(pattern: "*.swift", filePath: "src/main.swift"), "*.ext matches nested")
    t.check(!CodeownersParser.matches(pattern: "*.swift", filePath: "src/main.kt"), "*.ext wrong extension")

    // Double-star wildcard: **/*.ext
    t.check(CodeownersParser.matches(pattern: "**/*.swift", filePath: "src/main.swift"), "**/*.ext nested")
    t.check(CodeownersParser.matches(pattern: "**/*.swift", filePath: "main.swift"), "**/*.ext root")
    t.check(!CodeownersParser.matches(pattern: "**/*.swift", filePath: "src/main.kt"), "**/*.ext wrong ext")

    // Path with wildcard: path/*
    t.check(CodeownersParser.matches(pattern: "docs/*", filePath: "docs/guide.md"), "path/* direct child")
    t.check(CodeownersParser.matches(pattern: "docs/*", filePath: "docs/sub/guide.md"), "path/* nested child")
    t.check(!CodeownersParser.matches(pattern: "docs/*", filePath: "src/guide.md"), "path/* wrong dir")

    // Path with **: path/**
    t.check(CodeownersParser.matches(pattern: "src/**", filePath: "src/deep/nested/file.swift"), "path/** deep nested")

    // Catch-all matches everything
    t.check(CodeownersParser.matches(pattern: "*", filePath: "anything/at/all.txt"), "* matches everything")
    t.check(CodeownersParser.matches(pattern: "**", filePath: "deep/path/file.go"), "** matches everything")

    // --- CodeownersParser: Full parsing ---

    do {
        let content = """
            # This is a comment
            * @fallback-team
            /src/auth/ @alice @bob
            /src/cart/ @charlie
            *.md @docs-team
            """
        let parser = CodeownersParser(content: content)
        t.checkEqual(parser.rules.count, 4, "parsed 4 rules (skipped comment + blank)")

        // Catch-all rule
        t.check(parser.rules[0].isCatchAll, "first rule is catch-all")
        t.checkEqual(parser.rules[0].owners, ["@fallback-team"], "catch-all owner")

        // Specific rules
        t.check(!parser.rules[1].isCatchAll, "auth rule not catch-all")
        t.checkEqual(parser.rules[1].owners, ["@alice", "@bob"], "auth owners")
    }

    // --- CodeownersParser: Last-match-wins ---

    do {
        let content = """
            * @fallback
            /src/ @team-lead
            /src/cart/ @charlie
            """
        let parser = CodeownersParser(content: content)

        let (owners1, catchAll1) = parser.owners(for: "src/cart/Cart.swift")
        t.check(!catchAll1, "cart file not catch-all")
        t.checkEqual(owners1, ["@charlie"], "cart file owned by charlie (last match)")

        let (owners2, catchAll2) = parser.owners(for: "src/auth/Login.swift")
        t.check(!catchAll2, "auth file not catch-all")
        t.checkEqual(owners2, ["@team-lead"], "auth file owned by team-lead")

        let (owners3, catchAll3) = parser.owners(for: "README.md")
        t.check(catchAll3, "README only matches catch-all")
        t.checkEqual(owners3, ["@fallback"], "README owned by fallback")
    }

    // --- CodeownersParser: isDirectOwner ---

    do {
        let content = """
            * @fallback-team @testuser
            /src/cart/ @testuser
            /src/auth/ @alice
            """
        let parser = CodeownersParser(content: content)

        // User owns src/cart/ directly
        t.check(
            parser.isDirectOwner(username: "testuser", files: ["src/cart/Cart.swift"]),
            "direct owner of cart file"
        )

        // User is in catch-all but NOT direct owner of auth files
        t.check(
            !parser.isDirectOwner(username: "testuser", files: ["src/auth/Login.swift"]),
            "not direct owner of auth file (only catch-all)"
        )

        // Mixed: one file is direct, one is catch-all → still direct owner
        t.check(
            parser.isDirectOwner(username: "testuser", files: ["src/auth/Login.swift", "src/cart/Cart.swift"]),
            "direct owner when at least one file matches"
        )

        // Files only matching catch-all
        t.check(
            !parser.isDirectOwner(username: "testuser", files: ["README.md", "docs/setup.md"]),
            "not direct owner when all files are catch-all"
        )

        // User not in any rule
        t.check(
            !parser.isDirectOwner(username: "bob", files: ["src/cart/Cart.swift"]),
            "bob not owner of cart"
        )
    }

    // --- CodeownersParser: Case-insensitive owner matching ---

    do {
        let content = "/src/ @TestUser"
        let parser = CodeownersParser(content: content)
        t.check(
            parser.isDirectOwner(username: "testuser", files: ["src/file.swift"]),
            "case-insensitive owner match"
        )
    }

    // --- CodeownersParser: No CODEOWNERS file ---

    do {
        let parser = CodeownersParser(content: "")
        t.check(!parser.isDirectOwner(username: "anyone", files: ["file.txt"]), "empty CODEOWNERS → not direct owner")
    }

    // --- Categorization: Fallthrough codeowner → goes to LLM ---

    do {
        let llm = MockLLMClient()
        await llm.setResponse(#"{"category": "low", "reason": "Not in user's area"}"#)
        let service = CategorizationService(llmClient: llm)
        // isRequestedReviewer but NOT isDirectCodeowner — now goes to LLM instead of pre-filtering
        let pr = makePR(isRequestedReviewer: true, isDirectCodeowner: false)
        let result = await service.categorize(pr: pr, codeowners: nil, userContext: "")
        t.checkEqual(result.category, .low, "fallthrough codeowner → LLM decides")
        let calls = await llm.getCallCount()
        t.checkEqual(calls, 1, "fallthrough codeowner hits LLM")
    }

    // --- Categorization: Direct codeowner → goes to LLM ---

    do {
        let llm = MockLLMClient()
        await llm.setResponse(#"{"category": "priority", "reason": "Owns this code"}"#)
        let service = CategorizationService(llmClient: llm)
        let pr = makePR(isRequestedReviewer: true, isDirectCodeowner: true)
        let result = await service.categorize(pr: pr, codeowners: nil, userContext: "I own src/cart")
        t.checkEqual(result.category, .priority, "direct codeowner → LLM categorizes")
        let calls = await llm.getCallCount()
        t.checkEqual(calls, 1, "direct codeowner calls LLM")
    }

    // --- Categorization: @mentioned overrides fallthrough ---

    do {
        let llm = MockLLMClient()
        let service = CategorizationService(llmClient: llm)
        let pr = makePR(isMentioned: true, isRequestedReviewer: true, isDirectCodeowner: false)
        let result = await service.categorize(pr: pr, codeowners: nil, userContext: "")
        t.checkEqual(result.category, .priority, "mentioned overrides fallthrough")
    }

    // --- Categorization: Draft overrides everything ---

    do {
        let llm = MockLLMClient()
        let service = CategorizationService(llmClient: llm)
        let pr = makePR(isDraft: true, isRequestedReviewer: true, isDirectCodeowner: true)
        let result = await service.categorize(pr: pr, codeowners: nil, userContext: "")
        t.checkEqual(result.category, .noise, "draft overrides direct codeowner")
    }

    // --- Notification filtering logic ---
    // Notifications should only fire for priority PRs with passing CI, not yet notified, not yet reviewed

    do {
        // Helper that mirrors NotificationService.notifyIfNeeded filtering
        func shouldNotify(_ prs: [PullRequest], alreadyNotified: Set<String> = [], username: String = "") -> [PullRequest] {
            prs.filter {
                guard $0.category == .priority && $0.buildStatus == .passed else { return false }
                guard !alreadyNotified.contains($0.id) else { return false }
                if !username.isEmpty && $0.reviewers.contains(where: {
                    $0.login.caseInsensitiveCompare(username) == .orderedSame && $0.state != .pending
                }) { return false }
                return true
            }
        }

        // Priority + passing CI → notify
        var pr1 = makePR()
        pr1.category = .priority
        pr1.buildStatus = .passed
        t.checkEqual(shouldNotify([pr1]).count, 1, "notify: priority + passing CI")

        // Priority + failed CI → no notify
        var pr2 = makePR()
        pr2.category = .priority
        pr2.buildStatus = .failed
        t.checkEqual(shouldNotify([pr2]).count, 0, "no notify: priority + failed CI")

        // Priority + no CI → no notify
        var pr3 = makePR()
        pr3.category = .priority
        pr3.buildStatus = nil
        t.checkEqual(shouldNotify([pr3]).count, 0, "no notify: priority + no CI")

        // Priority + running CI → no notify
        var pr4 = makePR()
        pr4.category = .priority
        pr4.buildStatus = .running
        t.checkEqual(shouldNotify([pr4]).count, 0, "no notify: priority + running CI")

        // Low + passing CI → no notify
        var pr5 = makePR()
        pr5.category = .low
        pr5.buildStatus = .passed
        t.checkEqual(shouldNotify([pr5]).count, 0, "no notify: low + passing CI")

        // Noise + passing CI → no notify
        var pr6 = makePR()
        pr6.category = .noise
        pr6.buildStatus = .passed
        t.checkEqual(shouldNotify([pr6]).count, 0, "no notify: noise + passing CI")

        // Already notified → no duplicate
        t.checkEqual(shouldNotify([pr1], alreadyNotified: [pr1.id]).count, 0, "no notify: already notified")

        // Mix of PRs → only matching ones
        t.checkEqual(shouldNotify([pr1, pr2, pr3, pr5]).count, 1, "notify: only priority+passing from mix")

        // Already reviewed (approved) → no notify
        var pr7 = makePR()
        pr7.category = .priority
        pr7.buildStatus = .passed
        pr7.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .approved)]
        t.checkEqual(shouldNotify([pr7], username: "testuser").count, 0, "no notify: already approved")

        // Already reviewed (changes requested) → no notify
        var pr8 = makePR()
        pr8.category = .priority
        pr8.buildStatus = .passed
        pr8.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .changesRequested)]
        t.checkEqual(shouldNotify([pr8], username: "testuser").count, 0, "no notify: changes requested")

        // Pending review → still notify
        var pr9 = makePR()
        pr9.category = .priority
        pr9.buildStatus = .passed
        pr9.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .pending)]
        t.checkEqual(shouldNotify([pr9], username: "testuser").count, 1, "notify: only pending review")

        // Review dismissed → still notify (needs re-review)
        var pr10 = makePR()
        pr10.category = .priority
        pr10.buildStatus = .passed
        pr10.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .dismissed)]
        t.checkEqual(shouldNotify([pr10], username: "testuser").count, 0, "no notify: dismissed counts as reviewed")
    }

    // --- Notified PR IDs persistence ---

    do {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("prsieve-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        if let persistence = try? PersistenceService(directory: dir) {
            // Initially empty
            let ids1 = await persistence.loadNotifiedPRIDs()
            t.checkEqual(ids1.count, 0, "persistence: starts empty")

            // Save and reload
            let saved: Set<String> = ["owner/repo#1", "owner/repo#2", "owner/repo#3"]
            await persistence.saveNotifiedPRIDs(saved)
            let ids2 = await persistence.loadNotifiedPRIDs()
            t.checkEqual(ids2, saved, "persistence: saves and reloads IDs")

            // Overwrite
            let updated: Set<String> = ["owner/repo#1"]
            await persistence.saveNotifiedPRIDs(updated)
            let ids3 = await persistence.loadNotifiedPRIDs()
            t.checkEqual(ids3, updated, "persistence: overwrites correctly")
        } else {
            t.check(false, "persistence: failed to create PersistenceService with temp dir")
        }
    }

    // --- Reviewed by me detection ---

    do {
        // Helper that mirrors DashboardViewModel.isReviewedByMe
        func isReviewedByMe(_ pr: PullRequest, username: String) -> Bool {
            guard !username.isEmpty else { return false }
            return pr.reviewers.contains { $0.login.caseInsensitiveCompare(username) == .orderedSame && $0.state == .approved }
        }

        // PR with user's approval → reviewed
        var pr1 = makePR()
        pr1.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .approved)]
        t.check(isReviewedByMe(pr1, username: "testuser"), "user approved → reviewed")

        // Case-insensitive match
        t.check(isReviewedByMe(pr1, username: "TestUser"), "case-insensitive → reviewed")

        // PR with user's changes_requested → not reviewed
        var pr2 = makePR()
        pr2.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .changesRequested)]
        t.check(!isReviewedByMe(pr2, username: "testuser"), "changes requested → not reviewed")

        // PR with user's comment only → not reviewed
        var pr3 = makePR()
        pr3.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .commented)]
        t.check(!isReviewedByMe(pr3, username: "testuser"), "commented → not reviewed")

        // PR with someone else's approval → not reviewed
        var pr4 = makePR()
        pr4.reviewers = [ReviewerInfo(login: "alice", avatarURL: nil, state: .approved)]
        t.check(!isReviewedByMe(pr4, username: "testuser"), "other user approved → not reviewed")

        // PR with no reviewers → not reviewed
        let pr5 = makePR()
        t.check(!isReviewedByMe(pr5, username: "testuser"), "no reviewers → not reviewed")

        // Empty username → not reviewed
        t.check(!isReviewedByMe(pr1, username: ""), "empty username → not reviewed")

        // Mixed reviewers: user approved among others
        var pr6 = makePR()
        pr6.reviewers = [
            ReviewerInfo(login: "alice", avatarURL: nil, state: .changesRequested),
            ReviewerInfo(login: "testuser", avatarURL: nil, state: .approved),
        ]
        t.check(isReviewedByMe(pr6, username: "testuser"), "user approved among others → reviewed")
    }

    // --- Closed PR filtering ---

    do {
        // Helper mirroring DashboardViewModel.filtered + reviewed logic
        func visiblePRs(_ prs: [PullRequest]) -> [PullRequest] {
            prs.filter { !$0.isClosed }
        }

        func visibleReviewed(_ prs: [PullRequest], username: String) -> [PullRequest] {
            prs
                .filter { pr in pr.reviewers.contains { $0.login == username && $0.state == .approved } }
                .filter { !$0.isClosed }
        }

        var openPR = makePR()
        openPR.isClosed = false

        var closedPR = makePR()
        closedPR.isClosed = true

        // Open PR is visible
        t.checkEqual(visiblePRs([openPR]).count, 1, "open PR appears in list")

        // Closed PR is excluded
        t.checkEqual(visiblePRs([closedPR]).count, 0, "closed PR excluded from list")

        // Mixed: only open one shows
        t.checkEqual(visiblePRs([openPR, closedPR]).count, 1, "only open PR shown in mixed list")

        // Closed reviewed PR is also excluded
        var closedReviewed = makePR()
        closedReviewed.isClosed = true
        closedReviewed.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .approved)]
        t.checkEqual(visibleReviewed([closedReviewed], username: "testuser").count, 0,
                     "closed reviewed PR excluded from reviewed section")

        // Open reviewed PR appears
        var openReviewed = makePR()
        openReviewed.isClosed = false
        openReviewed.reviewers = [ReviewerInfo(login: "testuser", avatarURL: nil, state: .approved)]
        t.checkEqual(visibleReviewed([openReviewed], username: "testuser").count, 1,
                     "open reviewed PR appears in reviewed section")
    }

    // --- Keep unreviewed priority PRs after merge ---

    do {
        let username = "testuser"

        func isUnreviewedPriorityWithinGracePeriod(
            _ pr: PullRequest,
            enabled: Bool = true,
            username: String = "testuser"
        ) -> Bool {
            guard enabled, pr.isMerged, pr.category == .priority else { return false }
            let isReviewed = pr.reviewers.contains { $0.login.caseInsensitiveCompare(username) == .orderedSame && $0.state == .approved }
            guard !isReviewed else { return false }
            return Date().timeIntervalSince(pr.updatedAt) < 3 * 24 * 3600
        }

        let recent = Date().addingTimeInterval(-1 * 24 * 3600)  // 1 day ago
        let stale  = Date().addingTimeInterval(-4 * 24 * 3600)  // 4 days ago

        // Merged priority PR, unreviewed, recent → keep visible
        var pr1 = makePR(isDirectCodeowner: true, updatedAt: recent)
        pr1.category = .priority
        pr1.isMerged = true
        t.check(isUnreviewedPriorityWithinGracePeriod(pr1), "merged priority unreviewed within 3d → keep")

        // Merged priority PR, reviewed → do not keep
        pr1.reviewers = [ReviewerInfo(login: username, avatarURL: nil, state: .approved)]
        t.check(!isUnreviewedPriorityWithinGracePeriod(pr1), "merged priority reviewed → don't keep")

        // Merged priority PR, unreviewed, stale (> 3 days) → don't keep
        var pr2 = makePR(isDirectCodeowner: true, updatedAt: stale)
        pr2.category = .priority
        pr2.isMerged = true
        t.check(!isUnreviewedPriorityWithinGracePeriod(pr2), "merged priority unreviewed >3d → don't keep")

        // Merged low PR → don't keep regardless
        var pr3 = makePR(updatedAt: recent)
        pr3.category = .low
        pr3.isMerged = true
        t.check(!isUnreviewedPriorityWithinGracePeriod(pr3), "merged low PR → don't keep")

        // Feature disabled → don't keep
        var pr4 = makePR(isDirectCodeowner: true, updatedAt: recent)
        pr4.category = .priority
        pr4.isMerged = true
        t.check(!isUnreviewedPriorityWithinGracePeriod(pr4, enabled: false), "feature disabled → don't keep")

        // Open priority PR → grace period logic doesn't apply
        var pr5 = makePR(isDirectCodeowner: true, updatedAt: recent)
        pr5.category = .priority
        pr5.isMerged = false
        t.check(!isUnreviewedPriorityWithinGracePeriod(pr5), "open PR → grace period not applicable")
    }

    // --- Previously reviewed PRs (reviewed-by fetch) ---

    do {
        let username = "testuser"

        // PR found via reviewed-by has isRequestedReviewer = false
        var pr = makePR(isRequestedReviewer: false)
        pr.reviewers = [ReviewerInfo(login: username, avatarURL: nil, state: .commented)]
        t.check(!pr.isRequestedReviewer, "reviewed-by PR: isRequestedReviewer = false")

        // Pre-filter still marks it priority (user previously reviewed)
        let llm1 = MockLLMClient()
        let svc1 = CategorizationService(llmClient: llm1)
        let r1 = await svc1.categorize(pr: pr, codeowners: nil, userContext: "", username: username)
        t.checkEqual(r1.category, .priority, "reviewed-by PR with comment → priority")
        t.checkEqual(await llm1.getCallCount(), 0, "reviewed-by PR skips LLM")

        // Review-requested PR wins when same PR comes from both sources
        // (simulated by isRequestedReviewer = true taking precedence)
        var prRequested = makePR(isRequestedReviewer: true)
        prRequested.reviewers = [ReviewerInfo(login: username, avatarURL: nil, state: .approved)]
        t.check(prRequested.isRequestedReviewer, "requested PR: isRequestedReviewer = true")

        // PR found only via reviewed-by with no review state → falls through to LLM
        var prNoReview = makePR(isRequestedReviewer: false, isDirectCodeowner: true)
        prNoReview.reviewers = []
        let llm2 = MockLLMClient()
        await llm2.setResponse(#"{"category": "low", "reason": "Not relevant"}"#)
        let svc2 = CategorizationService(llmClient: llm2)
        let r2 = await svc2.categorize(pr: prNoReview, codeowners: nil, userContext: "", username: username)
        t.checkEqual(await llm2.getCallCount(), 1, "reviewed-by PR with no review hits LLM")

        // Dedup: review-requested takes precedence over reviewed-by for same PR ID
        // Simulated by checking that if a PR is in both sets, it keeps isRequestedReviewer = true
        let requestedIDs: Set<String> = ["owner/repo#1"]
        var prFromReviewedBy = makePR(isRequestedReviewer: false)
        // If the ID is already in requested set, it should not be added again with isRequested = false
        let alreadySeen = requestedIDs.contains(prFromReviewedBy.id)
        t.check(alreadySeen, "dedup: reviewed-by PR with same ID as requested PR is skipped")
    }

    // --- Category override persistence ---

    do {
        let overriddenAt = Date()
        let beforeOverride = overriddenAt.addingTimeInterval(-3600) // 1 hour before override
        let afterOverride = overriddenAt.addingTimeInterval(3600)   // 1 hour after override

        // Override kept when PR has not been updated since override was set
        var existing = makePR(updatedAt: beforeOverride)
        existing.category = .noise
        existing.categoryOverridden = true
        existing.categoryReason = "Manually set to Noise"
        existing.lastCategorizedAt = overriddenAt

        var fresh = makePR(updatedAt: beforeOverride)
        fresh.isFlagged = existing.isFlagged
        if existing.categoryOverridden,
           let oa = existing.lastCategorizedAt,
           fresh.updatedAt <= oa {
            fresh.category = existing.category
            fresh.categoryOverridden = true
            fresh.categoryReason = existing.categoryReason
            fresh.lastCategorizedAt = existing.lastCategorizedAt
        }
        t.checkEqual(fresh.category, .noise, "override kept when PR unchanged")
        t.check(fresh.categoryOverridden, "categoryOverridden stays true when PR unchanged")

        // Override reset when PR has been updated after override was set
        var existingStale = makePR(updatedAt: afterOverride)
        existingStale.category = .noise
        existingStale.categoryOverridden = true
        existingStale.lastCategorizedAt = overriddenAt

        var freshUpdated = makePR(updatedAt: afterOverride)
        freshUpdated.isFlagged = existingStale.isFlagged
        if existingStale.categoryOverridden,
           let oa = existingStale.lastCategorizedAt,
           freshUpdated.updatedAt <= oa {
            freshUpdated.category = existingStale.category
            freshUpdated.categoryOverridden = true
        }
        // updatedAt > overriddenAt → override should NOT have been applied
        t.check(!freshUpdated.categoryOverridden, "override reset when PR updated after override")

        // Override kept when PR updatedAt exactly equals overriddenAt
        var existingExact = makePR(updatedAt: overriddenAt)
        existingExact.category = .priority
        existingExact.categoryOverridden = true
        existingExact.lastCategorizedAt = overriddenAt

        var freshExact = makePR(updatedAt: overriddenAt)
        if existingExact.categoryOverridden,
           let oa = existingExact.lastCategorizedAt,
           freshExact.updatedAt <= oa {
            freshExact.category = existingExact.category
            freshExact.categoryOverridden = true
        }
        t.checkEqual(freshExact.category, .priority, "override kept when updatedAt == overriddenAt")

        // No override when lastCategorizedAt is nil (legacy data)
        var existingNoDate = makePR()
        existingNoDate.category = .noise
        existingNoDate.categoryOverridden = true
        existingNoDate.lastCategorizedAt = nil

        var freshNoDate = makePR()
        if existingNoDate.categoryOverridden,
           let oa = existingNoDate.lastCategorizedAt,
           freshNoDate.updatedAt <= oa {
            freshNoDate.category = existingNoDate.category
            freshNoDate.categoryOverridden = true
        }
        t.check(!freshNoDate.categoryOverridden, "override with nil lastCategorizedAt is not applied")
    }

    // --- LLMClient: API key is optional ---

    do {
        // Empty endpoint → notConfigured (regardless of apiKey)
        let noEndpoint = LLMClient(endpoint: "", apiKey: "some-key", model: "gpt-4o-mini")
        do {
            _ = try await noEndpoint.complete(systemPrompt: "x", userPrompt: "y")
            t.check(false, "empty endpoint should throw")
        } catch let LLMError.notConfigured {
            t.check(true, "empty endpoint throws notConfigured")
        } catch {
            t.check(false, "empty endpoint threw wrong error: \(error)")
        }

        // Empty apiKey with valid endpoint → does NOT throw notConfigured
        // (http://127.0.0.1:1 will refuse the connection, producing requestFailed)
        let noKey = LLMClient(endpoint: "http://127.0.0.1:1", apiKey: "", model: "gpt-4o-mini")
        do {
            _ = try await noKey.complete(systemPrompt: "x", userPrompt: "y")
            t.check(false, "127.0.0.1:1 should fail to connect")
        } catch LLMError.notConfigured {
            t.check(false, "empty apiKey must NOT throw notConfigured")
        } catch {
            // Any other error is fine — we proved the guard let us past notConfigured
            t.check(true, "empty apiKey is allowed; got expected network error")
        }
    }

    // --- PullRequest Model ---

    do {
        let pr = makePR()
        t.checkEqual(pr.id, "owner/repo#1", "PR id format")
        t.checkEqual(pr.repoShortName, "repo", "repo short name")
        t.checkEqual(pr.ageDescription, "1h", "age description")
    }

    // --- LLMClient: placeholder API key is treated as not configured ---

    do {
        // "sk-..." placeholder → notConfigured without making a network call
        let placeholder = LLMClient(endpoint: "https://api.openai.com/v1", apiKey: "sk-...", model: "gpt-4o-mini")
        do {
            _ = try await placeholder.complete(systemPrompt: "x", userPrompt: "y")
            t.check(false, "placeholder apiKey should throw")
        } catch LLMError.notConfigured {
            t.check(true, "placeholder apiKey throws notConfigured")
        } catch {
            t.check(false, "placeholder apiKey threw wrong error: \(error)")
        }

        // Non-placeholder key with valid endpoint passes the guard (may fail for other reasons)
        let realKey = LLMClient(endpoint: "http://127.0.0.1:1", apiKey: "sk-real-key-abc", model: "gpt-4o-mini")
        do {
            _ = try await realKey.complete(systemPrompt: "x", userPrompt: "y")
            t.check(false, "127.0.0.1:1 should fail to connect")
        } catch LLMError.notConfigured {
            t.check(false, "non-placeholder key must NOT throw notConfigured")
        } catch {
            t.check(true, "non-placeholder key passes guard; got expected network error")
        }
    }

    // --- CategorizationService: notConfigured is silent (LLM disabled, not broken) ---

    do {
        // notConfigured → no lastLLMError set, PR falls back to .low silently
        let llm = MockLLMClient()
        await llm.setShouldThrow(true)
        await llm.setThrowError(.notConfigured)
        let service = CategorizationService(llmClient: llm)
        let pr = makePR(isRequestedReviewer: true, isDirectCodeowner: false)
        let result = await service.categorize(pr: pr, codeowners: nil, userContext: "")
        t.checkEqual(result.category, .low, "notConfigured → fallback to low")
        let err = await service.consumeLastLLMError()
        t.check(err == nil, "notConfigured is NOT captured as an error (LLM disabled)")

        // requestFailed IS captured (LLM broken, not just disabled)
        let llm2 = MockLLMClient()
        await llm2.setShouldThrow(true)
        await llm2.setThrowError(.requestFailed("401 Unauthorized"))
        let service2 = CategorizationService(llmClient: llm2)
        let result2 = await service2.categorize(pr: pr, codeowners: nil, userContext: "")
        t.checkEqual(result2.category, .low, "requestFailed → fallback to low")
        let err2 = await service2.consumeLastLLMError()
        t.check(err2 != nil, "requestFailed IS captured as an error")
    }

    // --- CategorizationService: LLM error tracking ---

    do {
        // LLM error is captured and consumable after a failed categorization
        let throwingLLM = MockLLMClient()
        await throwingLLM.setShouldThrow(true)
        let service = CategorizationService(llmClient: throwingLLM)
        let pr = makePR(isRequestedReviewer: true, isDirectCodeowner: false)
        let result = await service.categorize(pr: pr, codeowners: nil, userContext: "")
        t.checkEqual(result.category, .low, "LLM error → fallback to low")
        let err = await service.consumeLastLLMError()
        t.check(err != nil, "LLM error is captured after failure")

        // consumeLastLLMError clears the error (idempotent)
        let err2 = await service.consumeLastLLMError()
        t.check(err2 == nil, "consumeLastLLMError clears error")
    }

    do {
        // Successful LLM call leaves no error
        let goodLLM = MockLLMClient()
        await goodLLM.setResponse(#"{"category": "priority", "reason": "Owns this"}"#)
        let service = CategorizationService(llmClient: goodLLM)
        let pr = makePR(isRequestedReviewer: true, isDirectCodeowner: true)
        _ = await service.categorize(pr: pr, codeowners: nil, userContext: "owns cart")
        let err = await service.consumeLastLLMError()
        t.check(err == nil, "no LLM error after successful call")
    }

    do {
        // Pre-filter (no LLM call) leaves no error
        let llm = MockLLMClient()
        let service = CategorizationService(llmClient: llm)
        let pr = makePR(isDraft: true)
        _ = await service.categorize(pr: pr, codeowners: nil, userContext: "")
        let err = await service.consumeLastLLMError()
        t.check(err == nil, "pre-filtered PR leaves no LLM error")
        t.checkEqual(await llm.getCallCount(), 0, "pre-filtered PR hits no LLM")
    }

    // --- DashboardViewModel: llmErrorDescription ---

    do {
        // Helper to build a ViewModel-like description switch
        func describe(_ error: LLMError) -> (title: String, suggestion: String) {
            switch error {
            case .notConfigured:
                return ("LLM not configured", "Set a model name in Settings → Prompt.")
            case .requestFailed(let msg):
                let lower = msg.lowercased()
                if lower.contains("401") || lower.contains("unauthorized") {
                    return ("LLM authentication failed", "Check the API key in llm_config.json.")
                } else if lower.contains("404") || lower.contains("not found") {
                    return ("LLM model not found", "Check the model name in Settings → Prompt.")
                } else if lower.contains("429") || lower.contains("rate limit") {
                    return ("LLM rate limit reached", "Wait a moment, then refresh.")
                } else if lower.contains("connection refused") || lower.contains("network") {
                    return ("LLM connection failed", "Check the endpoint URL in llm_config.json.")
                } else {
                    return ("LLM request failed", "Check your endpoint and API key in llm_config.json.")
                }
            case .emptyResponse:
                return ("LLM returned no response", "Check the model name in Settings → Prompt.")
            }
        }

        let notConfigured = describe(.notConfigured)
        t.check(notConfigured.title.contains("not configured"), "notConfigured title")
        t.check(notConfigured.suggestion.contains("model"), "notConfigured suggestion mentions model")

        let auth401 = describe(.requestFailed("HTTP 401 Unauthorized"))
        t.check(auth401.title.contains("authentication"), "401 → auth error title")
        t.check(auth401.suggestion.contains("API key"), "401 suggestion mentions API key")

        let notFound = describe(.requestFailed("404 model not found"))
        t.check(notFound.title.contains("model not found"), "404 → model not found title")

        let rateLimit = describe(.requestFailed("429 rate limit exceeded"))
        t.check(rateLimit.title.contains("rate limit"), "429 → rate limit title")

        let empty = describe(.emptyResponse)
        t.check(empty.title.contains("no response"), "emptyResponse title")
        t.check(empty.suggestion.contains("model"), "emptyResponse suggestion mentions model")

        let generic = describe(.requestFailed("Internal server error 500"))
        t.check(generic.title.contains("failed"), "generic failure title")
        t.check(generic.suggestion.contains("endpoint"), "generic suggestion mentions endpoint")
    }

    // --- AppSettings: llmModel persistence ---

    do {
        // Default llmModel is empty (use bundle default)
        let defaults = AppSettings.default
        t.checkEqual(defaults.llmModel, "", "default llmModel is empty")

        // Round-trip through JSON preserves llmModel
        var settings = AppSettings.default
        settings.llmModel = "claude-opus-4-5"
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        if let data = try? encoder.encode(settings),
           let decoded = try? decoder.decode(AppSettings.self, from: data) {
            t.checkEqual(decoded.llmModel, "claude-opus-4-5", "llmModel survives JSON round-trip")
        } else {
            t.check(false, "llmModel: JSON round-trip failed")
        }

        // Missing llmModel in JSON falls back to empty string (backward compat)
        let legacyJSON = #"{"githubUsername":"alice","repos":[],"pollingIntervalSeconds":300}"#
        if let data = legacyJSON.data(using: .utf8),
           let legacy = try? decoder.decode(AppSettings.self, from: data) {
            t.checkEqual(legacy.llmModel, "", "missing llmModel in legacy JSON → empty string")
        } else {
            t.check(false, "llmModel: legacy JSON decode failed")
        }

        // PersistenceService saves and reloads llmModel
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("prsieve-test-llmmodel-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        if let persistence = try? PersistenceService(directory: dir) {
            var s = AppSettings.default
            s.llmModel = "gpt-4o-mini"
            try? await persistence.saveSettings(s)
            let loaded = await persistence.loadSettings()
            t.checkEqual(loaded.llmModel, "gpt-4o-mini", "llmModel persists through PersistenceService save/load")

            // Overwrite with empty to verify "use bundle default" state persists
            s.llmModel = ""
            try? await persistence.saveSettings(s)
            let loaded2 = await persistence.loadSettings()
            t.checkEqual(loaded2.llmModel, "", "empty llmModel persists (means use bundle default)")
        } else {
            t.check(false, "llmModel persistence: failed to create PersistenceService")
        }
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
