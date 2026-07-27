# Fix PR Status: Required Checks and Review Readiness

> **Implemented.** This document preserves the approved implementation plan.
> See [`PR_READINESS.md`](PR_READINESS.md) for the current operational behavior.

## Goal

Replace PRSieve's current legacy combined-status calculation with a reliable
answer to two separate questions:

1. Are all GitHub-required checks passing?
2. Is the PR otherwise ready to merge, with a qualifying approval as the only
   remaining action?

The existing `buildStatus == .passed` value is overloaded across the UI,
filtering, menu-bar indicator, and notifications. The new design separates
required-check state from review readiness so each signal remains accurate.

## Definitions

### Required checks status

```swift
enum RequiredChecksStatus {
    case passed
    case failed
    case running
    case unknown
}
```

Only GitHub check contexts for which GraphQL returns
`isRequired(pullRequestNumber:) == true` participate. Optional checks,
including `danger/danger`, have no effect.

GitHub exposes `isRequired` on both `StatusContext` and `CheckRun`, allowing
PRSieve to cover legacy commit statuses and GitHub Checks without maintaining
an ignored-check list.

### Ready for review

`isReadyForReview` means the PR is open, structurally mergeable, all required
checks are passing, and a qualifying approval is the only remaining normal
merge requirement.

The pure evaluator computes readiness once from:

```swift
ready =
    state == .open &&
    !isDraft &&
    mergeable == .mergeable &&
    reviewDecision == .reviewRequired &&
    requiredChecksStatus == .passed &&
    branchRuleEvaluation == .clear &&
    !mergeStateStatusIsStructurallyBlocking
```

It then persists an explicit `.ready`, `.blocked`, or `.unknown` outcome.
Dashboard and notification consumers must read that stored outcome rather than
re-deriving the predicate independently.

`reviewDecision` already incorporates required approvals and CODEOWNERS
approval requirements. PRSieve does not need to parse or evaluate CODEOWNERS
for merge readiness.

The expected `mergeStateStatus` is `.blocked` because approval is still
missing, but exact equality with `.blocked` is not part of the primary
predicate. GitHub computes merge state asynchronously, and `.unstable` may
reflect an optional failing context even when every required check passes.
Use the explicit check, review, conflict, draft, and rule inputs as the
authoritative decision. Use `mergeStateStatus` to detect structural blockers
and inconsistent or not-yet-computed state.

## Required Check Evaluation

### Legacy status contexts

Examples include Buildkite, Olive, Danger, and ISC code freeze.

| GitHub `StatusContext.state` | PRSieve result |
| --- | --- |
| `SUCCESS` | Passing input |
| `EXPECTED` | Running |
| `PENDING` | Running |
| `FAILURE` | Failed |
| `ERROR` | Failed |
| Missing or unrecognized | Unknown |

### Check runs

Examples include GitHub Actions and Semgrep.

| GitHub Check Run state | PRSieve result |
| --- | --- |
| `COMPLETED` + `SUCCESS` | Passing input |
| `COMPLETED` + `NEUTRAL` | Passing input |
| `COMPLETED` + `SKIPPED` | Passing input |
| `REQUESTED` | Running |
| `QUEUED` | Running |
| `IN_PROGRESS` | Running |
| `WAITING` | Running |
| `PENDING` | Running |
| `FAILURE` | Failed |
| `TIMED_OUT` | Failed |
| `CANCELLED` | Failed |
| `ACTION_REQUIRED` | Failed |
| `STARTUP_FAILURE` | Failed |
| `STALE` | Failed |
| Missing or unrecognized conclusion | Unknown |

GitHub treats `SUCCESS`, `NEUTRAL`, and `SKIPPED` as successful conclusions
for required checks.

### Aggregate precedence

Evaluate only required contexts, with failure-first precedence:

```text
If any required check failed  -> failed
Else if any is running        -> running
Else if any is unknown        -> unknown
Else                          -> passed
```

If a repository has no required checks, the result is `passed`, but only after
confirming that through the Rules API. A missing status rollup must not be
interpreted as "no requirements."

If a check and a legacy status share the same required name and GitHub marks
both as required, both must pass.

## Readiness Inputs

| Input | Meaning | Source |
| --- | --- | --- |
| `state` | PR remains open | GraphQL `PullRequest.state` |
| `isDraft` | Drafts are not ready | GraphQL `PullRequest.isDraft` |
| `mergeable` | GitHub can create the merge without conflicts | GraphQL `PullRequest.mergeable` |
| `mergeStateStatus` | Detailed aggregate merge state | GraphQL `PullRequest.mergeStateStatus` |
| `reviewDecision` | A qualifying approval is still required | GraphQL `PullRequest.reviewDecision` |
| Required check contexts | Build, test, and policy requirements | Latest commit's GraphQL `statusCheckRollup` |
| Active branch rules | Non-check restrictions and expected required checks | REST Rules API |
| Changed files | Detect applicable file-path restrictions | Existing PR details fetch |

### Review decisions

| `reviewDecision` | Ready for review? |
| --- | --- |
| `REVIEW_REQUIRED` | Eligible |
| `APPROVED` | No; approval is no longer the remaining action |
| `CHANGES_REQUESTED` | No |
| `null` | No or unknown |

Approved PRs continue into PRSieve's Reviewed section.

Requiring `REVIEW_REQUIRED` is deliberate. A repository without mandatory
approval may return `null` even when somebody manually requested a review.
Such a PR does not *need* an approval to merge, so it does not meet this
feature's definition: "approval is the only remaining merge requirement."

### Merge states

| State | Meaning for readiness |
| --- | --- |
| `MERGEABLE` + `BLOCKED` | Expected when approval is the remaining blocker |
| `CONFLICTING` / `DIRTY` | Not ready |
| `DRAFT` | Not ready |
| `BEHIND` | Not ready when active rules require branch freshness |
| `UNSTABLE` | Do not reject solely on this value; required checks and rules are authoritative |
| `UNKNOWN` | Retry briefly, then unknown; never notify while unresolved |
| `CLEAN` / `HAS_HOOKS` with `REVIEW_REQUIRED` | Record diagnostically and let explicit inputs decide |

When GitHub returns `UNKNOWN`, retry the readiness query a small bounded
number of times with short delays during the same refresh. Do not wait for the
next 15-30 minute polling interval merely because GitHub is still calculating
mergeability. If it remains unknown, fail closed for that refresh.

## Active Branch Rules

Fetch all active rules for each repository and base branch:

```text
GET /repos/{owner}/{repo}/rules/branches/{baseBranch}
```

This endpoint aggregates applicable repository, organization, and enterprise
rules. Cache its result by `(repository, baseBranch)` because rules change
infrequently.

### Rules already represented by GraphQL inputs

- Required status checks: `StatusContext.isRequired` and `CheckRun.isRequired`
- Required approving reviews: `reviewDecision`
- Required CODEOWNERS approval: `reviewDecision`
- Draft state: `isDraft`
- Merge conflicts: `mergeable`
- Strict branch freshness: `mergeStateStatus == BEHIND`

### Current explicit non-check restriction

The Instacart repositories inspected inherit restricted paths:

```text
.github/agents/*.md
agents/*.md
```

PRSieve already fetches changed filenames. If a PR changes one of these paths,
do not declare it ready unless bypass-actor evaluation is implemented later.
Failing closed is safer than producing a false ready notification.

### Current Instacart Android rules

The relevant required checks on `master` are:

- `Buildkite`
- `olive/require-approvals`

The branch also requires one approving review. Branch freshness is not strict,
and required conversation resolution is disabled.

### Current Carrot rules

The relevant required checks on `master` are:

- `Buildkite`
- `ISC code freeze`
- `olive/require-approvals`

Carrot requires one approving review and a code-owner approval. Both review
requirements are represented by `reviewDecision`; PRSieve does not need an
additional CODEOWNERS check.

Branch freshness is not strict, and required conversation resolution is
disabled.

### Unsupported future rules

If the Rules API returns an active merge-blocking rule PRSieve does not
understand, such as required deployments, metadata restrictions, or signed
commit requirements, set branch-rule evaluation to `unknown`. Do not produce
a ready notification from an incomplete rule interpretation.

## API Changes

### Remove the legacy combined-status calculation

PRSieve currently calls:

```text
GET /repos/{repo}/commits/{sha}/status
```

That approach is insufficient because:

- It only covers legacy Status Contexts.
- It omits GitHub Check Runs.
- GitHub returns only 30 contexts by default.
- PRSieve recomputes the result from the incomplete first page.
- It cannot distinguish required from optional checks.
- It does not describe review or mergeability state.

Remove `fetchCombinedStatus` from the readiness path. Once all consumers are
migrated, remove the ignored-CI-check setting and its UI.

### Add GraphQL access

Add an authenticated POST client for:

```text
https://api.github.com/graphql
```

Use the existing GitHub token and API headers.

For each PR, fetch:

```graphql
query Readiness(
  $owner: String!
  $repo: String!
  $number: Int!
  $after: String
) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      state
      isDraft
      mergeable
      mergeStateStatus
      reviewDecision
      baseRefName
      headRefOid

      commits(last: 1) {
        nodes {
          commit {
            oid
            statusCheckRollup {
              contexts(first: 100, after: $after) {
                pageInfo {
                  hasNextPage
                  endCursor
                }
                nodes {
                  __typename

                  ... on StatusContext {
                    context
                    state
                    isRequired(pullRequestNumber: $number)
                  }

                  ... on CheckRun {
                    name
                    status
                    conclusion
                    isRequired(pullRequestNumber: $number)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

Implementation requirements:

- Fetch only the latest commit's current rollup, not historical runs.
- Request up to 100 contexts per page.
- Continue while `hasNextPage` is true.
- Evaluate every required context across every page.
- Verify the returned commit OID matches `headRefOid`.
- Treat GraphQL errors, partial responses, pagination failures, and unknown
  enum values as `unknown`.
- Retry a GraphQL `mergeable` or `mergeStateStatus` value of `UNKNOWN` a small
  bounded number of times with short delays during the same refresh.
- Never retain a previously-ready state after a refresh failure.

### Request count and concurrency

Initially, use one GraphQL request per PR, bounded to five concurrent requests.
This replaces the existing one REST status request per unchanged PR, so the
request shape remains roughly the same.

A later optimization may batch multiple aliased PR queries into one GraphQL
request per repository. Batching is not required for correctness and should
not delay the first implementation.

### Rules API caching

On the first refresh for a `(repository, baseBranch)` pair, fetch the active
rules and cache them:

```text
GET /repos/{owner}/{repo}/rules/branches/{baseBranch}
```

Use an approximately one-hour TTL and share the result across the entire
refresh. A rule-fetch failure makes readiness unknown but does not hide the PR
or affect its relevance category.

Use the rules response defensively to:

- Confirm which required checks should exist.
- Detect a required check that has not yet produced a rollup context.
- Evaluate supported non-check restrictions.
- Detect unsupported rule types and fail closed.

For contexts that exist in the rollup, GraphQL `isRequired` remains
authoritative because GitHub applies the configured integration/source
requirement. Rules reconciliation is primarily responsible for detecting an
expected required context that has not emitted a rollup entry. Matching must
account for both `{context, integration_id}` from the Rules API and the
corresponding status/check identity; a same-named context from the wrong
integration must not satisfy the rule.

## Model Changes

Do not continue overloading `BuildStatus`.

Store the new non-optional readiness inputs inside one optional nested value:

```swift
enum ReadinessOutcome: String, Codable, Sendable {
    case ready
    case blocked
    case unknown
}

struct PRReadiness: Codable, Sendable {
    var outcome: ReadinessOutcome
    var requiredChecksStatus: RequiredChecksStatus
    var mergeableState: MergeableState
    var mergeStateStatus: MergeStateStatus
    var reviewDecision: ReviewDecision?
    var blocker: ReadinessBlocker?
    var checkedAt: Date
}

struct PullRequest {
    // Existing fields...
    var readiness: PRReadiness? = nil
    var readinessNotificationBaseline: Bool? = nil
}
```

Expose:

```swift
var isReadyForReview: Bool {
    readiness?.outcome == .ready
}
```

`ReadinessOutcome` is the persisted single source of truth. `blocker` explains
a `.blocked` or `.unknown` result but does not define readiness by itself.
Using `blocker == nil` as an implicit success signal is unsafe because missing
or partially decoded diagnostic data could otherwise appear ready.

Suggested blockers:

```swift
enum ReadinessBlocker {
    case checksFailed
    case checksRunning
    case mergeConflict
    case draft
    case branchBehind
    case changesRequested
    case restrictedFiles
    case unsupportedRule
    case githubStateUnknown
}
```

Persist the inputs so the dashboard can render immediately after launch, but
refresh them every poll.

The optional nested field is required for safe migration. `PullRequest` uses
synthesized `Codable`; adding new non-optional stored properties would make
every existing `pull_requests.json` fail decoding and cause
`PersistenceService.loadPullRequests()` to return an empty list. A missing
`readiness` key must decode as `nil`, preserving the cached PR and forcing a
one-time readiness refresh.

Legacy `buildStatus` values must not be trusted during migration. Old JSON may
contain the key, but the new model ignores it and treats `readiness == nil` as
unfetched.

## Legacy Buildkite Cleanup

`BuildkiteClient` is currently constructed and injected into
`PollingService`, but it is not called by the refresh path. GitHub's required
check rollup becomes the sole source of Buildkite state.

After the GraphQL path is working, remove:

- `BuildkiteClient.swift`
- The `buildkiteClient` property and initializer parameter in
  `PollingService`
- `PRSieveApp` construction and credential loading for `BuildkiteClient`
- Legacy Buildkite settings and token plumbing that have no remaining
  consumer
- `BuildStatus.swift` after persistence and every UI/test consumer has moved
  to the new types

Keep old JSON decoding compatible by allowing obsolete keys to be ignored.

## Polling Changes

### Full detail fetch

Replace the parallel `fetchCombinedStatus` call inside `fetchPRDetail` with
`fetchMergeReadiness`.

The existing REST calls for files, reviews, comments, timeline, and CODEOWNERS
can remain unchanged.

### Unchanged PR refresh

Replace `refreshStatuses` with `refreshReadiness`.

Run it for every unchanged PR on every poll because:

- Check changes do not bump a PR's `updatedAt`.
- Required-status configuration can change.
- Mergeability can change when the base branch changes.
- Approval state can change.
- Code-freeze status can change independently.

On an API failure:

```text
requiredChecksStatus = unknown
isReadyForReview = false
```

Do not fall back to a stale `.passed` value. The current fallback in
`PollingService.refreshStatuses` can preserve a false-positive ready state and
must be removed.

`PollingService.reusableCopy` currently starts with the stored PR and resets
only categorization-decision fields. Preserve both `readiness` and
`readinessNotificationBaseline` through this copy. Capture the previous
outcome and notification baseline before `refreshReadiness` overwrites current
readiness, because transition calculation depends on the previous known
state. Readiness must never be reset as part of categorization reuse.

Categorization caching and the LLM fingerprint do not need to change;
readiness is independent of relevance categorization.

## UI and Behavior Changes

Replace every consumer of `buildStatus == .passed`.

### Filter

Rename:

```text
Show only PRs with passing CI
```

to:

```text
Show only PRs ready for review
```

Filter on `isReadyForReview`.

### Menu-bar indicator

Turn the icon orange when any priority/review PR has
`isReadyForReview == true`.

Update accessibility text from "priority PRs ready" to "priority PRs ready for
review."

### PR status pill

Replace misleading CI-only text with readiness-aware labels:

- `Ready for review`
- `Required checks failing`
- `Required checks running`
- `Merge conflict`
- `Blocked`

Do not label Olive or code-freeze policy results as merely "CI passed."

### Categorization

Relevance categorization remains unchanged. A priority PR remains visible even
when it is not ready for review.

For PRs `instacart/instacart-android#49371` and `#49591`:

- Their category remains priority.
- Their required-check status becomes failed while Buildkite is failing.
- `isReadyForReview` is false.
- Once Buildkite passes, they become ready if a review is still required and
  no other blocker appears.

## Notifications

Notifications should trigger on a readiness transition:

```text
wasReadyForReview == false
isReadyForReview == true
```

Define first-sight and migration behavior explicitly:

| PR state before refresh | Current readiness | Notify? |
| --- | --- | --- |
| Genuinely new PR, no previous object | Ready | Yes; treat absent prior state as false |
| Existing cached PR with legacy `readiness == nil` | Ready | No; establish a migration baseline |
| Existing PR previously not ready | Ready | Yes |
| Existing PR previously ready | Ready | No |
| Existing PR previously ready | Not ready | No; update baseline to false |
| Existing PR previously ready | Unknown | No; preserve the last known baseline |
| Last known state not ready, then unknown | Ready later | Yes |
| Last known state ready, then unknown | Ready later | No |

`PollingService` already builds `existingByID`, so it can distinguish a newly
discovered PR from a migrated cached PR. It should compute the transition and
pass explicit notification candidates to `NotificationService`, rather than
asking `NotificationService` to reconstruct previous readiness from its
current persisted ID set.

Persist `readinessNotificationBaseline` separately from current readiness.
Update it only when the current result is definitively ready or not ready; an
unknown/API-error result must not erase the last known baseline. This prevents
a transient `ready -> unknown -> ready` sequence from generating a duplicate
notification while still allowing `not ready -> unknown -> ready` to notify.

Transition-based notifications prevent:

- Notifications from stale persisted state.
- Repeated notifications after transient API failures.
- A false-positive notification permanently suppressing a later legitimate
  readiness notification.

Keep the existing decision about whether previously commented-on or reviewed
PRs should notify as a separate product behavior. It is not part of the
readiness calculation.

## Testing

Add table-driven tests for the pure required-check and readiness evaluators.

### Required checks

- Required Buildkite failure -> failed and not ready.
- Required Buildkite pending -> running and not ready.
- Buildkite and Olive successful -> passed.
- Optional `danger/danger` failure -> still passed.
- Required `danger/danger` failure -> failed.
- Required Check Run `SUCCESS` -> passed.
- Required Check Run `NEUTRAL` -> passed.
- Required Check Run `SKIPPED` -> passed.
- Required Check Run cancelled, timed out, stale, or action-required -> failed.
- Required context on a second GraphQL page -> included.
- Missing expected required context -> running or unknown, never passed.
- No required checks confirmed by rules -> passed.

### Rules reconciliation

- Required `{context, integration_id}` matches the emitted context from the
  expected integration.
- Same context name from the wrong integration does not satisfy the rule.
- Required context is entirely absent from the rollup.
- Required context is present in `EXPECTED` state.
- Required context is emitted as a legacy `StatusContext`.
- Required context is emitted as a `CheckRun`.
- A status and check share the same required name; both GitHub-required nodes
  must pass.
- Multiple active rulesets require the same context.
- Repository, organization, and enterprise rules are aggregated.
- Integration-qualified check names match correctly.
- A rule is removed while an old status with that name remains in the rollup;
  the old optional status does not participate.

### Readiness

- All required checks pass and review is required -> ready.
- Merge conflict -> not ready.
- Draft -> not ready.
- Branch behind under a strict rule -> not ready.
- Changes requested -> not ready.
- Approved -> no longer "ready except for review."
- Restricted agent path -> not ready.
- Unknown active rule -> unknown and not ready.
- `mergeStateStatus == UNKNOWN` retries during the current refresh.
- `mergeStateStatus == UNSTABLE` with all required checks passing does not
  fail solely because an optional check is red.
- GraphQL partial error -> unknown and not ready.
- Returned commit OID differs from `headRefOid` -> unknown and not ready.
- Refresh failure after a previously-ready result -> unknown, never
  stale-ready.
- Brand-new PR first seen ready -> notification candidate.
- Cached legacy PR first recomputed as ready -> baseline only, no migration
  notification.
- Existing not-ready PR transitions to ready -> notification candidate.
- Existing ready PR transitions through unknown and back to ready -> no
  duplicate notification.
- Existing not-ready PR transitions through unknown and then to ready ->
  notification candidate.
- `reusableCopy` preserves readiness and the notification baseline while
  resetting categorization fields.

### Regression fixtures

- `instacart/instacart-android#49371` shape: 49 contexts, Buildkite failure
  after the first 30 contexts.
- `instacart/instacart-android#49591` shape: 46 contexts, Buildkite failure
  after the first 30 contexts.
- Carrot shape: Buildkite, ISC code freeze, Olive, and code-owner review
  requirement.

Run `./test.sh` after all code changes.

## Implementation Order

1. Add the pure required-check and readiness models and evaluator.
2. Add GraphQL response decoding and status-context pagination. As the first
   integration check, query `mergeStateStatus` with the real configured token
   and fail the step if GitHub returns a field-level error.
3. Add bounded retry handling for asynchronously computed unknown merge state.
4. Add the cached active-rules fetcher.
5. Replace full-fetch and unchanged-PR status refresh paths.
6. Migrate persistence with optional nested readiness and without trusting
   legacy `.passed` values.
7. Implement explicit first-sight, migration-baseline, and false-to-true
   notification transitions.
8. Move filtering, menu-bar state, notifications, and status pills to
   `isReadyForReview`.
9. Remove the ignored-CI-check setting after all consumers are migrated.
10. Remove the unused Buildkite client, settings, and legacy `BuildStatus`.
11. Add regression fixtures for the two Android PRs and Carrot rules.
12. Run the complete test suite.
13. Validate live:
    - Keep captured responses from `#49371` and `#49591` as permanent
      regression fixtures even after those PRs close.
    - If either PR remains open and Buildkite-red, confirm it is not ready.
    - Dynamically locate an open `REVIEW_REQUIRED` PR with a failing required
      check and confirm it is not ready.
    - Dynamically locate an open `REVIEW_REQUIRED` PR with all required checks
      passing and confirm it is ready.
    - When available, verify an optional failing context does not prevent
      readiness.

`mergeStateStatus` has already been empirically verified against the live
GitHub GraphQL endpoint with the configured token for Android PRs `#49371` and
`#49591`; both returned `MERGEABLE`, `BLOCKED`, and `REVIEW_REQUIRED`. The
early step-2 integration check preserves that verification as an explicit
implementation gate rather than relying only on final validation.

## References

- [GitHub GraphQL PullRequest fields](https://docs.github.com/en/graphql/reference/pulls#pullrequest)
- [GitHub GraphQL CheckRun fields](https://docs.github.com/en/graphql/reference/checks#checkrun)
- [GitHub status-check behavior](https://docs.github.com/en/pull-requests/reference/status-checks)
- [GitHub active branch rules API](https://docs.github.com/en/rest/repos/rules#get-rules-for-a-branch)
