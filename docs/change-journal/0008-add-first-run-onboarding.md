# 0008 — Add first-run onboarding

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/19
Branch: `19-first-run-onboarding`

## What was requested

Show a Welcome screen on first launch with invitation-link entry, QR sign-in
and a quiet option to import a user's own configuration file. The account
backend is not ready, so the interface must be usable with temporary mock data
without coupling screens to that mock implementation.

## Why

Home cannot truthfully present an account subscription before access has been
established. Implementing the journey now defines the backend boundary and
allows the product flow to be reviewed while account services are developed.

## How it was implemented

- Added an `AccountGateway` interface for invitation and QR authentication.
- Added a temporary `MockAccountGateway` that returns only a generic local demo
  session and never returns credentials, server addresses or configurations.
- The screen explicitly says validation is local until the backend is ready.
- Added a localized RU/EN Welcome screen with URL field, validation, primary
  action, QR alternative and subdued file-import action.
- QR explains that camera/backend integration is not connected before starting
  a demo session; it does not pretend to scan anything.
- `.conf` import uses the operating system file picker, checks for WireGuard
  Interface and Peer sections, then writes through the existing `ConfigStore`.
- The direct BSD-3-Clause `file_selector` dependency is recorded in
  `ATTRIBUTION.md` as required by `CONTRIBUTING.md`.
- Completion is stored in the existing readable `settings.json` and loaded
  before the first frame. Settings provides a disconnect-account action to
  return to onboarding.
- The Caelo logo is reused from the repository; no generated replacement asset
  was introduced.

## Verification and result

- `flutter analyze` passed during implementation.
- Three focused widget tests cover Russian content, invitation validation and
  the explicitly labelled QR demo path.
- No real invitation, key, account or server address is present in source or
  tests.

After the stacked Home task, the complete suite passed with 34 tests and the
official Android script produced split and universal debug APKs. A clean
Android 16 install opened Welcome, accepted a syntactically valid temporary
invitation and opened Home. The implementation commit is `cd07a39`; rollback
with `git revert cd07a39`.
