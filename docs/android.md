# Android visual prototype

The native Android client lives in [`apps/android`](../apps/android) and is a standalone
Gradle project built with Kotlin and Jetpack Compose. It targets Android 8–16 (API 26–36).

It is intentionally separate from Flutter's reserved `android/` runner directory. The
repository can therefore keep the existing Flutter/macOS application while the native
prototype is evaluated independently.

## Current scope

The project currently implements the product's visual and local interaction model:

- registration, password login, recovery and biometric sign-in screens;
- a built-in local administrator account (`admin` / `admin`) for demonstrations;
- server selection, connection-state animations and simulated latency changes;
- administrator screens for servers, invitations and users;
- light, dark and system themes plus Russian and English UI;
- QR generation, QR scanning through Google Code Scanner and local device-session UI;
- local settings for passwords, Passkey, account sessions and application metadata.

The VPN tunnel, remote account service, invitation validation, device synchronization,
server administration API and update distribution are **not implemented**. Connection
states, latencies, users and most server operations are simulated in memory.

## Project layout

```text
apps/android/
├── app/src/main/java/com/caelo/vpn/
│   ├── MainActivity.kt              # activity, edge-to-edge and theme persistence
│   └── ui/
│       ├── AppLogic.kt              # testable authentication/sorting helpers
│       ├── CaeloApp.kt              # authorization and home UI
│       ├── AdminScreens.kt          # settings and administration UI
│       ├── DeviceScreens.kt         # QR and device-session UI
│       └── theme/Theme.kt           # color schemes and typography
├── app/src/test/                    # JVM unit tests
├── app/src/androidTest/             # emulator/device Compose tests
└── gradle/wrapper/                  # pinned Gradle wrapper
```

## Requirements

- JDK 17;
- Android SDK 36;
- an Android 8.0+ device or emulator;
- Google Play Services for the permissionless Google Code Scanner UI.

Android Studio can create `local.properties` automatically. For command-line builds,
configure `ANDROID_HOME` or create an untracked `local.properties` containing `sdk.dir`.

## Build and install

From the repository root:

```bash
cd apps/android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The debug APK is not a release artifact: it uses the Android debug signing key and must
not be distributed as a production build.

## Tests

Run the JVM test suite without an emulator:

```bash
cd apps/android
./gradlew testDebugUnitTest
```

The JVM suite covers:

- built-in and persisted credential decisions;
- invitation normalization, roles and validation failures;
- password-change validation;
- accepted Caelo account-link QR values;
- server ordering by badge, reachability and latency;
- stable proportional scrollbar calculations.

Run the Compose instrumentation suite on a connected device or running emulator:

```bash
./gradlew connectedDebugAndroidTest
```

The instrumentation suite clears local preferences before each test and verifies the real
authorization UI, including the built-in admin login and clearing registration fields when
the user goes back.

Run the complete local verification used before commits:

```bash
./gradlew testDebugUnitTest connectedDebugAndroidTest :app:assembleDebug
```

## Local state and security limitations

This prototype stores demonstration credentials and preferences in ordinary
`SharedPreferences`. The built-in `admin` / `admin` account is deliberately insecure and
must be removed before any production release. Recovery codes and QR account-link tokens
are UI prototypes rather than server-authorized, expiring credentials.

A production implementation must move authentication and device sessions to a backend,
store local secrets with Android Keystore-backed encryption, validate single-use QR tokens
server-side, revoke sessions remotely, and connect the UI to `caelo-core` rather than the
current simulated connection state.

Google Code Scanner downloads its Barcode UI module through Google Play Services. A
sideloaded build on an emulator without current Google services can show the handled
scanner-unavailable dialog even when the rest of the app works.
