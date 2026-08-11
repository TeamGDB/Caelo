# 0021 — Show the measured ping for a custom server

Date: 2026-08-11
Issue: https://github.com/TeamGDB/Caelo/issues/35
Branch: `35-custom-server-ping`

## What was requested

Fix the missing ping after adding a user-owned server configuration.

## Why

A custom configuration correctly had no fabricated catalog latency, but the
Home server surface only read that nullable catalog field. It ignored the real
latency later published in `TunnelStatus`. Android also stopped after bringing
up the system tunnel and never performed the reachability request that both
proves traffic works and measures its delay.

## How it was implemented

- Android now calls the core reachability check after the tunnel descriptor is
  connected and its sockets are protected from recursive VPN routing.
- The server catalog also measures missing latency in the background with the
  core's isolated `probe` path. Home receives the server list immediately and
  rows update progressively; probes run sequentially to avoid opening several
  tunnel sessions and network requests at once.
- The measured `elapsed_ms` is published as `TunnelStatus.pingMs`. Failure to
  obtain this optional display value is recorded but does not tear down a
  descriptor that Android and the core already accepted.
- Home passes a connected tunnel's ping into the persistent server section.
- The runtime value overrides catalog latency only for the currently selected
  server, in both the collapsed header and selected list row.
- Disconnecting clears the runtime presentation value. Before a real
  measurement exists, the field remains empty rather than showing invented
  data.
- Added regression tests for a custom server with no initial catalog ping,
  progressive controller updates, and redacted endpoint-to-latency projection.

## Verification and result

- `flutter analyze`: no issues.
- `flutter test`: all 77 tests passed, including progressive latency updates,
  custom-config probing and clearing the connected runtime value.
- `scripts/build-android.sh debug`: built debug APKs for `armeabi-v7a`,
  `arm64-v8a`, `x86_64`, and the universal package.
- Installed the universal APK over existing emulator data. Without connecting
  the system VPN, background probes produced real values for two reachable
  saved custom configurations; the selected server showed the same measured
  value in the collapsed header and its selected list row. The unreachable
  configuration correctly remained blank.
- Also verified that a failed optional measurement no longer turns an accepted
  Android tunnel descriptor into a failed connection.
- Android logs contained no Flutter rendering errors or fatal exceptions.

The missing-ping problem is fixed. Values appear progressively when a real
probe succeeds; failure or absence of a measurement is represented by an empty
field rather than fabricated data.

## Rollback

Revert the task commit from a descendant branch. The previous completed state
remains available on local branch `34-server-list-behavior`.
