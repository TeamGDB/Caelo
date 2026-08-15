# Updates

How an installed copy of Caelo finds out that a newer one exists, and what it is
allowed to do about it.

This describes the manifest — the contract between the release pipeline and every
updater. The updaters themselves are separate work: Sparkle on macOS (#44),
WinSparkle on Windows (#45), the sideload updater on Android (#48). Linux does
not get an updater at all, and the reason is below.

## Two files, one truth

`scripts/make-appcast.sh` produces both in a single pass:

| File | Read by |
| --- | --- |
| `appcast.xml` | Sparkle on macOS, WinSparkle on Windows |
| `latest.json` | the Android updater, and the "there is a newer version" notice on Linux |

They carry the same facts. They are generated together rather than separately
because the failure they are guarding against is the two disagreeing about which
version is current, which would send half the installed base to one build and
half to another with nothing in the logs to explain it.

Both live on GitHub Pages. The artifacts they point at live on GitHub Releases.

## Why not the API

The obvious implementation is to ask `api.github.com` for the latest release.
Do not.

Unauthenticated it allows sixty requests an hour **per IP address**, and Caelo
checks for updates through its own tunnel. Everybody sharing an exit node
therefore shares one quota: the first few get an answer and the rest get a 403.
The busier a node, the more broken updates become on it — which is exactly
backwards.

Fetching a static file from Pages has no such limit, and reveals less: a CDN
request is far weaker evidence of who asked than an API call is.

Two more properties of the host, written down so they are not rediscovered:

- **A draft release does not serve its assets.** A manifest naming a draft's
  files offers an update that 404s for everyone who accepts it. This is why
  the gate step in `release.yml` decides once, for both the release and the
  manifest, so they cannot drift apart. It combines `PUBLISH_TAGGED_RELEASES`
  with "is this a tag": a dispatch run is always a draft, which is what makes it
  safe to look at a release before there is one to make.
- **A release asset can be replaced under the same name.** The URL proves
  nothing about the bytes, which is fine, because the signature does.

## Signatures

Every enclosure carries an Ed25519 signature over the file's bytes, base64
encoded — what Sparkle calls `sparkle:edSignature`, and what `latest.json` calls
`ed25519`.

This is **not** the code-signing identity from #42, and the difference matters.
The code signature tells the operating system it may run the file. This one tells
an already-installed copy of Caelo that the file came from our release pipeline.
They are issued by different authorities, they fail independently, and either one
failing must stop the update.

Because verification is on the payload rather than the transport, the host does
not have to be trusted. That is what will make mirrors cheap to add later; we are
not adding them now, but nothing here forecloses it.

### The key

```bash
openssl genpkey -algorithm ed25519 -out caelo-appcast.pem
openssl pkey -in caelo-appcast.pem -pubout -outform DER | tail -c 32 | base64
```

The private half becomes the `APPCAST_ED25519_KEY` secret and exists nowhere
else. The public half is compiled into the app — `SUPublicEDKey` in the macOS
`Info.plist`, and the equivalent constants on the other platforms.

### Two keys, from the first release

The app trusts a **list** of public keys, not one, and it has to from the very
first release. This is the part that cannot be added later: a single key cannot
be replaced, because putting a second one into the app takes an update, and
shipping an update takes the key you no longer have.

So there are two — an active key that signs releases, and a spare that signs
nothing until it must. They live in different places; a spare stored beside the
key it stands in for is decoration.

Rotating, when the active key is lost or has been somewhere it should not:

1. Sign the next release with the spare — every existing installation already
   accepts it.
2. In that same release, change `trustedKeys` in `lib/core/update_check.dart`:
   drop the lost key, keep the spare as the new active one, add a fresh spare.
3. Once enough people have taken that update, the lost key is inert.

Step 2 is why the list is in the app rather than fetched: a list that arrived
over the network could be replaced by whoever replaced the manifest.

**macOS needs none of this**, which is worth knowing before panicking. Sparkle
falls back to Developer ID with a matching team ID when its own signature check
fails — deliberately, so that a key can be rotated — and Apple reissues that
certificate. Windows has no equivalent, because those builds carry no
Authenticode signature at all, so there this list is the only thing that makes a
lost key survivable.

**Still, losing both is final.** No installed copy could be updated again, and
everyone would have to reinstall by hand. Treat them like the signing
certificate they stand beside, and keep them apart.

Until the secret exists the script says so and carries on without signatures, so
that the shape of the manifest is exercised on every run rather than first
attempted on the day it has to work.

## The Linux repositories

Built by `scripts/make-repo.sh` in the same job as the manifest, and served from
the same site: `deb/` for apt, `rpm/` for dnf.

**One version, not a history.** `apt upgrade` compares what is on offer against
what is installed and does not care that only one version is available, so
carrying old releases would buy nothing and cost the whole question of when to
prune — with Pages holding a soft gigabyte and these packages running to tens of
megabytes each. Somebody who wants an older version has the releases page.

**The packages live in the Pages tree.** They cannot be pointed at from it: apt
resolves the `Filename` field relative to the archive root and cannot be sent
elsewhere, which is also why this cannot simply reference the release assets.

**Both `InRelease` and `Release.gpg`.** Modern apt fetches the first, older
releases still look for the second, and serving only one turns a working machine
into a broken one on upgrade day.

### The archive key

Separate from the appcast key and from anything Apple issued — this one signs
package metadata and nothing else.

```bash
gpg --batch --quick-generate-key "Caelo Archive <you@example.com>" ed25519 sign never
gpg --armor --export-secret-keys "Caelo Archive" | gh secret set REPO_GPG_KEY --repo TeamGDB/Caelo
```

Without the secret the repositories are built unsigned, and apt refuses them.
That is the right failure: an unsigned package repository serving a VPN client is
worth less than none.

Losing this one is survivable, unlike the appcast key — a new key can be shipped
in a package update, since the package itself is what installs the keyring.

### How a machine ends up subscribed

`packaging/linux/postinst.sh` writes the source list and the keyring on first
install, so a `.deb` downloaded by hand from the releases page turns into a
machine that upgrades by the ordinary route. The key goes to
`/usr/share/keyrings` and is named with `signed-by` rather than added to the
global trusted set: `apt-key` would let it sign anything on the machine.

`postrm.sh` removes both on purge. A repository left configured for software that
is gone means a machine still fetching our metadata indefinitely, which is both
rude and a signal we have no business collecting.

## What Linux gets instead

No updater. `/opt/caelo`, the binaries under `/usr` and the units in
`packaging/linux/systemd/` belong to the package manager, and an application that
overwrites them from underneath itself breaks the next `apt upgrade` and leaves a
machine nobody can reason about.

`apt upgrade` and `dnf upgrade` already do this job correctly; they just have
nothing to talk to yet (#46). The AppImage is the exception — a single file the
user owns, installing nothing — and it updates itself through zsync (#47).

So on Linux `latest.json` exists only to support a line of text saying a newer
version is available, and the command to get it. No download button.

## What the check may not do

A client that contacts a server on a schedule is a client that reports when it is
running and from where. In most software that is a footnote. Here it is the thing
people installed us to avoid, so these are properties of the feature rather than
a hardening pass over it. `lib/core/update_check.dart` holds them and
`test/update_check_test.dart` pins them.

**Nothing identifies the installation.** No identifier, no query string, no
header that varies. Two copies on the same platform send byte-identical requests,
which is what makes the request worthless as a beacon rather than merely small.

**The version is not sent.** It is the obvious design — the server could then
answer "you are current" in a line — and it is rejected, because a request
carrying a version sorts installations into groups for anyone counting. The whole
manifest is fetched and the comparison happens on the device.

**Not the GitHub API.** Sixty unauthenticated requests an hour per IP, and this
check goes through the tunnel, so everyone behind one exit node would share a
quota. The busier the node, the more broken updates would become.

**Through the tunnel when there is one.** Where the platform routes the whole
machine, this happens by itself. Where it does not — the in-process tunnel on a
Linux box with no privileged service — the caller passes a fetch that goes
through it.

**The switch stops the request, not the result.** Turning checks off in Settings
means nothing is sent. A check that fetched and then discarded would still have
announced that this copy is running, which is the whole thing being avoided.

**Checking is not downloading.** The check decides whether something newer
exists. Fetching it is a separate act somebody agrees to: it is large, and their
connection may be metered.

The remaining item on #51 is a packet capture proving the second-to-last point on
a real Linux machine with the in-process tunnel up. It cannot be done from a Mac
and has not been done.
