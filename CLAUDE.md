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
    LLMSystemPrompt.swift       # LLM system prompt (edit to tune categorization behavior)
    CategorizationService.swift # Pre-filters + LLM triage
    CodeownersParser.swift      # Gitignore-style CODEOWNERS pattern matching
    NotificationService.swift   # macOS notifications via UNUserNotificationCenter
    PollingService.swift        # Orchestrates refresh: fetch -> categorize -> persist
    PersistenceService.swift    # JSON files in ~/Library/Application Support/PRSieve/
  ViewModels/
    DashboardViewModel.swift    # @Observable, drives the main view
    SettingsViewModel.swift     # Settings load/save
  Views/
    DashboardView.swift         # Full window PR list (toolbar, search, settings)
    MenuBarPRListView.swift     # Compact popover for menu bar (with collapsible search)
    PRListContent.swift         # Shared PR list body (used by both views)
    PRRowView.swift             # PR card with status pills and reviewer avatars
    SettingsView.swift          # GitHub, LLM, and preferences tabs
    CategoryHeaderView.swift    # Collapsible section headers with AI summaries
    DesignSystem.swift          # PRTheme colors (adaptive light/dark)
```

## Key Design Decisions

- **Menu bar app**: Runs as `LSUIElement` (no Dock icon). Left-click shows PR popover, right-click shows context menu (Refresh, Settings, Quit). Status bar icon turns orange when priority PRs with passing CI exist.
- **No Xcode**: Built entirely with SPM. `run.sh` creates a minimal .app bundle.
- **No Keychain**: Tokens stored in `~/.../PRSieve/.tokens.json` with 0600 permissions (unsigned app causes Keychain prompts).
- **Ad-hoc code signing**: `run.sh` runs `codesign --force --sign -` on the bundle so macOS grants notification permissions.
- **Pre-filters before LLM**: Applied in order before any LLM call:
  1. Draft PRs → noise
  2. Release PRs → noise
  3. Strings/l10n PRs → noise
  4. @mentioned in comments → priority
  5. User previously left a review (any non-pending state) → priority
  - Everything else goes to the LLM.
- **CODEOWNERS parsing**: Parses repo CODEOWNERS files with gitignore-style glob matching. `isDirectCodeowner` is set to true when the user owns specific (non-catch-all) patterns for the changed files. Passed to the LLM as context.
- **LLM prompt focuses on file paths**: System prompt in `LLMSystemPrompt.swift` tells the LLM to categorize based on changed file paths and the user's ownership context. Edit that file to tune behavior.
- **CI status via GitHub**: Uses the combined commit status API (`/commits/{sha}/status`). Status bar icon only highlights orange for priority PRs with passing CI.
- **Actor-based services**: GitHubClient, LLMClient, PersistenceService, PollingService are all actors for thread safety.
- **Bounded concurrency**: PR detail fetching and LLM categorization use TaskGroup with max 5 concurrent operations.
- **LLMProvider protocol**: Enables mock LLM in tests without network calls.
- **Tests without XCTest**: Uses a lightweight custom test runner compiled via `test.sh` (works with Command Line Tools only, no Xcode SDK needed).
- **Disappeared PR handling**: PRs that vanish from GitHub search results (e.g. review dismissed, team assignment) are re-fetched to check actual state before marking merged.

## Sections

The PR list has four sections:
- **Priority** — PRs matching your ownership context or pre-filter rules, with passing CI
- **Low** — Other review requests, LLM-determined not in your area
- **Noise** — Drafts, releases, strings PRs (auto-filtered, no LLM call)
- **Reviewed** — PRs you've already approved (collapsed by default)

Merged priority PRs remain visible for 3 days if you haven't reviewed them (configurable).

## Settings

Configured via the popover footer or right-click > Settings:
- **GitHub**: username, personal access token, repos (owner/repo format)
- **LLM**: OpenAI-compatible endpoint URL, API key, model name
- **Code ownership context**: Free-text description of what code you own (used in LLM prompt)
- **Polling interval**: 1-15 minutes
- **Hide draft PRs**: Toggle (default on)
- **Keep unreviewed priority PRs visible for 3 days after merge**: Toggle (default on)
- **Notify when priority PRs pass CI**: Toggle (default on)

## Notifications

- Sends macOS notifications for priority PRs when CI passes
- Skips PRs you've already reviewed (any non-pending review state)
- Notified PR IDs persisted to disk — no re-notification on app restart
- Clicking a notification opens the PR in the browser

## Testing

- **Always add tests** for new features and bug fixes.
- **Run `./test.sh`** after any code changes to verify nothing is broken.
- Tests use a lightweight custom runner (no XCTest/Xcode needed) in `Tests/PRSieveTests/PRSieveTests.swift`.
- Use `MockLLMClient` for testing LLM-dependent code paths.
- Test helpers `makePR(...)` and `makeReview(...)` simplify test data creation.
- `PersistenceService(directory:)` accepts a temp dir for isolated persistence tests.

## Data Storage

All in `~/Library/Application Support/PRSieve/`:
- `settings.json` — non-secret settings
- `.tokens.json` — GitHub token, LLM API key (0600 perms)
- `pull_requests.json` — cached PRs with categories
- `notified_pr_ids.json` — persisted set of already-notified PR IDs
- `codeowners_cache/` — per-repo CODEOWNERS files
