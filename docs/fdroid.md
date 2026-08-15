# F-Droid

The natural home for a GPLv3 VPN client, and the one channel that solves updates
without us writing an updater: their build server rebuilds from our tag and their
client installs the result. For everyone who will not touch Play, this is how
Caelo arrives.

It also costs nothing per release once it works, because F-Droid signs what it
builds itself. Our release keystore never leaves us.

## Nothing here blocks inclusion

Checked rather than assumed:

- **No Google services.** Nothing from `com.google`, no Firebase, no
  `play-services`, no GMS of any kind in the Android build.
- **No proprietary binaries.** The `wintun.pin` in `packaging/windows` names a
  Windows driver that never reaches an APK — worth saying out loud in the
  submission, because a reviewer scanning the tree will find it.
- **Dependencies** are `cupertino_icons`, `ffi`, `file_selector`,
  `path_provider` and `share_plus`, all first-party Flutter packages under
  BSD-3-Clause, plus AmneziaWG (MIT) and sing-box in the core. See
  `ATTRIBUTION.md`.
- **No anti-features** apply. Caelo has no advertising, no tracking, no
  non-free network services and no upstream non-free dependencies.

## What F-Droid reads from this repository

`fastlane/metadata/android/<locale>/` — title, descriptions and per-build
changelogs, in English and Russian. F-Droid picks these up automatically; they do
not need to be duplicated into the recipe.

Changelogs are named for the **build number**, not the version, because that is
what `versionCode` carries: `3.txt` is 0.1.0, `4.txt` is 0.1.1.

## The recipe

Submitted as `metadata/team.gdb.caelo.yml` to
[fdroiddata](https://gitlab.com/fdroid/fdroiddata), not kept here — it belongs to
their repository and would go stale in ours.

```yaml
Categories:
  - Internet
  - Security
License: GPL-3.0-or-later
SourceCode: https://github.com/TeamGDB/Caelo
IssueTracker: https://github.com/TeamGDB/Caelo/issues
WebSite: https://teamgdb.github.io/Caelo/

RepoType: git
Repo: https://github.com/TeamGDB/Caelo.git

Builds:
  - versionName: 0.1.1
    versionCode: 4
    commit: v0.1.1
    subdir: android/app
    sudo:
      - apt-get update
      - apt-get install -y golang-go
    gradle:
      - yes
    srclibs:
      - flutter@stable
    rm:
      - packaging/windows
    prebuild: sed -i -e '/signingConfig/d' build.gradle.kts
    scanignore:
      - android/app/src/main/jniLibs
    build: |
      export PATH="$$flutter$$/bin:$$PATH"
      cd $$SRC$$ && ./scripts/build-android.sh release

AutoUpdateMode: Version
UpdateCheckMode: Tags ^v[0-9.]+$
CurrentVersion: 0.1.1
CurrentVersionCode: 4
```

Three parts of that are worth understanding rather than copying.

**`scanignore` on `jniLibs`.** The Go core is compiled into `libcaelo.so` per ABI
during the build and lands there. F-Droid's scanner flags binaries in the source
tree; these are build output, which is also why the directory is not committed.

**The `signingConfig` removal.** `android/app/build.gradle.kts` falls back to the
debug key when no release keystore is present, which is right for a person who
cloned the repository and wrong for F-Droid, who sign with their own key. Removing
the line makes the intent explicit rather than relying on a fallback.

**Go from the distribution, not downloaded.** The build server has no network
beyond declared dependencies, so `golang-go` comes from apt. If the version there
falls behind what `core/go.mod` requires, this is the line that breaks, and it
breaks with a message about the language rather than about us.

## Not verified

The recipe has never run. F-Droid's build server is a specific sandbox — a fixed
Debian, no network during the build, a particular Flutter srclib — and none of
that can be reproduced faithfully from a Mac. Expect the first submission to need
one or two rounds with their CI, most likely around the Flutter and Go versions.

What *has* been checked is everything that would make the submission pointless:
the licence, the absence of proprietary components, and that
`scripts/build-android.sh` needs nothing beyond Go, the NDK and Flutter.
