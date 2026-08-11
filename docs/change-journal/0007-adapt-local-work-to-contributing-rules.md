# 0007 — Adapt local work to the contribution rules

Date: 2026-08-11

## What was requested

Update the local work after Vladimir's changes reached `main`, read and follow
the newly documented task and branch rules, and preserve the work without
merging or publishing it.

## Why

`origin/main` gained the macOS NetworkExtension path, removal of the privileged
helper, the configuration/probe core boundary and explicit contribution rules.
Our original branch predated those decisions, combined several logical tasks
and used a branch name that could not be connected to an issue.

## How it was done

- Fetched `origin/main` at `c9858cc`.
- Converted the four already completed Project 2 draft cards into repository
  issues rather than creating duplicates: #15, #16, #17 and #18.
- Saved the exact pre-rebase state as the local recovery branch
  `backup/pre-main-adaptation-20260811`.
- Rebased the work onto `origin/main`, as required by `CONTRIBUTING.md`.
- Verified that the rebase retains `AppleTunnelClient` for Apple platforms and
  does not restore the removed privileged-helper clients.
- Organised the work as a local stacked branch series:
  - `15-cupertino-design-system` — design foundation;
  - `16-home-real-state` — Home visual adaptation using real core state;
  - `17-saved-locale` — saved system/Russian/English selection;
  - `18-settings-upper-right` — safe upper-right Settings action.
- Updated earlier journal rollback hashes, which necessarily changed during
  rebase.

No branch was merged into `main` and nothing was pushed.

## Verification

- `dart format --set-exit-if-changed lib test` — no formatting changes.
- `flutter analyze` — no issues.
- `flutter test` — all 29 tests passed on the rebased tree.
- `./scripts/build-android.sh debug` — rebuilt the Go core for `arm64-v8a`,
  `armeabi-v7a` and `x86_64`, then produced split and universal debug APKs.
- The rebased `main.dart` was inspected to confirm the Apple system-extension
  client remains authoritative and no removed helper code was resurrected.

## Result and recovery

The work now sits on top of the current project architecture and follows the
issue-linked branch naming convention. Each later branch builds on the previous
UI branch, so it can be reviewed as a stacked change while its own commit stays
independently reversible.

The untouched pre-adaptation history remains reachable at
`backup/pre-main-adaptation-20260811`. If the adaptation itself must be
discarded, that branch is the local recovery point.
