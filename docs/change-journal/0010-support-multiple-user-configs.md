# 0010 — Support multiple user configurations

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/23
Branch: `23-multiple-user-configs`

## What was requested

Allow several user-owned configurations to be added in Settings and show them
alongside subscription/mock servers in the Home selection list.

## Why

The original store exposed one `tunnel.conf`, so adding another configuration
overwrote the first. Tunnel clients still need exactly one active configuration
at a time, but storage and selection do not need to share that limitation.

## How it was implemented

- `ConfigStore` now keeps a small metadata index plus one restricted `.conf`
  file per entry.
- Existing `tunnel.conf` is migrated atomically into an `Imported
  configuration` entry before the legacy file is removed.
- The existing `read()` contract remains: Android, Apple and core clients see
  only the selected configuration, so the Flutter ↔ core boundary is unchanged.
- Settings lists every configuration and opens an editor for add, rename,
  update and delete operations.
- Imported files use their filename as the initial display name.
- `DevelopmentServerCatalog` combines temporary subscription presentation data
  with user configs. User entries expose only name/id and a `Custom` badge;
  private keys, peers and endpoints remain inside the config file.
- Selecting a custom entry makes its config active before persisting the Home
  selection.
- Returning from Settings reloads both the catalog and tunnel configuration
  availability.

## Verification and result

- `flutter analyze` passed with no issues.
- All 37 Flutter tests passed at this stage.
- Storage tests cover multiple entries, active selection, deletion fallback,
  migration of the old file and absence of secrets in catalog metadata.

Multiple own configs are now independently stored and available to Home. The
official Android build produced core libraries for three ABIs plus split and
universal APKs. On Android 16, the existing legacy config appeared as `Imported
configuration`, a second `Office` config was added through Settings, and both
appeared in the Home server list. Implementation commit: `fa285c3`; rollback
with `git revert fa285c3`.
