# PRSieve

macOS menu bar app for triaging GitHub PR review requests. Uses an LLM to categorize PRs by relevance so fallthrough codeowners can focus on what actually matters.

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

The app runs as a `.app` bundle created by `run.sh` (copies binary + Info.plist + AppIcon.icns into the bundle). Use `pkill -9 PRSieve` before relaunching if the old process is still running.

To regenerate the app icon: `swift resources/generate_icon.swift`

## Architecture

```
Sources/PRSieve/
  PRSieveApp.swift              # @main entry, AppDelegate, AppState service wiring
  StatusBarController.swift     # NSStatusItem + NSPopover, right-click context menu
  Models/
    PullRequest.swift           # Core PR model, ReviewerInfo, ReviewStatus
    Category.swift              # PRCategory: priority, low, noise
    AppSettings.swift           # User configuration
    BuildStatus.swift           # CI status enum (passed/failed/running/unknown)
  Services/
    GitHubClient.swift          # GitHub REST API (search, PR details, reviews, CODEOWNERS, combined CI status)
    LLMClient.swift             # OpenAI-compatible chat completions, LLMProvider protocol
    CategorizationService.swift # Pre-filters (draft/release/strings/mentioned) + LLM triage
    PollingService.swift        # Orchestrates refresh: fetch -> categorize -> persist
    PersistenceService.swift    # JSON files in ~/Library/Application Support/PRSieve/
  ViewModels/
    DashboardViewModel.swift    # @Observable, drives the main view
    SettingsViewModel.swift     # Settings load/save
  Views/
    DashboardView.swift         # Full window PR list (toolbar, search, settings)
    MenuBarPRListView.swift     # Compact popover for menu bar
    PRListContent.swift         # Shared PR list body (used by both views)
    PRRowView.swift             # PR card with status pills and reviewer avatars
    SettingsView.swift          # GitHub, LLM, and preferences tabs
    CategoryHeaderView.swift    # Collapsible section headers with AI summaries
    DesignSystem.swift          # PRTheme colors (adaptive light/dark)
```

## Key Design Decisions

- **Menu bar app**: Runs as `LSUIElement` (no Dock icon). Left-click shows PR popover, right-click shows context menu (Refresh, Settings, Quit). Status bar icon turns orange when priority PRs exist.
- **No Xcode**: Built entirely with SPM. `run.sh` creates a minimal .app bundle.
- **No Keychain**: Tokens stored in `~/.../PRSieve/.tokens.json` with 0600 permissions (unsigned app causes Keychain prompts).
- **Pre-filter before LLM**: Drafts, releases, strings/l10n PRs are categorized as "noise" without an LLM call. @mentioned PRs are auto-priority.
- **LLM prompt focuses on file paths**: The system prompt tells the LLM to categorize based on which files changed, not the PR title/description.
- **CI status via GitHub**: Uses the combined commit status API (`/commits/{sha}/status`) which aggregates all CI providers. No Buildkite-specific config needed.
- **Actor-based services**: GitHubClient, LLMClient, PersistenceService, PollingService are all actors for thread safety.
- **Bounded concurrency**: PR detail fetching and LLM categorization use TaskGroup with max 5 concurrent operations.
- **LLMProvider protocol**: Enables mock LLM in tests without network calls.
- **Tests without XCTest**: Uses a lightweight custom test runner compiled via `test.sh` (works with Command Line Tools only, no Xcode SDK needed).

## Settings

Configured via the popover footer or right-click > Settings:
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
