# 0020 — Integrate the node API and finish the server list

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/34
Branch: `34-server-list-behavior`

## What was requested

Reduce the space below the final server, make the scrollbar describe only the
scrolling rows, close the section from both the current-server header and a
selected row, align every latency value, and move the connection control a
little higher. The completed server interaction from `main` also had to replace
the temporary presentation source.

## Why

The expanded section looked longer than its contents, its scrollbar could be
read as belonging to the fixed heading, and choosing a server left the drawer
covering most of Home. The selected outline also changed the row's internal
layout and shifted its latency relative to every other row. Most importantly,
keeping demo servers after the subscription contract landed would create a
second, contradictory source of truth.

## How it was implemented

- Fetched `origin/main` and rebased the complete local UI stack onto it. Git
  skipped the four subscription commits already present upstream. The previous
  local state remains recoverable from branch `33-server-descriptions`.
- Replaced the production demo catalog with a projection of the current
  `SubscriptionStore` and its `SubscriptionNode` fields: stable id, name,
  description, country-derived flag and maintenance state.
- Kept custom configurations in the same presentation list without treating
  server-owned nodes as custom Settings entries.
- A manual node selection now saves the subscription pin and activates the
  exact endpoint supplied by the backend for the next tunnel connection.
- The current-server header toggles the drawer. Selecting an available list row
  closes it before persisting the choice.
- Kept the heading outside the scroll view, removed the scrollbar's main-axis
  margin, and reduced the list's final padding to the small spacing token plus
  the device safe area.
- Reserved identical trailing columns for latency and selection state. The
  selected outline is painted as a foreground decoration so it cannot inset
  and shift row contents.
- Shifted the power control another alignment step upward.
- Added tests for backend node projection and activation, hidden subscription
  endpoint storage, drawer closing behavior, and exact latency-column alignment.

## Verification and result

- `flutter analyze`: no issues.
- `flutter test`: all 75 tests passed. Coverage added in this task verifies the
  subscription projection, backend identity activation, endpoint isolation,
  both closing interactions, scrollbar/list bounds and exact latency-column
  alignment.
- `scripts/build-android.sh debug`: built debug APKs for `armeabi-v7a`,
  `arm64-v8a`, `x86_64`, and the universal package after the final changes.
- Installed the universal APK over the emulator's existing app data. Confirmed
  the higher power control, fixed heading, compact final list padding, and that
  taps on the current-server area and a list row close the section.
- The device intentionally had no fabricated subscription response; its saved
  custom configurations were used for interaction checks. Real node field
  mapping and activation were verified deterministically in tests with redacted
  endpoint material.
- Android logs contained no Flutter rendering errors or fatal exceptions.

The requested interaction is complete, the production server source is the
current subscription contract from `main`, and no demo server data remains in
the running application.

## Rollback

Revert the task commit from a descendant branch. To return to the exact state
before taking the new `main`, switch to local branch `33-server-descriptions`.
