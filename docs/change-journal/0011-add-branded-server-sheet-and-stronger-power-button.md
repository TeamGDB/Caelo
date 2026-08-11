# 0011 — Add branded server sheet and stronger power button

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/24
Branch: `24-branded-server-sheet`

## What was requested

Replace the iOS-looking system server list with a panel that rises from the
bottom, remove all text beneath the main VPN button and make that button larger
and more distinct from the page background.

## Why

`CupertinoActionSheet` is a platform system surface and visually interrupted
Caelo's otherwise shared cross-platform language. The idle power control used
nearby surface colors and a hairline border, so it did not read as the primary
action strongly enough.

## How it was implemented

- Replaced `CupertinoActionSheet` with `ServerPickerSheet`, a Caelo surface
  animated by the modal route from the bottom edge.
- The sheet has a 30 px top radius, drag handle, branded selection rows, 72%
  viewport height and the shared 560 px desktop width limit.
- The collapsed server bar remains persistent; it opens the sheet only while
  disconnected and shows a lock during active tunnel phases.
- Removed configuration, scope and reconnect text from beneath the VPN button.
  The safety-critical process-only warning moves into the fixed server card
  while relevant, so it does not move the layout or disappear.
- Added a dedicated cyan `primary` palette token for the disconnected action.
  The button now scales to 210–252 logical px, uses a 3 px cyan border, stronger
  shadow, larger icon and 21–26 px label.
- Connected green remains semantically separate from idle cyan.

## Verification and result

- `dart format` completed without remaining changes.
- `flutter analyze` passed with no issues.
- All 39 Flutter tests passed.
- Tests assert that `ServerPickerSheet` is used instead of
  `CupertinoActionSheet`, that the sheet reaches the bottom edge, the power
  control is visually dominant, compact Russian layout fits and coordinates
  remain stable across tunnel phases.

The server selector now reads as part of Caelo and the central action is larger
and more contrastive without reintroducing layout movement. The official
Android build produced core libraries for three ABIs plus split and universal
APKs. Android 16 visual inspection confirmed the cyan 252 px button, empty area
beneath it and bottom-attached branded sheet with five rows; runtime logs had
no Flutter, RenderFlex or fatal errors. Implementation commit: `e2bce8e`;
rollback with `git revert e2bce8e`.
