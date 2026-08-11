# 0012 — Add emoji to user configurations

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/26
Branch: `26-custom-config-emoji`

## What was requested

Give each user-owned configuration an input for its own flag emoji and show it
where that configuration appears in Home.

## Why

Names alone are slower to distinguish in a mixed server list, while the shared
document icon made every local entry look identical. The flag is presentation
metadata and does not belong inside the tunnel configuration.

## How it was implemented

- Added `emoji` to `StoredConfig` metadata with a neutral document fallback.
- Existing `configs.json` rows without the field continue to decode as `📄`.
- Added a compact flag/emoji input beside the configuration name for both add
  and edit flows.
- Empty values normalize to `📄`; full emoji sequences are stored as entered
  rather than being split by UTF-16 code units.
- `DevelopmentServerCatalog` forwards the saved emoji without exposing config
  contents.

## Verification and result

- Storage/catalog tests cover a custom `🏢` value and legacy metadata fallback.
- `flutter analyze`: passed with no findings.
- `flutter test`: all 41 tests passed.
- Android debug APKs were built successfully for ARM64, ARMv7, x86_64, and the
  universal target.
- The stacked Home verification showed every existing user configuration in
  the server list; older saved rows correctly retained the `📄` fallback.

Implementation commit: `d926a88`

## Rollback

Run `git revert d926a88` from a descendant branch.
