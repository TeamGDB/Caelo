# 0013 — Make the server section swipeable

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/27
Branch: `27-swipe-server-section`

## What was requested

Keep server selection directly on Home as a bottom section that expands with
an upward swipe, rather than opening a card or system-style window on tap. Move
the primary connection control lower so it is easier to reach.

## Why

The server list is part of the main connection workflow. A persistent peek
makes the current selection visible, preserves the layout between tunnel
states, and lets the user reveal the list with the gesture described in the
product specification. The lower primary action is more comfortable for
one-handed use.

## How it was implemented

- Replaced the modal server picker route with a persistent
  `DraggableScrollableSheet` inside Home.
- The section starts as a fixed 152-pixel peek, follows an upward/downward
  swipe, and snaps between collapsed and expanded extents.
- Tapping the collapsed selection does not open anything; selection remains a
  normal action only on rows visible in the expanded section.
- The section is locked at its collapsed extent while the tunnel is changing
  state or connected, preventing a server change during an active session.
- Moved the connection control below the geometric centre without overlapping
  the collapsed server section.
- Added widget coverage for swipe-only expansion, tap inactivity, locked
  extent, compact Russian layout, and the lower control position.

## Verification and result

- `flutter analyze`: passed with no findings.
- `flutter test`: 41 tests passed.
- Android debug APKs built successfully for ARM64, ARMv7, x86_64, and the
  universal target.
- On the Android emulator, an upward swipe expanded the section from the Home
  edge and exposed both development servers and all stored user configs.
- The collapsed screen kept the lower connection control above the server
  peek; the device log contained no Flutter errors, overflow, or fatal crash.

## Rollback

Revert the commit whose subject is
`Make server selection a swipeable Home section` from a descendant branch.
