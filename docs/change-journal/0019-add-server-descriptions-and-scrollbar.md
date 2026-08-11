# 0019 — Add server descriptions and a visible scrollbar

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/33
Branch: `33-server-descriptions`

## What was requested

Move the connection control slightly higher, make additional servers visibly
discoverable with a scrollbar, keep “Choose server” fixed while rows scroll,
add a description input for custom configurations, and display server name plus
description instead of city plus country.

## Why

The list could contain more rows than the viewport without communicating that
fact, and scrolling moved the section heading away from its context. The data
model also only gave user configurations a name and emoji, leaving their second
line as a generic implementation label rather than something meaningful to the
person who created it.

## How it was implemented

- Shifted the power control upward by another alignment step.
- Moved “Choose server” outside the list `CustomScrollView`.
- Wrapped the independently controlled list in an always-visible
  `CupertinoScrollbar`.
- Replaced `ServerOption.location` with the presentation-level `description`.
- Added optional `description` metadata to `StoredConfig`, its JSON format, and
  create/update flows; legacy rows decode with an empty value.
- Added a localized description input to both add and edit configuration flows.
- Empty custom descriptions receive a localized “User configuration” fallback
  only at presentation time; stored tunnel text is untouched.
- Updated tests for metadata persistence, catalog projection, scrollbar
  presence, and the fixed heading position during list scrolling.

## Verification and result

- `flutter analyze`: no issues.
- `flutter test`: all 60 tests passed, including the compact Russian viewport,
  persistent heading, and independent list scrolling checks.
- `scripts/build-android.sh debug`: built debug APKs for `armeabi-v7a`,
  `arm64-v8a`, `x86_64`, and the universal package.
- Installed the universal APK over the existing emulator installation so that
  stored configurations were preserved.
- On Android, confirmed that the power control sits higher, a visible scrollbar
  communicates the longer list, “Choose server” remains fixed as rows move,
  and rows show name plus description. Existing configurations without a saved
  description display the localized fallback.
- Android logs contained no Flutter rendering errors or fatal exceptions after
  expanding and scrolling the server section.

The requested behavior is implemented. Existing configuration metadata remains
compatible and no tunnel configuration content is rewritten.

## Rollback

Revert the commit whose subject is
`Add server descriptions and fixed list chrome` from a descendant branch.
