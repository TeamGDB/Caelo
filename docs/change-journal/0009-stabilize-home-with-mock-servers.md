# 0009 — Stabilize Home with mock servers

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/20
Branch: `20-stable-server-home`

## What was requested

Bring Home closer to the product specification, show the selected server before
connection and prevent the interface from moving when the tunnel connects or
disconnects. Temporary mock data is explicitly allowed until the backend is
ready.

## Why

The previous connection panel appeared only after the core reported a node.
That changed the vertical composition at the most distracting moment. The
future account backend will provide an ordered server list, but Home and the
selection contract can be implemented without waiting for network APIs.

## How it was implemented

- Added a Flutter-owned `ServerCatalog` boundary, consistent with issue #10 and
  the current project architecture: subscriptions/server delivery live in the
  application, while the core still owns connection state and receives one
  configuration.
- Added a replaceable `MockServerCatalog` with Helsinki, Stockholm and Frankfurt
  presentation records. The records contain only demo ids, names, flags,
  badges and latency; there are no endpoints, keys or tunnel configurations.
- Added a `ServerSelectionController` that restores and persists the selected
  demo id through the existing settings file.
- Home always reserves the same server-card and power-button geometry.
  Connecting, connected and disconnecting change visuals and lock selection,
  but do not insert/remove layout sections.
- The server action sheet shows the temporary nature of its data. Selection is
  disabled outside the disconnected phase.
- Mock selection never writes `TunnelStatus` and never impersonates the core.
- Added RU/EN labels and compact-layout coverage.

## Verification and result

- `dart format` completed without remaining changes.
- `flutter analyze` passed with no issues.
- All 34 Flutter tests passed.
- Tests cover saved selection, absence of configuration material in mock
  records, selected-server persistence across core phase changes, stable power
  control coordinates and Russian 320 × 640 layout without overflow.

The selected server is now visible before and during connection and the Home
composition remains stable. The official Android script produced core
libraries for all three supported ABIs plus split and universal debug APKs. On
Android 16, the server sheet selected Stockholm and that choice survived a
force-stop and relaunch; no Flutter, RenderFlex or fatal errors appeared in the
runtime log. The implementation commit is `223390e`; rollback with
`git revert 223390e`.
