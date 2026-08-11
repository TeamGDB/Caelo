# 0014 — Flatten the server section visual

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/28
Branch: `28-flat-server-section`

## What was requested

Bring the expanded server section closer to the supplied visual reference,
while removing the `Main`, `Stable`, `Testing`, and `Custom` badges.

## Why

The previous implementation had the right swipe interaction but still read as
a collection of separate cards. The reference uses one continuous surface,
with a stronger current-server summary and a quieter, easier-to-scan list.

## How it was implemented

- Kept the existing persistent swipe interaction and backend-facing model.
- Made the current-server label a centred section heading and grouped its flag,
  name, description, latency, and collapse affordance into one summary row.
- Increased the server-list heading hierarchy and retained the existing honest
  development-data notice instead of inventing recommendation copy.
- Removed all badge rendering without removing fields from the catalog
  contract.
- Made ordinary rows transparent and borderless; only the selected row gets a
  shared tinted surface, outline, and check mark.
- Reused existing server locations, measured latency values, and stored config
  metadata; no new mock values were introduced.
- Added widget assertions for missing badges and the flat unselected row.

## Verification and result

- `flutter analyze`: passed with no findings.
- `flutter test`: all 41 tests passed.
- Android debug APKs built successfully for ARM64, ARMv7, x86_64, and the
  universal target.
- The expanded light-theme section was inspected on the Android emulator: its
  ordinary rows are flat, the selected row alone is outlined, and latency is
  omitted for user configs that do not provide it.
- The Android accessibility hierarchy contained none of the removed badge
  labels; logcat contained no Flutter error, overflow, or fatal crash.

## Rollback

Revert the commit whose subject is
`Flatten the swipeable server section` from a descendant branch.
