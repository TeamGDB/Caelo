# 0017 — Integrate local UI with the subscription contract branch

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/25
Branch: `25-subscription-contract-local-ui`

## What was requested

Review the remote `25-subscription-contract` work, identify what remains,
record its commits in issue #25, and hand the separate local UI development to
that line of work without pushing or merging it remotely.

## Why

The subscription branch and the local interface were developed from the same
older base in parallel. Reviewing either branch alone could make completed work
look missing, while combining them without an audit could hide a semantic gap
behind a conflict-free cherry-pick.

## How it was implemented

- Fetched and inspected `origin/25-subscription-contract` and all four commits
  attached to the issue.
- Verified that the contract, endpoint parser, example server, subscription
  storage/fetching, and probe-based node choice are implemented.
- Replayed the complete 21-commit local UI chain onto a new local branch based
  on `origin/25-subscription-contract`; Git reported no textual conflicts.
- Audited the combined result for actual usage of `SubscriptionStore`,
  `SubscriptionFetcher`, and `NodeChooser` outside their own implementation.
- Identified the remaining product wiring: onboarding still uses
  `MockAccountGateway`, Home still uses `DevelopmentServerCatalog`, selection
  does not pin a subscription node, and the connect action does not call
  `NodeChooser.prepare` before the platform tunnel client.
- Kept the integration local. The remote branch, issue state, and repository
  history were not merged or pushed.

## Verification and result

- `flutter analyze`: passed with no findings on the combined tree.
- `flutter test`: all 58 combined tests passed.
- `go test ./...` in `core`: passed.
- `examples/subscription-server/conformance.sh`: passed for both endpoint
  parsing and the app-side subscription reader.

The two implementations coexist cleanly, but the four wiring points above are
still required before the invitation-to-connection path is real.

## Rollback

Delete the local `25-subscription-contract-local-ui` branch. No remote state
was changed by the integration itself; the issue comment can be edited or
deleted independently on GitHub.
