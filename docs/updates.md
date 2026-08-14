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
  `RELEASE_IS_DRAFT` in `release.yml` gates both the release and the manifest
  from one place — they cannot drift apart.
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

**There is no recovery from losing the private half.** No installed copy could
ever be updated again, because the entire mechanism rests on nothing else being
able to produce a signature they accept. Everyone would have to reinstall by
hand. Treat it like the signing certificate it stands beside.

Until the secret exists the script says so and carries on without signatures, so
that the shape of the manifest is exercised on every run rather than first
attempted on the day it has to work.

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

Set out in full in #51. In short: no identifiers of any kind, an identical
request from every installation, through the tunnel when one is up, and an off
switch that genuinely stops the timer.

A client that contacts a server on a schedule is a client that reports when it is
running and from where. In most software that is a footnote. Here it is the thing
people installed us to avoid.
