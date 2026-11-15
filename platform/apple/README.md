# platform/apple

Swift shared by the iOS packet tunnel extension and the macOS system extension.

The two run in different kinds of process — iOS embeds an app extension, macOS
installs a system extension — but what happens inside is the same: ask the core
to describe the configuration, tell the system what the tunnel looks like, hand
the descriptor over.

It lives here rather than in either Xcode project because both reference it.
Two copies of a file this fiddly would disagree within a week, and the one that
disagreed would be whichever platform was tested less.


## Runtime failure and diagnostics

A local health monitor reads `caelo_diagnostics_fd` every two seconds, including
while the app is in the background. It records a confirmed packet-bridge failure
once. It does not cancel the provider or remove capture routes: traffic remains
blocked until an explicit disconnect. The app reads the failure in live status,
shows an explanation and makes the main button **Disconnect**. It does not
silently retry other servers or release traffic outside the VPN.

Log export requests live core lines and a local status snapshot over provider
IPC. A two-second timeout falls back to persisted lifecycle history, with the
source marked in the report. Old extensions remain readable. Replies race
safely with their timeout; snapshots preserve original core timestamps and
remove duplicates. Clearing diagnostics clears the extension's ring and file.

The bounded file is now `Library/Caches/Caelo/tunnel.log` inside the app group,
where developer file tools can read it. Existing root-level `tunnel.log` is read
as a migration fallback and removed after a successful write to the new path.
The app and extension share the same storage/formatting implementation.
Credentials and subscription/VLESS links are redacted again before persistence
and export; structured snapshots use an allowlist of operational fields.

Run the Foundation-only tests on a Mac with Xcode:

```sh
./scripts/test-apple-diagnostics.sh
```

They cover live/saved export, redaction, bounded concurrent persistence,
legacy migration, timeout/reply races and local-failure monitoring. The normal
iOS/macOS builds validate the NetworkExtension and Flutter integration.


## macOS UDP rights in the released app

AmneziaWG probes run in the main application before the system extension is
started. They bind unconnected UDP sockets, so the sandboxed release app needs
both `com.apple.security.network.client` and `com.apple.security.network.server`.
The extension having those rights is not enough. Debug builds already had the
rights and did not exercise the release app's sandbox policy (issue #178).

Read-only checks, without opening sockets or changing a VPN:

```sh
python3 scripts/check-macos-network-entitlements.py
python3 scripts/check-macos-network-entitlements.py --app /path/to/Caelo.app
```

The signed-app check inspects both the app and its embedded system extension.
The packaging workflow runs it before notarisation and against the app inside
the final DMG. Missing rights stop publication.

The macOS CI job also runs `--exercise-bind`: a small ad-hoc-signed sandboxed
program binds an ephemeral UDP port and closes it without sending packets.
A control signed without `network.server` must fail with EPERM; the release
network rights must allow the bind. The script refuses to run this experiment
outside a macOS GitHub Actions runner. It never creates a VPN or changes routes,
DNS or firewall settings.
