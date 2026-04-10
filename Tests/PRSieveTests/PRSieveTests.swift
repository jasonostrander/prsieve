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
    isRequestedReviewer: Bool = true,
    isDirectCodeowner: Bool = false
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

    // --- AppSettings: hideDraftPRs ---

    do {
        let defaults = AppSettings.default
        t.checkEqual(defaults.hideDraftPRs, true, "hideDraftPRs defaults to true")
    }

    do {
        let json = #"{"githubUsername":"","repos":[],"buildkiteOrgSlug":"","llmEndpoint":"","llmModel":"gpt-4o-mini","codeownerContext":"","pollingIntervalSeconds":300,"notificationsEnabled":true}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        t.checkEqual(decoded.hideDraftPRs, true, "hideDraftPRs defaults when missing from JSON")
    }

    do {
        let json = #"{"githubUsername":"","repos":[],"buildkiteOrgSlug":"","llmEndpoint":"","llmModel":"gpt-4o-mini","codeownerContext":"","pollingIntervalSeconds":300,"hideDraftPRs":false,"notificationsEnabled":true}"#
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: json.data(using: .utf8)!)
        t.checkEqual(decoded.hideDraftPRs, false, "hideDraftPRs can be set to false")
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
            * @fallback-team @jasonostrander
            /src/cart/ @jasonostrander
            /src/auth/ @alice
            """
        let parser = CodeownersParser(content: content)

        // User owns src/cart/ directly
        t.check(
            parser.isDirectOwner(username: "jasonostrander", files: ["src/cart/Cart.swift"]),
            "direct owner of cart file"
        )

        // User is in catch-all but NOT direct owner of auth files
        t.check(
            !parser.isDirectOwner(username: "jasonostrander", files: ["src/auth/Login.swift"]),
            "not direct owner of auth file (only catch-all)"
        )

        // Mixed: one file is direct, one is catch-all → still direct owner
        t.check(
            parser.isDirectOwner(username: "jasonostrander", files: ["src/auth/Login.swift", "src/cart/Cart.swift"]),
            "direct owner when at least one file matches"
        )

        // Files only matching catch-all
        t.check(
            !parser.isDirectOwner(username: "jasonostrander", files: ["README.md", "docs/setup.md"]),
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
        let content = "/src/ @JasonOstrander"
        let parser = CodeownersParser(content: content)
        t.check(
            parser.isDirectOwner(username: "jasonostrander", files: ["src/file.swift"]),
            "case-insensitive owner match"
        )
    }

    // --- CodeownersParser: No CODEOWNERS file ---

    do {
        let parser = CodeownersParser(content: "")
        t.check(!parser.isDirectOwner(username: "anyone", files: ["file.txt"]), "empty CODEOWNERS → not direct owner")
    }

    // --- Categorization: Fallthrough codeowner → low ---

    do {
        let llm = MockLLMClient()
        let service = CategorizationService(llmClient: llm)
        // isRequestedReviewer but NOT isDirectCodeowner
        let pr = makePR(isRequestedReviewer: true, isDirectCodeowner: false)
        let result = await service.categorize(pr: pr, codeowners: nil, userContext: "")
        t.checkEqual(result.category, .low, "fallthrough codeowner → low")
        t.check(result.reason.contains("Fallthrough"), "fallthrough reason")
        let calls = await llm.getCallCount()
        t.checkEqual(calls, 0, "fallthrough skips LLM")
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
    // Notifications should only fire for priority PRs with passing CI

    do {
        // Helper that mirrors NotificationService.notifyIfNeeded filtering
        func shouldNotify(_ prs: [PullRequest], alreadyNotified: Set<String> = []) -> [PullRequest] {
            prs.filter { $0.category == .priority && $0.buildStatus == .passed && !alreadyNotified.contains($0.id) }
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
        pr1.reviewers = [ReviewerInfo(login: "jasonostrander", avatarURL: nil, state: .approved)]
        t.check(isReviewedByMe(pr1, username: "jasonostrander"), "user approved → reviewed")

        // Case-insensitive match
        t.check(isReviewedByMe(pr1, username: "JasonOstrander"), "case-insensitive → reviewed")

        // PR with user's changes_requested → not reviewed
        var pr2 = makePR()
        pr2.reviewers = [ReviewerInfo(login: "jasonostrander", avatarURL: nil, state: .changesRequested)]
        t.check(!isReviewedByMe(pr2, username: "jasonostrander"), "changes requested → not reviewed")

        // PR with user's comment only → not reviewed
        var pr3 = makePR()
        pr3.reviewers = [ReviewerInfo(login: "jasonostrander", avatarURL: nil, state: .commented)]
        t.check(!isReviewedByMe(pr3, username: "jasonostrander"), "commented → not reviewed")

        // PR with someone else's approval → not reviewed
        var pr4 = makePR()
        pr4.reviewers = [ReviewerInfo(login: "alice", avatarURL: nil, state: .approved)]
        t.check(!isReviewedByMe(pr4, username: "jasonostrander"), "other user approved → not reviewed")

        // PR with no reviewers → not reviewed
        let pr5 = makePR()
        t.check(!isReviewedByMe(pr5, username: "jasonostrander"), "no reviewers → not reviewed")

        // Empty username → not reviewed
        t.check(!isReviewedByMe(pr1, username: ""), "empty username → not reviewed")

        // Mixed reviewers: user approved among others
        var pr6 = makePR()
        pr6.reviewers = [
            ReviewerInfo(login: "alice", avatarURL: nil, state: .changesRequested),
            ReviewerInfo(login: "jasonostrander", avatarURL: nil, state: .approved),
        ]
        t.check(isReviewedByMe(pr6, username: "jasonostrander"), "user approved among others → reviewed")
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
        closedReviewed.reviewers = [ReviewerInfo(login: "jasonostrander", avatarURL: nil, state: .approved)]
        t.checkEqual(visibleReviewed([closedReviewed], username: "jasonostrander").count, 0,
                     "closed reviewed PR excluded from reviewed section")

        // Open reviewed PR appears
        var openReviewed = makePR()
        openReviewed.isClosed = false
        openReviewed.reviewers = [ReviewerInfo(login: "jasonostrander", avatarURL: nil, state: .approved)]
        t.checkEqual(visibleReviewed([openReviewed], username: "jasonostrander").count, 1,
                     "open reviewed PR appears in reviewed section")
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
