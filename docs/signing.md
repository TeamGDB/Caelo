# Signing builds in CI

What the release pipeline needs in order to produce a build that opens on
somebody else's machine, and how to give it to it. macOS first, because it is
the one that is finished; iOS, Windows and Android follow.

Everything here is done once. None of it can be done by anyone without access to
the Apple Developer account, which is why it is written down rather than
automated.

## Why any of this

The project signs manually against a named provisioning profile. On a machine
that has the profile installed this simply works, which is why it was not noticed
that a hosted runner has neither the profile nor the certificate — the release
workflow only runs on a tag or on demand, and between the extension landing and
somebody running it, three days passed (#55).

There is no unsigned fallback, on purpose. A system extension will not load on a
machine with SIP enabled unless the app carrying it has been signed and
notarised, so an unsigned macOS build of Caelo is not a lesser build — it is a
build whose main feature does not work. A workaround that produced one quietly
would still be here, unnoticed, long after signing became real.

## One certificate

**Developer ID Application**, which signs the `.app` and the system extension
inside it. The `.dmg` needs nothing of its own — it is a container, and what
matters is the signed and stapled app within.

There is a second identity, **Developer ID Installer**, which signs a `.pkg`.
The release does not ship one, so it is not needed. If a `.pkg` is ever wanted —
for installing across a fleet, which is the only thing it is better at — it needs
that certificate issued as well, because Gatekeeper will not install an unsigned
package. See `packaging/macos/package.sh`.

## Exporting it

On macOS 15 **Keychain Access** is no longer in Utilities. It lives at
`/System/Library/CoreServices/Applications/Keychain Access.app`, and searching
for it offers the Passwords app instead, which does not show certificates at all:

```bash
open "/System/Library/CoreServices/Applications/Keychain Access.app"
```

Under *My Certificates*, find the certificate and **expand the row**. There has
to be a private key underneath; without it you have the half that identifies and
not the half that signs, and it will import cleanly and sign nothing.

Right-click the certificate — not the key — *Export*, choose `.p12`, and set a
password. macOS then asks for a second password, which is your login password
and only confirms the export is you. The first one becomes a secret of its own:
it is what protects the key in transit.

To check what came out:

```bash
openssl pkcs12 -in Developer-ID-Application.p12 -info -noout -legacy
```

`Shrouded Keybag` in the output means the private key is in there. `-legacy` is
required because Keychain Access still exports with RC2, which OpenSSL 3 moved
out of its default provider; without the flag it fails on the algorithm and not
on anything wrong with the file.

Then:

```bash
base64 -i Developer-ID-Application.p12 | pbcopy
```

base64 because a GitHub secret is a string and a `.p12` is not text.

## The provisioning profiles

Two, matching the names the project asks for: `Caelo` and `Caelo SystemExtension`.
They are already on your machine if the build works locally:

```bash
ls ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/
```

Identify the right ones and put both into a zip, then encode that:

```bash
zip -j caelo-profiles.zip <the two>.provisionprofile
base64 -i caelo-profiles.zip | pbcopy
```

If they are not there, they come from the Developer portal: Developer ID
profiles for the app and the extension, the extension's carrying the
`com.apple.developer.networking.networkextension` capability.

## Notarisation

Use an **App Store Connect API key**, not an Apple ID and app-specific password.
The key carries only the authority to notarise and can be revoked on its own,
without touching the account or anyone's sign-in.

App Store Connect → *Users and Access* → *Integrations* → *App Store Connect API*
→ *Team Keys* → generate a key. **Developer** access is enough; **App Manager**
also works, so an existing key made for uploading builds can be reused. You get a
`.p8` file, downloadable exactly once, plus a Key ID and an Issuer ID.

```bash
base64 -i AuthKey_XXXXXXXX.p8 | pbcopy
```

## Setting the secrets

Six of them. Read from a file rather than typed as an argument, because an
argument is visible in the process list to everything else on the machine:

```bash
gh secret set MACOS_CERTIFICATE_P12 --repo TeamGDB/Caelo < <(base64 -i Developer-ID-Application.p12)
gh secret set MACOS_CERTIFICATE_PASSWORD --repo TeamGDB/Caelo
gh secret set MACOS_PROVISIONING_PROFILES --repo TeamGDB/Caelo < <(base64 -i caelo-profiles.zip)
gh secret set MACOS_NOTARY_KEY --repo TeamGDB/Caelo < <(base64 -i AuthKey_XXXXXXXX.p8)
gh secret set MACOS_NOTARY_KEY_ID --repo TeamGDB/Caelo
gh secret set MACOS_NOTARY_ISSUER --repo TeamGDB/Caelo
```

The three without redirection will prompt, and what you type is not echoed.

Afterwards, delete the exported `.p12`. It is now in the two places that matter,
your keychain and the repository's secrets, and a third copy on the Desktop is
the one that ends up somewhere else.

Keep the `.p8`. Apple lets it be downloaded exactly once, and local notarisation
uses it too.

## What the pipeline then does

`scripts/ci-apple-signing.sh setup macos` builds a keychain inside `RUNNER_TEMP`,
imports the identities, installs the profiles, and prints the identity names —
names only, because the failure that catches, a Development certificate exported
where a Developer ID was meant, is otherwise found days later by someone reading
a signature.

The app is notarised and stapled before it is wrapped, so the copy inside the
disk image carries its own ticket and validates on a machine that is offline the
first time it opens it. The disk image is then notarised in turn.

The last check mounts the disk image and runs `spctl --assess`, which is the
question a stranger's Mac actually asks. `stapler validate` alone is not enough:
it confirms a ticket is attached, not that Gatekeeper accepts what it is attached
to.

`teardown` runs whether the job passed or failed, and the keychain lives in
`RUNNER_TEMP` so it goes away with the runner even if teardown never runs at all.

## When they expire

Developer ID certificates last five years and the API key lasts until revoked.
The Developer ID provisioning profiles in use here run to 2044, which is long
enough not to be the thing that breaks — unlike the Development profiles people
are used to, which expire in a year.

So the certificate is what will lapse first, and it will do so silently: the
pipeline simply starts failing the way it did in #55. Check the date with

```bash
security find-certificate -c "Developer ID Application" -p |
  openssl x509 -noout -enddate
```

and put it in a calendar rather than meeting it as a surprise.

## iOS: TestFlight

Not finished. The pipeline builds the archive on every run and stops there until
the material below exists; the state of it is #78.

iOS signs manually against named profiles, the way macOS does, and for the same
reason: automatic signing wants an Xcode logged into an Apple ID, which a hosted
runner is not. The Release configuration of both targets names
`Caelo App Store` and `Caelo Tunnel App Store`; Debug and Profile are left
automatic, so `flutter run` on a device is unaffected.

Signing at **export** was tried first and does not work, which is worth knowing
before anyone tries it again. Entitlements are compiled in at the moment of
signing, so an archive built with `--no-codesign` carries none, and exporting it
produces an app with only the four Apple adds by default. Everything reports
success — `EXPORT SUCCEEDED`, both bundles signed by the distribution
certificate — and App Store Connect rejects the upload:

```
ERROR: Missing Entitlement. The bundle 'Runner.app' is missing entitlement
'com.apple.developer.networking.networkextension'. (90525)
```

An app that could not have run a tunnel, signed perfectly. Both the build and
the upload now check the entitlements themselves rather than waiting to be told.

On a machine with no certificate, `./scripts/build-ios.sh archive-unsigned`
still proves the thing compiles, and produces nothing shippable.

### Two things have to be made by hand

**An Apple Distribution certificate.** Not the cloud-managed one Xcode created —
that one has no private key on this machine, which is the whole point of it, and
a key that cannot be exported cannot be given to a runner. Generate a CSR
locally, as for Developer ID above, and export the result as a `.p12`.

**Two provisioning profiles, manually managed**, for `team.gdb.caelo` and
`team.gdb.caelo.PacketTunnel`. The ones Xcode manages for itself will not do,
whatever they are named: exporting against one fails with

```
Provisioning profile "..." is Xcode managed, but signing settings
require a manually managed profile.
```

on Xcode 16 and 26 alike. Name them `Caelo App Store` and
`Caelo Tunnel App Store`, or set `IOS_PROFILE_APP` and `IOS_PROFILE_TUNNEL` as
repository variables to whatever you did name them.

### The secrets

```bash
gh secret set IOS_CERTIFICATE_P12 --repo TeamGDB/Caelo < <(base64 -i Apple-Distribution.p12)
gh secret set IOS_CERTIFICATE_PASSWORD --repo TeamGDB/Caelo
gh secret set IOS_PROVISIONING_PROFILES --repo TeamGDB/Caelo < <(base64 -i caelo-ios-profiles.zip)
gh secret set IOS_ASC_KEY --repo TeamGDB/Caelo < <(base64 -i AuthKey_XXXXXXXX.p8)
gh secret set IOS_ASC_KEY_ID --repo TeamGDB/Caelo
gh secret set IOS_ASC_ISSUER --repo TeamGDB/Caelo
```

The App Store Connect key can be the same one that notarises macOS. App Manager
is enough authority to upload; it does not need Admin.

**Check the paths before running these.** `base64 -i` on a file that is not
there prints its complaint to stderr and nothing to stdout, and `gh secret set`
stores the nothing — leaving a secret that exists, has a fresh timestamp, and is
empty. That happened on the first attempt here and cost a pipeline run to find.
The job prints the size of each secret at the start, which is where to look:

```
IOS_CERTIFICATE_P12          0 characters
```

### Which Xcode

App Store Connect rejects a build made against an SDK it considers old, and a
runner's default Xcode is not always the newest it has installed. The job picks
the highest version present and fails immediately if that is below 26 — which is
cheaper than being told after the upload. The same applies locally:

```bash
DEVELOPER_DIR=/Applications/Xcode-26.3.app/Contents/Developer ./scripts/build-ios.sh archive
```

Check what you actually built against, since this is silent when it is wrong:

```bash
plutil -extract DTSDKName raw \
  build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist
```

### Export compliance

`ITSAppUsesNonExemptEncryption` is not in `ios/Runner/Info.plist` yet, and until
it is, every upload stops and waits for a person to answer Apple's export
questions — which is the one thing that keeps this from being automatic. The
value is a legal statement rather than a build setting, so it is in #78 and not
decided here.

## Windows: deliberately unsigned, for now

Decided 15 August 2026, while the project has no users to speak of.

Windows ships without an Authenticode certificate. This is a decision, not an
oversight, and the reasoning should be re-read before anyone spends money
reversing it.

**It works.** Unlike macOS, where an unsigned build cannot load its system
extension and therefore cannot tunnel at all, an unsigned Windows build is fully
functional: Wintun carries its own Microsoft-attested driver signature, so the
tunnel comes up regardless of who signed the installer around it. What is lost is
trust, not capability.

**What people see.** SmartScreen's "Windows protected your PC" on first run, a
browser warning on download, and — worst of the three — "Publisher: unknown" on
the elevation prompt, which Caelo needs because it installs a privileged service.
An application that circumvents censorship, asks for administrator rights, and
cannot say who wrote it is asking for exactly the habit that malware relies on.

**Why not simply buy one.** Three reasons, in order of weight:

1. There is nothing worth signing yet. #22 is open: the Windows tunnel has never
   run on a real machine. A certificate bought today would spend its first months
   accruing SmartScreen reputation for a binary that may not work.
2. Since 2023 the private key must live on hardware or in a cloud signing
   service, so a certificate cannot simply be handed to a hosted runner. Either a
   self-hosted machine with the token, or a service such as Azure Trusted
   Signing, which has its own eligibility and geography constraints.
3. An individual, as opposed to a company, can hold only an OV certificate, and
   the publisher line then reads as a person's name rather than an organisation.

For reference, AmneziaVPN — same space, established, with an Estonian company
behind it — signs by subject name from the Windows certificate store and does not
sign on its public runners either. The constraint is structural, not a matter of
diligence.

**What is done instead.** Every artifact is listed in `latest.json` with its
SHA-256 and an Ed25519 signature, so a download can be checked without
Authenticode, and the Windows updater (#45) verifies that signature rather than
relying on the operating system's opinion. The release notes say plainly that
Windows will warn and why, rather than telling anyone to click through warnings.

**When to revisit.** When there are enough users for the drop-off at the
SmartScreen dialog to be worth measuring, and after #22 proves there is something
to sign. Note that reputation accrues per certificate and never starts without
one — this does not improve on its own with time.

## Android

One keystore, held outside the repository, and irrecoverable in the way that
matters: Android refuses an update signed with a different key than the installed
copy. Lose it and every existing installation is stranded — uninstall and
reinstall, losing whatever the app was holding, with nothing we can do from our
side. It is not reissued by anybody, exactly like the appcast key in
`docs/updates.md`.

Generate it once. The command prompts for a password and asks for a name and
organisation; those end up in the certificate but nobody reads them:

```bash
keytool -genkeypair -v -keystore ~/.caelo-dev/caelo-release.jks -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 10000 -alias caelo
```

PKCS#12 rather than the older JKS, which keytool itself now warns about. One
password covers the store and the key.

Then four secrets:

```bash
gh secret set ANDROID_KEYSTORE --repo TeamGDB/Caelo < <(base64 -i ~/.caelo-dev/caelo-release.jks)
gh secret set ANDROID_KEYSTORE_PASSWORD --repo TeamGDB/Caelo
gh secret set ANDROID_KEY_PASSWORD --repo TeamGDB/Caelo
echo -n caelo | gh secret set ANDROID_KEY_ALIAS --repo TeamGDB/Caelo
```

Back it up the same way as the appcast key, and to the same standard: a copy that
survives this machine, and somebody else able to reach it.

### Building without it

A clone with no keystore still builds. `android/app/build.gradle.kts` falls back
to the debug key and says so in the build output, because an open-source project
a stranger cannot build is not really open.

The release workflow has no such fallback and fails outright when the secret is
absent. The danger was never building a debug-signed APK — it is publishing one,
and the difference is invisible until somebody tries to update. So the workflow
also runs `apksigner` afterwards and refuses to go on if the certificate reads as
`Android Debug`, or if it cannot read a certificate at all.

### For local release builds

Rather than exporting four variables, put them in `android/key.properties`, which
is already in `android/.gitignore`:

```properties
storeFile=/Users/you/.caelo-dev/caelo-release.jks
storePassword=...
keyAlias=caelo
keyPassword=...
```
