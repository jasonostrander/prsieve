import Foundation

actor CategorizationService {
    private let llmClient: LLMClient

    init(llmClient: LLMClient) {
        self.llmClient = llmClient
    }

    struct CategorizationResult: Sendable {
        let category: PRCategory
        let reason: String
    }

    /// Categorize a PR. Pre-filters obvious cases, sends the rest to the LLM.
    func categorize(
        pr: PullRequest,
        codeowners: String?,
        userContext: String
    ) async -> CategorizationResult {
        // Noise: draft PRs
        if pr.isDraft {
            return CategorizationResult(category: .noise, reason: "Draft PR")
        }

        // Noise: release PRs
        if isReleasePR(pr) {
            return CategorizationResult(category: .noise, reason: "Release PR")
        }

        // Noise: strings/translations PRs
        if isStringsPR(pr) {
            return CategorizationResult(category: .noise, reason: "Strings/translations PR")
        }

        // Pre-filter: mentioned in comments → always priority
        if pr.isMentioned {
            return CategorizationResult(category: .priority, reason: "You were @mentioned in comments")
        }

        // Everything else → LLM
        do {
            return try await llmCategorize(pr: pr, codeowners: codeowners, userContext: userContext)
        } catch {
            if pr.isRequestedReviewer {
                return CategorizationResult(category: .low, reason: "LLM unavailable — defaulting to low")
            }
            return CategorizationResult(category: .low, reason: "LLM unavailable")
        }
    }

    // MARK: - Pre-filter helpers

    private func isReleasePR(_ pr: PullRequest) -> Bool {
        let title = pr.title.lowercased()
        return title.hasPrefix("[releases]")
            || title.hasPrefix("[release]")
            || title.starts(with: "release ")
            || (pr.author.contains("machine-user") && title.contains("release"))
    }

    private func isStringsPR(_ pr: PullRequest) -> Bool {
        let title = pr.title.lowercased()
        if title.contains("strings") || title.contains("translations") || title.contains("l10n") {
            return true
        }
        // All files are string resources
        if !pr.filesChanged.isEmpty && pr.filesChanged.allSatisfy({ isStringFile($0) }) {
            return true
        }
        return false
    }

    private func isStringFile(_ path: String) -> Bool {
        let p = path.lowercased()
        return p.contains("/values") && p.hasSuffix("strings.xml")
            || p.hasSuffix(".strings")
            || p.hasSuffix(".stringsdict")
            || p.contains("translations/")
            || p.contains("locales/")
    }

    // MARK: - LLM categorization

    private func llmCategorize(
        pr: PullRequest,
        codeowners: String?,
        userContext: String
    ) async throws -> CategorizationResult {
        let systemPrompt = """
            You are a PR triage assistant. Categorize the PR into exactly one of two tiers:

            - "priority": The PR is directly relevant to the user — it touches code they own, \
            maintain, or have domain expertise in. The user should review this.
            - "low": The PR is not directly relevant. The user is likely assigned only through \
            fallthrough codeownership (catch-all patterns) or broad team ownership.

            Consider the PR age when categorizing. Older PRs (>7 days) are less likely to be priority \
            unless they are clearly in the user's domain.

            Respond with JSON only: {"category": "priority"|"low", "reason": "<one sentence>"}
            """

        let filesStr = pr.filesChanged.prefix(50).joined(separator: "\n  ")
        let codeownersStr = codeowners ?? "Not available"
        let ageStr = formatAge(pr.age)

        let userPrompt = """
            PR: \(pr.title)
            Repo: \(pr.repoFullName)
            Author: \(pr.author)
            Age: \(ageStr)
            User is requested reviewer: \(pr.isRequestedReviewer ? "yes" : "no")
            Description: \(String((pr.body ?? "").prefix(500)))
            Labels: \(pr.labels.joined(separator: ", "))
            Files changed:
              \(filesStr)

            CODEOWNERS file content:
            \(String(codeownersStr.prefix(3000)))

            User's ownership context:
            \(userContext)
            """

        let response = try await llmClient.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)

        // Parse JSON response
        if let parsed = parseResponse(response) {
            return parsed
        }

        // Try to extract JSON from markdown code block
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = parseResponse(cleaned) {
            return parsed
        }

        return CategorizationResult(category: .low, reason: "Could not parse LLM response")
    }

    private func parseResponse(_ text: String) -> CategorizationResult? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let categoryStr = json["category"],
              let reason = json["reason"],
              let category = PRCategory(rawValue: categoryStr) else {
            return nil
        }
        return CategorizationResult(category: category, reason: reason)
    }

    private func formatAge(_ age: TimeInterval) -> String {
        let hours = Int(age / 3600)
        if hours < 1 { return "less than 1 hour" }
        if hours < 24 { return "\(hours) hours" }
        let days = hours / 24
        if days == 1 { return "1 day" }
        return "\(days) days"
    }
}
