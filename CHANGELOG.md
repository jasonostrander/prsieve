# Changelog

All notable changes to PRSieve are recorded here. Each entry is a brief,
Claude-generated summary of the major changes in that release, produced by
`release.sh` (see `RELEASING.md`). The latest entry is also shown in the in-app
**Check for Updates…** dialog via the Sparkle appcast.

## 0.9.3 — 2026-05-27
- Better triage of PRs that mix code you own with code you don't (now judged file-by-file)

## 0.9.2 — 2026-05-21
- Added a "Test" button for the GitHub personal access token in Settings

## 0.9.1 — 2026-05-20
- Mark a PR as priority when you're the only assigned reviewer
- Added a prompt-test sheet for tuning your ownership context
- Added per-repo remove buttons in Settings
- A single misconfigured repo no longer blanks out the whole PR list

## 0.9.0 — 2026-05-13
- Initial release: menu bar PR triage with LLM categorization, CODEOWNERS awareness, CI status, and notifications
- Sparkle auto-updates (notarized zip), four-step onboarding, and launch-at-login
