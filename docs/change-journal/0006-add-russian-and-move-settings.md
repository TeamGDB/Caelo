# 0006 — Add Russian and move Settings

Date: 2026-08-11

## What was requested

- Create and complete project tasks for adding Russian language support and
  moving the Settings button into the upper corner.
- Keep the implementation careful, documented and independently reversible.
- Do not introduce mock product data.

The matching conflict cards already existed in TeamGDB Project 2, so they were
reused instead of creating duplicates. They were later converted to repository
issues to follow the updated contribution rules:

- [#17 — Согласовать начальный язык и ручное переключение локали](https://github.com/TeamGDB/Caelo/issues/17)
- [#18 — Согласовать положение Settings с desktop window chrome](https://github.com/TeamGDB/Caelo/issues/18)

Both cards were moved to **In progress** before implementation and to **Done**
after verification.

## Why

The application already contained English and Russian ARB resources, but it
only followed the operating-system locale and the Language row was read-only.
The Home screen also kept Settings in the lower-right corner to avoid the
transparent macOS title bar, while the approved visual direction calls for the
upper-right corner.

Project behavior remains authoritative over the specification: the existing
system-locale behavior is retained as the default, with Russian and English as
explicit saved overrides.

## How it was implemented

### Language

- Added `system`, `russian` and `english` locale modes.
- Stored the selected mode in the existing local `settings.json`; no new
  storage mechanism or remote service was introduced.
- Loaded theme and locale before the first Flutter frame to prevent a startup
  flash in the wrong language or color scheme.
- Made the Language settings row open a native Cupertino action sheet and
  apply the choice immediately without restarting.
- Added localized names for Russian and English and regenerated Flutter's
  localization output from the ARB sources.
- Added a widget test for live English-to-Russian switching and unit checks for
  locale resolution.

After rebasing onto the current `main`, the implementation commit is `e91a88f`
(`Add saved Russian and English locale choices`) on branch `17-saved-locale`.

Rollback only this part with `git revert e91a88f`.

### Settings position

- Moved the existing Settings action to the upper-right of Home.
- Kept it inside `SafeArea` on mobile so it clears status bars and cut-outs.
- Reserved 36 logical pixels on macOS because its transparent title bar does
  not expose that chrome as a Flutter safe-area inset.
- Added layout tests for the general upper-right position and the macOS title
  bar reserve.

After rebasing onto the current `main`, the implementation commit is `3ddc555`
(`Move Settings into the upper-right safe area`) on branch
`18-settings-upper-right`.

Rollback only this part with `git revert 3ddc555`.

## Verification and result

- `flutter analyze`: passed with no issues.
- `flutter test`: all 29 tests passed.
- `flutter build apk --debug`: passed.
- APK native-library check: `libcaelo.so` is present for `arm64-v8a`,
  `armeabi-v7a` and `x86_64`.
- Android 16 emulator: Settings is visible and clickable in the upper-right
  safe area without overlapping the status bar.
- Android 16 emulator: selecting Russian updates the open Settings screen
  immediately.
- Android 16 emulator: after force-stopping and relaunching the application,
  Russian remains selected and Home remains translated.
- No mock nodes, latency values, subscriptions or connection state were added.

The requested behavior is implemented and verified. Linux desktop compilation
was not available in this environment because the host lacks the required
Clang, Ninja, pkg-config and GTK development packages; the macOS chrome rule is
covered by a platform-specific widget test.
