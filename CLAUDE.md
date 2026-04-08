# PRSieve

macOS native app for triaging GitHub PR review requests. Uses an LLM to categorize PRs by relevance so fallthrough codeowners can focus on what actually matters.

## Tech Stack

- Swift 6 / SwiftUI, macOS 14+
- Swift Package Manager (no Xcode required)
- Zero external dependencies
- OpenAI-compatible API for LLM categorization

## Build & Run

```bash
./run.sh          # builds, bundles .app, and launches
swift build       # build only
./test.sh         # compile and run tests (no Xcode/XCTest needed)
```

The app runs as a `.app` bundle created by `run.sh` (copies binary + Info.plist into `Contents/MacOS/`). Use `pkill -9 PRSieve` before relaunching if the old process is still running.

## Architecture

```
Sources/PRSieve/
  PRSieveApp.swift              # @main entry, AppState service wiring
  Models/
    PullRequest.swift           # Core PR model, ReviewerInfo, ReviewStatus
    Category.swift              # PRCategory: priority, low, noise
    AppSettings.swift           # User configuration
    BuildStatus.swift           # CI status enum (not currently wired)
  Services/
    GitHubClient.swift          # GitHub REST API (search, PR details, reviews, CODEOWNERS)
    LLMClient.swift             # OpenAI-compatible chat completions, LLMProvider protocol
    CategorizationService.swift # Pre-filters (draft/release/strings/mentioned) + LLM triage
    PollingService.swift        # Orchestrates refresh: fetch -> categorize -> persist
    PersistenceService.swift    # JSON files in ~/Library/Application Support/PRSieve/
  ViewModels/
    DashboardViewModel.swift    # @Observable, drives the main view
    SettingsViewModel.swift     # Settings load/save
  Views/
    DashboardView.swift         # Main PR list grouped by category
    PRRowView.swift             # PR card with reviewer avatars
    SettingsView.swift          # GitHub, LLM, and preferences tabs
    CategoryHeaderView.swift    # Section headers
    DesignSystem.swift          # PRTheme colors (adaptive light/dark)
```

## Key Design Decisions

- **No Xcode**: Built entirely with SPM. `run.sh` creates a minimal .app bundle for Dock/window behavior.
- **No Keychain**: Tokens stored in `~/.../PRSieve/.tokens.json` with 0600 permissions (unsigned app causes Keychain prompts).
- **Pre-filter before LLM**: Drafts, releases, strings/l10n PRs are categorized as "noise" without an LLM call. @mentioned PRs are auto-priority.
- **LLM prompt focuses on file paths**: The system prompt tells the LLM to categorize based on which files changed, not the PR title/description.
- **Actor-based services**: GitHubClient, LLMClient, PersistenceService, PollingService are all actors for thread safety.
- **LLMProvider protocol**: Enables mock LLM in tests without network calls.
- **Tests without XCTest**: Uses a lightweight custom test runner compiled via `test.sh` (works with Command Line Tools only, no Xcode SDK needed).

## Settings

Configured in-app (gear icon or Cmd+,):
- **GitHub**: username, personal access token, repos (owner/repo format)
- **LLM**: OpenAI-compatible endpoint URL, API key, model name
- **Code ownership context**: Free-text description of what code you own (used in LLM prompt)
- **Polling interval**: 1-15 minutes

## Testing

- **Always add tests** for new features and bug fixes.
- **Run `./test.sh`** after any code changes to verify nothing is broken.
- Tests use a lightweight custom runner (no XCTest/Xcode needed) in `Tests/PRSieveTests/PRSieveTests.swift`.
- Use `MockLLMClient` for testing LLM-dependent code paths.
- Test helpers `makePR` and `makeReview` simplify test data creation.

## Data Storage

All in `~/Library/Application Support/PRSieve/`:
- `settings.json` — non-secret settings
- `.tokens.json` — GitHub token, LLM API key (0600 perms)
- `pull_requests.json` — cached PRs with categories
- `codeowners_cache/` — per-repo CODEOWNERS files
