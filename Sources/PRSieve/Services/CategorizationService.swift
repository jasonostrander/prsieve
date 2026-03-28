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

    /// Categorize a PR. Uses pre-filtering for obvious cases, LLM for ambiguous ones.
    func categorize(
        pr: PullRequest,
        codeowners: String?,
        userContext: String
    ) async -> CategorizationResult {
        // Pre-filter: explicitly requested reviewer or mentioned → must-review
        if pr.isRequestedReviewer && pr.isMentioned {
            return CategorizationResult(
                category: .mustReview,
                reason: "You are a requested reviewer and were mentioned in comments"
            )
        }
        if pr.isMentioned {
            return CategorizationResult(
                category: .mustReview,
                reason: "You were mentioned in PR comments"
            )
        }

        // Pre-filter: draft PRs → fyi
        if pr.isDraft {
            return CategorizationResult(
                category: .fyi,
                reason: "Draft PR — no review needed yet"
            )
        }

        // If explicitly requested as reviewer (but not mentioned), still must-review
        if pr.isRequestedReviewer {
            return CategorizationResult(
                category: .mustReview,
                reason: "You are specifically requested as a reviewer"
            )
        }

        // LLM categorization for ambiguous cases
        do {
            return try await llmCategorize(pr: pr, codeowners: codeowners, userContext: userContext)
        } catch {
            // Fallback to fyi if LLM fails
            return CategorizationResult(
                category: .fyi,
                reason: "Auto-categorized (LLM unavailable): \(error.localizedDescription)"
            )
        }
    }

    private func llmCategorize(
        pr: PullRequest,
        codeowners: String?,
        userContext: String
    ) async throws -> CategorizationResult {
        let systemPrompt = """
            You are a PR triage assistant. Categorize the PR into exactly one tier:

            - "must-review": The user is a direct codeowner of files changed (not a fallthrough/catch-all owner like * @user).
            - "should-know": The PR touches code the user actively maintains or has domain expertise in, but they are not a direct codeowner.
            - "fyi": The PR is only relevant through fallthrough codeownership (catch-all patterns) or broad team ownership. Low urgency.

            Respond with JSON only: {"category": "must-review"|"should-know"|"fyi", "reason": "<one sentence>"}
            """

        let filesStr = pr.filesChanged.prefix(50).joined(separator: "\n  ")
        let codeownersStr = codeowners ?? "Not available"
        let userPrompt = """
            PR: \(pr.title)
            Repo: \(pr.repoFullName)
            Author: \(pr.author)
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
        if let jsonData = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
           let categoryStr = json["category"],
           let reason = json["reason"],
           let category = PRCategory(rawValue: categoryStr) {
            return CategorizationResult(category: category, reason: reason)
        }

        // Try to extract JSON from markdown code block
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonData = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
           let categoryStr = json["category"],
           let reason = json["reason"],
           let category = PRCategory(rawValue: categoryStr) {
            return CategorizationResult(category: category, reason: reason)
        }

        return CategorizationResult(category: .fyi, reason: "Could not parse LLM response")
    }
}
