# PRSieve

macOS menu bar app for triaging GitHub PR review requests. Uses an LLM to categorize PRs by relevance so fallthrough codeowners can focus on what actually matters.

## Tech Stack

- Swift 6 / SwiftUI, macOS 14+
- Swift Package Manager (no Xcode required)
- One external dependency: [Sparkle](https://sparkle-project.org) for auto-updates
- OpenAI-compatible API for LLM categorization

## Build & Run

First-time setup: copy `llm_config.example.json` to `llm_config.json` and fill in the endpoint/token/model. The file is gitignored. `run.sh`/`release.sh` will warn and fall back to the example if it's missing (LLM will be disabled until token is set).

```bash
cp llm_config.example.json llm_config.json   # one-time, then edit
./run.sh          # builds, bundles .app, and launches
swift build       # build only
./test.sh         # compile and run tests (no Xcode/XCTest needed)
./release.sh 1.2.3            # builds, notarizes, tags, pushes, creates GitHub Release
./release.sh 1.2.3 --no-publish  # local build + notarize, no git/GH side effects
```

The app runs as a `.app` bundle created by `run.sh` (copies binary + Info.plist + AppIcon.icns + Sparkle.framework + a binary-plist `llm_config.plist` derived from `llm_config.json` into the bundle). Use `pkill -9 PRSieve` before relaunching if the old process is still running. `run.sh` strips Sparkle's `SUFeedURL`/`SUPublicEDKey` keys for dev builds so the local copy never tries to auto-update.

`release.sh` produces a Developer ID-signed and notarized **zip** (`dist/PRSieve.zip`), EdDSA-signs it for Sparkle, prepends a Claude-generated entry to `CHANGELOG.md`, regenerates `appcast.xml` (with those bullets as `<description>` release notes), and (unless `--no-publish`) tags + pushes + creates a GitHub Release. Signing identity SHA-1 is hardcoded to `Developer ID Application: Jason Ostrander (TCL5ZG7A2L)`; notarization uses the `PRSieve-notarize` keychain profile. The bundled config is converted to **binary plist** at build time so corporate DLP (CrowdStrike) doesn't strip it — plain JSON files get filtered. **Why zip and not DMG**: Apple's notary service silently rejects DMG-packaged bundles containing `Sparkle.framework` (`signature of the binary is invalid` on the main Mach-Os) even when the bytes are identical to a notarization-Accepted zip of the same `.app`. See `RELEASING.md` for the full investigation and Sparkle key-management instructions.

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
    LLMConfig.swift             # Loads endpoint/token/model from bundled llm_config.plist
    LLMSystemPrompt.swift       # LLM system prompt (edit to tune categorization behavior)
    CategorizationService.swift # Pre-filters + LLM triage
    CodeownersParser.swift      # Gitignore-style CODEOWNERS pattern matching
    NotificationService.swift   # macOS notifications via UNUserNotificationCenter
    PollingService.swift        # Orchestrates refresh: fetch -> categorize -> persist
    PersistenceService.swift    # JSON files in ~/Library/Application Support/PRSieve/
    UpdaterService.swift        # UpdaterServicing protocol (Sparkle-free, so tests compile)
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

- **Menu bar app**: Runs as `LSUIElement` (no Dock icon). Left-click shows PR popover, right-click shows context menu (Refresh, Check for Updates…, Settings, Quit). Status bar icon turns orange when priority PRs with passing CI exist.
- **No Xcode**: Built entirely with SPM. `run.sh` creates a minimal .app bundle.
- **No Keychain**: Tokens stored in `~/.../PRSieve/.tokens.json` with 0600 permissions (unsigned app causes Keychain prompts).
- **LLM credentials baked into the bundle**: Endpoint, token, and model live in `llm_config.json` at the project root (gitignored). `run.sh`/`release.sh` convert it to a **binary plist** (`Contents/Resources/llm_config.plist`) and `LLMConfig.loadFromBundle()` reads it via `Bundle.main`. Use `llm_config.example.json` as the template. Users only configure the prompt (ownership context) via Settings. JSON-key is `token` (not `apiKey`) so corporate DLP doesn't recognize the file as credentials; binary plist further hides it from text-based scanners.
- **Code signing**: `run.sh` ad-hoc signs (`--sign -`) for local dev. `release.sh` signs with Developer ID + hardened runtime + secure timestamp, then submits to Apple's notary service via `notarytool` (using the `PRSieve-notarize` keychain profile) and staples the ticket. The signing identity SHA-1 hash is hardcoded in `release.sh` to disambiguate when multiple Developer ID certs are installed.
- **Auto-updates via Sparkle**: `SparkleUpdater` (in `PRSieveApp.swift`) wraps `SPUStandardUpdaterController` behind the `UpdaterServicing` protocol from `UpdaterService.swift`. The protocol lets the test build (which excludes `PRSieveApp.swift`) compile without linking Sparkle. `release.sh` EdDSA-signs the release zip; the public key (`SUPublicEDKey`) is baked into `resources/Info.plist`; the private key lives in the macOS Keychain (service `https://sparkle-project.org`, account `ed25519`) with a backup at `sparkle_private_key.txt` (gitignored). Appcast is served from `raw.githubusercontent.com/jasonostrander/prsieve/main/appcast.xml`. End-to-end test: `./scripts/test_sparkle.sh` (builds two notarized zips, installs the older one, serves the newer via localhost, waits for manual "Check for Updates…" click).
- **Agent-generated changelog**: `CHANGELOG.md` (newest first) is the source of truth for release notes. `release.sh` calls `scripts/generate_changelog.sh`, which feeds the commit subjects since the previous tag to the `claude` CLI and gets back ≤4 brief, user-facing bullets (falls back to cleaned commit subjects if `claude` is missing/errors). Those bullets are prepended to `CHANGELOG.md`, embedded in the appcast item as HTML `<description>` release notes (shown by Sparkle's updater), and used as the GitHub Release body. Generation happens *before* the build so a bad summary or abort costs nothing; press `e` at the prompt to edit, or set `CHANGELOG_NOTES` to bypass the agent. Tune wording via the prompt in `scripts/generate_changelog.sh`.
- **Pre-filters before LLM**: Applied in order before any LLM call:
  1. Draft PRs → noise
  2. Release PRs → noise
  3. Strings/l10n PRs → noise
  4. @mentioned in comments → priority
  5. User previously left a review (any non-pending state) → priority
  6. User is the sole non-agent reviewer assigned → priority (`isBot` covers app-style agents like `olive-agent[bot]`; `agentReviewerTeams` in `GitHubClient` covers rotation-bot teams like `icapp-android-secondary-rotation`)
  - Everything else goes to the LLM.
- **CODEOWNERS parsing**: Parses repo CODEOWNERS files with gitignore-style glob matching. `isDirectCodeowner` is set to true when the user owns specific (non-catch-all) patterns for the changed files. Passed to the LLM as context.
- **LLM prompt focuses on file paths**: System prompt in `LLMSystemPrompt.swift` tells the LLM to categorize based on changed file paths and the user's ownership context. Edit that file to tune behavior.
- **CI status via GitHub**: Uses the combined commit status API (`/commits/{sha}/status`). Status bar icon only highlights orange for priority PRs with passing CI.
- **Actor-based services**: GitHubClient, LLMClient, PersistenceService, PollingService are all actors for thread safety.
- **Bounded concurrency**: PR detail fetching and LLM categorization use TaskGroup with max 5 concurrent operations.
- **Categorization caching**: A PR keeps its stored category (skipping re-categorization and the LLM call it implies) when it hasn't changed since it was last categorized — `pr.updatedAt <= lastCategorizedAt` — *and* the non-`updatedAt` inputs are unchanged. Those inputs (system prompt, ownership context, username, codeowner/reviewer flags) are captured in `PullRequest.categorizationContextHash`, a stable FNV-1a fingerprint (`PollingService.categorizationFingerprint`). `PollingService.canReuseCategorization` is the reuse gate. Editing the ownership prompt, shipping a new `llmSystemPrompt`, or a CODEOWNERS change all flip the fingerprint and force a one-time recompute; legacy PRs with a nil hash also recompute once.
- **Selective detail fetching (sync speed)**: The expensive part of a refresh is the per-PR detail fan-out — `GitHubClient.fetchPRDetail` makes ~7 REST calls (detail, files, reviews, review comments, issue comments, timeline, combined status). To avoid paying that for unchanged PRs, polling first does the cheap search (`fetchReviewRequestItems` / `fetchReviewedItems`, which already return each PR's `updatedAt`) and diffs against the stored PR via `PollingService.fetchPlan`: `.reuse` (0 calls) when `updatedAt` hasn't advanced and CI is already `.passed`; `.reuseRefreshingStatus` (1 call) when unchanged but CI is not yet passed; `.fullFetch` (7 calls) when new, changed, or a legacy PR without a stored `headSHA`. **Key caveat**: CI/commit status does *not* bump a PR's `updatedAt` (it attaches to the commit SHA), so `needsStatusRefresh` refreshes just `/commits/{sha}/status` for any non-passed PR — which is why `PullRequest.headSHA` is persisted. Only `.passed` counts as settled: a `.failed`/`.running` build can flip to passed via a CI re-run on the same commit with no `updatedAt` change, and catching that "went green" event drives the priority highlight + notifications. Reused PRs are run through `reusableCopy` (categorization-decision fields reset) so the override/cache gate re-derives the verdict uniformly: a settings/prompt change still triggers an LLM re-eval without re-fetching from GitHub. GraphQL (single-request fan-out) is the next step under evaluation if more speed is needed.
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
- **Prompt**: Free-text description of what code you own (used in LLM prompt)
- **Polling interval**: 15 minutes, 30 minutes (default), 1 hour, or 2 hours
- **Hide draft PRs**: Toggle (default on)
- **Keep unreviewed priority PRs visible for 3 days after merge**: Toggle (default on)
- **Notify when priority PRs pass CI**: Toggle (default on)
- **Automatically check for updates**: Toggle (default on; Sparkle polls the appcast daily) + manual "Check for Updates Now" button

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
- `.tokens.json` — GitHub token (0600 perms)
- `pull_requests.json` — cached PRs with categories
- `notified_pr_ids.json` — persisted set of already-notified PR IDs
- `codeowners_cache/` — per-repo CODEOWNERS files

LLM credentials are *not* stored here — they come from the bundled `llm_config.plist` (see "LLM credentials baked into the bundle" above).
