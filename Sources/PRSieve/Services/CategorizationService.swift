import Foundation

actor CategorizationService {
    private let llmClient: any LLMProvider

    init(llmClient: any LLMProvider) {
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
        if Self.isReleasePR(pr) {
            return CategorizationResult(category: .noise, reason: "Release PR")
        }

        // Noise: strings/translations PRs
        if Self.isStringsPR(pr) {
            return CategorizationResult(category: .noise, reason: "Strings/translations PR")
        }

        // Pre-filter: mentioned in comments → always priority
        if pr.isMentioned {
            return CategorizationResult(category: .priority, reason: "You were @mentioned in comments")
        }

        // Pre-filter: requested reviewer but only via catch-all/fallthrough CODEOWNERS → low
        if pr.isRequestedReviewer && !pr.isDirectCodeowner {
            return CategorizationResult(category: .low, reason: "Fallthrough codeowner (not a direct owner of changed files)")
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

    static func isReleasePR(_ pr: PullRequest) -> Bool {
        let title = pr.title.lowercased()
        return title.hasPrefix("[releases]")
            || title.hasPrefix("[release]")
            || title.starts(with: "release ")
            || (pr.author.contains("machine-user") && title.contains("release"))
    }

    static func isStringsPR(_ pr: PullRequest) -> Bool {
        let title = pr.title.lowercased()
        if title.contains("strings") || title.contains("translations") || title.contains("l10n") {
            return true
        }
        // All files are string resources
        if !pr.filesChanged.isEmpty && pr.filesChanged.allSatisfy({ Self.isStringFile($0) }) {
            return true
        }
        return false
    }

    static func isStringFile(_ path: String) -> Bool {
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

            - "priority": The changed files are in code the user ACTUALLY owns, maintains, or has \
            domain expertise in, as described in their ownership context.
            - "low": The changed files are NOT in the user's area of actual ownership or interest.

            IMPORTANT RULES (in priority order):
            1. The user's ownership context is the HIGHEST priority signal. It describes what they \
            actually care about, including any exclusions or narrowing of broad CODEOWNERS rules. \
            If the user says they only care about a subset of a directory, respect that.
            2. Focus on FILE PATHS changed, not the PR title or description.
            3. The CODEOWNERS file shows formal ownership but may be overly broad. A user listed \
            on a broad directory pattern may not actually need to review all changes there. \
            Always defer to the user's ownership context over CODEOWNERS.

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
