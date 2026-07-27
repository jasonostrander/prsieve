# PR Readiness

PRSieve's green status means **ready for review**, not merely "CI passed."
It answers a deliberately narrow question:

> Can this pull request be merged after one qualifying approval, with no other
> known action required?

Categorization and readiness are independent. Categorization decides whether a
PR belongs in Priority, Low, Noise, or Reviewed. Readiness decides whether a PR
currently needs only its required review.

## Ready predicate

A PR is ready for review only when all of the following are true:

- The PR is open and is not a draft.
- The GraphQL result describes the expected HEAD commit.
- GitHub reports the PR as structurally mergeable.
- Merge state is known and has no conflict or other structural blocker.
- The branch is not behind when active rules require strict status checks.
- Every GitHub-required status context and check run has passed.
- Every required context declared by the Rules API is present in the GraphQL
  rollup.
- Active branch rules were successfully evaluated, contain no unsupported
  blocking rule, and no changed file matches an active file-path restriction.
- `reviewDecision` is `REVIEW_REQUIRED`.

The evaluator persists a `PRReadiness` value with a diagnostic outcome and
blocker. `PullRequest.isReadyForReview` reads that stored result and is true
only when the persisted blocker is `nil`; UI consumers do not independently
reconstruct the predicate.

`APPROVED`, `CHANGES_REQUESTED`, and a missing review decision are not ready:
the feature specifically represents PRs for which approval is still the only
remaining merge requirement. CODEOWNERS parsing is not part of this
calculation. GitHub's `reviewDecision` already incorporates required approval
and CODEOWNERS-review policy.

## Required checks

The latest commit's complete `statusCheckRollup.contexts` connection is
paginated in batches of 100. Both legacy `StatusContext` entries and modern
`CheckRun` entries participate, but only when GraphQL reports
`isRequired(pullRequestNumber:) == true`.

Required-check aggregation uses failure-first precedence:

1. Any failed required context makes the aggregate failed.
2. Otherwise, a missing or running required context makes it running.
3. Otherwise, any unrecognized required state makes it unknown.
4. Otherwise, the aggregate passes.

For completed check runs, `SUCCESS`, `NEUTRAL`, and `SKIPPED` count as passing.
Failures, timeouts, cancellations, action-required, startup failures, and stale
runs count as failed.

Optional checks do not affect readiness. In particular, `danger/danger` needs
no special-case ignore setting: if a repository does not require it, a Danger
failure is irrelevant to the ready predicate. The former ignored-CI-check list
and Buildkite-specific client/settings were removed.

The active Rules API response supplies the expected required context names.
This catches a required check that has not created a rollup entry yet. A
same-named optional context cannot satisfy that requirement because only
GraphQL contexts marked required enter the present-name set.

## GitHub API inputs

Each readiness refresh combines:

| Input | API |
| --- | --- |
| PR state, draft state, base branch, HEAD OID | GraphQL `PullRequest` |
| Mergeability and detailed merge state | GraphQL `PullRequest` |
| Review decision | GraphQL `PullRequest.reviewDecision` |
| Required legacy statuses and check runs | GraphQL `statusCheckRollup` |
| Required context names, strictness, and path restrictions | REST Rules API |
| Changed file paths | Existing REST PR-detail fetch |

GraphQL partial errors are treated as failures rather than accepting incomplete
data. The configured GitHub token must be able to read the PR, its check
rollup, and the repository's active branch rules. If the Rules API is denied or
unavailable, readiness becomes unknown rather than silently assuming no rules.

Rules are cached for one hour per repository and base branch. Check and merge
state are not treated as settled: they can change without advancing the PR's
`updatedAt`, so every poll refreshes readiness even when PR details are reused.

## Fail-closed behavior

PRSieve never labels or notifies a PR as ready from incomplete state.

- A HEAD mismatch, GraphQL error, Rules API error, unknown check state, or
  unsupported blocking rule produces an unknown readiness result.
- Unknown GitHub merge state is retried up to three times with a 500 ms delay.
- A missing expected required context remains running/missing rather than
  passing.
- `UNSTABLE` alone does not block: it can be caused by a failing optional check,
  so explicit required-check and rule inputs remain authoritative.
- `BEHIND` blocks only when the active required-status-check rule is strict.

## Polling and notifications

New or changed PRs receive the normal REST detail fetch and a readiness
evaluation. Unchanged PRs reuse stored details but still refresh readiness
against the stored HEAD SHA.

`readinessNotificationBaseline` persists the last definitive ready/not-ready
state:

- A new priority PR that is already ready may notify immediately.
- A not-ready to ready transition notifies.
- An unknown refresh preserves the previous definitive baseline and never
  notifies.
- Legacy cached PRs establish their initial baseline silently after upgrade, so
  installing the new version does not generate a notification storm.

Notifications are still limited to priority PRs and are skipped after the user
has submitted any non-pending review.
