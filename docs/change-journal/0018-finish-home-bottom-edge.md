# 0018 — Finish the Home bottom edge

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/32
Branch: `32-home-bottom-edge`

## What was requested

Remove the green strip below the server section, make the connection control a
little larger and higher, render its disconnected label in black, and allow a
tap on the selected server to expand the available-server list.

## Why

Wrapping the complete Home stack in `SafeArea` stopped the server surface above
the system gesture area and exposed the page background. The primary action
also remained slightly small and low after the server-section changes. Finally,
the selected-server summary looked interactive but only accepted a drag.

## How it was implemented

- Moved the server drawer outside Home's bottom `SafeArea`, while keeping the
  power and Settings controls inside their safe regions.
- Extended the list's own bottom padding by the device inset so content remains
  reachable even though the surface paint continues to the physical edge.
- Increased the power-control diameter and shifted its alignment upward.
- Gave only the disconnected label a near-black light-theme colour; the power
  icon retains the existing primary colour and dark mode remains legible.
- Added tap-to-expand to the unlocked current-server summary without removing
  swipe interaction or independent list scrolling.
- Added widget coverage for bottom-edge paint, tap expansion, idle label colour,
  and the updated power-control geometry.

## Verification and result

- `flutter analyze`: passed with no findings.
- `flutter test`: all 60 combined tests passed.
- Android debug APKs built successfully for ARM64, ARMv7, x86_64, and the
  universal target; the universal APK was installed over existing data.
- The light-theme device check confirmed the white server surface reaches
  behind the gesture area, with no green strip at the bottom.
- The larger, higher control rendered a black disconnected label while keeping
  its blue power icon, and tapping the current-server summary exposed the list.
- Logcat contained no Flutter error, overflow, or fatal crash.

## Rollback

Revert the commit whose subject is
`Finish Home controls and bottom server edge` from a descendant branch.
