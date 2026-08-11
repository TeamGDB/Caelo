# 0015 — Match the server reference proportions

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/29
Branch: `29-match-server-reference`

## What was requested

Bring the server section as close as possible to the supplied reference while
retaining the earlier decision to omit all server badges.

## Why

The flat hierarchy was correct, but the first pass expanded too high, left too
much empty space inside the current-server summary, used an oversized list
heading, and packed list rows more tightly than the reference.

## How it was implemented

- Tuned the expanded extent and current-server area against emulator
  screenshots so the sheet top and list heading follow the reference geometry.
- Matched the reference wording with “Current server” / “Текущий сервер”.
- Reduced the heading size, strengthened the explanatory copy, and adjusted
  its line height so it wraps like the reference on a phone viewport.
- Increased row height substantially and aligned the flag, text, latency, and
  selection columns to the reference proportions.
- Preserved the swipe-only interaction, badge removal, existing catalog data,
  and absence of invented latency for user configurations.

## Verification and result

- `flutter analyze`: passed with no findings.
- `flutter test`: all 41 tests passed.
- Android debug APKs built successfully; the final universal APK was installed
  over existing emulator data.
- Light-theme device screenshots were used iteratively to calibrate the sheet
  extent, current-server block, heading wrap, row rhythm, and column alignment.
- Badge labels remain absent and the device log contains no Flutter error,
  overflow, or fatal crash.

## Rollback

Revert the commit whose subject is
`Match server section proportions to reference` from a descendant branch.
