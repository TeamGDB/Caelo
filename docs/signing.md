# Signing macOS builds in CI

What the release pipeline needs in order to produce a macOS build that opens on
somebody else's machine, and how to give it to it.

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

## Two certificates, not one

They are different identities and both are needed:

| Certificate | Signs |
| --- | --- |
| Developer ID **Application** | the `.app` and the system extension inside it |
| Developer ID **Installer** | the `.pkg` |

The `.dmg` needs neither — it is a container, and what matters is the signed and
stapled app inside it.

## Exporting them

In **Keychain Access**, find each certificate under *My Certificates* — the row
has to expand to show a private key, otherwise what you have is the certificate
without the half that signs. Right-click, *Export*, choose `.p12`, and set a
password. That password becomes a secret of its own; it is not a formality, it is
what protects the key in transit.

Then, for each:

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
→ generate a key with the **Developer** role. You get a `.p8` file, downloadable
exactly once, plus a Key ID and an Issuer ID.

```bash
base64 -i AuthKey_XXXXXXXX.p8 | pbcopy
```

## Setting the secrets

Eight of them. Read from a file or from the clipboard so no key is ever a
command-line argument, which every other process on the machine can read:

```bash
gh secret set MACOS_CERTIFICATE_P12 --repo TeamGDB/Caelo < <(base64 -i Developer-ID-Application.p12)
gh secret set MACOS_CERTIFICATE_PASSWORD --repo TeamGDB/Caelo
gh secret set MACOS_INSTALLER_P12 --repo TeamGDB/Caelo < <(base64 -i Developer-ID-Installer.p12)
gh secret set MACOS_INSTALLER_PASSWORD --repo TeamGDB/Caelo
gh secret set MACOS_PROVISIONING_PROFILES --repo TeamGDB/Caelo < <(base64 -i caelo-profiles.zip)
gh secret set MACOS_NOTARY_KEY --repo TeamGDB/Caelo < <(base64 -i AuthKey_XXXXXXXX.p8)
gh secret set MACOS_NOTARY_KEY_ID --repo TeamGDB/Caelo
gh secret set MACOS_NOTARY_ISSUER --repo TeamGDB/Caelo
```

The four without redirection will prompt, and what you type is not echoed.

Afterwards, delete the exported `.p12` files and the `.p8`. They are now in two
places that matter — your keychain and the repository's secrets — and a third
copy in `~/Downloads` is the one that ends up somewhere else.

## What the pipeline then does

`scripts/ci-macos-signing.sh setup` builds a keychain inside `RUNNER_TEMP`,
imports the identities, installs the profiles, and prints the identity names —
names only, because the failure that catches, a Development certificate exported
where a Developer ID was meant, is otherwise found days later by someone reading
a signature.

The app is notarised and stapled before it is wrapped, so the copy inside the
disk image carries its own ticket and validates on a machine that is offline the
first time it opens it. The `.dmg` and `.pkg` are then notarised in turn.

The last check mounts the disk image and runs `spctl --assess`, which is the
question a stranger's Mac actually asks. `stapler validate` alone is not enough:
it confirms a ticket is attached, not that Gatekeeper accepts what it is attached
to.

`teardown` runs whether the job passed or failed, and the keychain lives in
`RUNNER_TEMP` so it goes away with the runner even if teardown never runs at all.

## When they expire

Developer ID certificates last five years, provisioning profiles one, and the API
key until revoked. The profile is the one that will lapse first and it will do so
silently — the pipeline will simply start failing the way it did in #55. Worth a
calendar entry rather than a surprise.
