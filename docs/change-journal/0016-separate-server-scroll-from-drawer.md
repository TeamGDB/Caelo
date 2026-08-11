# 0016 — Separate server scrolling from drawer movement

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/31
Branch: `31-independent-server-scroll`

## What was requested

Make server rows wider, increase typography and flags, enlarge and better
space the current-server heading, remove the description under “Choose
server”, reduce the gap before the list, and prevent list scrolling from
accidentally closing the section.

## Why

The previous shared draggable scroll controller treated a downward list gesture
at its upper boundary as a request to collapse the whole section. That made a
normal browsing gesture destructive to the current view. The visual scale also
remained too restrained compared with the supplied reference.

## How it was implemented

- Replaced the shared draggable/list controller with explicit drawer extent
  state and a separate list `ScrollController`.
- Drawer extent now changes only through a vertical drag on the persistent
  current-server header; list gestures affect only the list.
- Kept snapping, tunnel-state locking, and reset-to-top when collapsing.
- Reduced outer row insets, enlarged flags, names, descriptions, latency, and
  the selected check mark.
- Enlarged “Current server” and added space before and after it.
- Removed the development description below “Choose server” and reduced the
  following gap to one spacing step.
- Added a regression test proving a downward gesture inside the expanded list
  does not change the section position.

## Verification and result

- `flutter analyze`: passed with no findings.
- `flutter test`: all 42 tests passed, including the independent-scroll
  regression.
- Android debug APKs built successfully for ARM64, ARMv7, x86_64, and the
  universal target; the final universal APK was installed on the emulator.
- The light-theme collapsed state was inspected with the larger current-server
  heading, flags, typography, and horizontal row area.
- The removed description is absent, and logcat contains no Flutter error,
  overflow, or fatal crash.

## Rollback

Revert the commit whose subject is
`Separate server list scrolling from drawer drag` from a descendant branch.
