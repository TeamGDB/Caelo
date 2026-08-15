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

`scripts/ci-macos-signing.sh setup` builds a keychain inside `RUNNER_TEMP`,
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
