#!/usr/bin/env bash
#
# Renders the download page from the manifest.
#
#   ./scripts/make-page.sh <pages-dir>
#
# Reads latest.json rather than looking at the artifacts again. The page and the
# manifest then cannot disagree about what exists or what it hashes to, which
# they would within one release of being built from separate passes -- and the
# page is the half a person reads before deciding to trust a download.
set -euo pipefail

PAGES="${1:-pages}"
MANIFEST="$PAGES/latest.json"

[[ -f "$MANIFEST" ]] || { echo "error: no manifest at $MANIFEST" >&2; exit 1; }

VERSION="$(jq -r .version "$MANIFEST")"
BUILD="$(jq -r .build "$MANIFEST")"
NOTES="$(jq -r .notes "$MANIFEST")"

# One row per thing somebody might actually want to download, in the order they
# are likely to want it. Keys that are absent from the manifest are skipped
# rather than rendered as dead links: a platform that failed to build should
# leave a gap, not a promise.
rows() {
  local specs=(
    "macos-dmg|macOS|Disk image, signed and notarised. Drag Caelo into Applications."
    "windows-setup-x64|Windows|Installer for 64-bit Windows. See the note below."
    "linux-appimage-x64|Linux|AppImage — one file, runs anywhere, installs nothing."
    "android-arm64-v8a|Android|Most phones from the last several years."
    "android-universal|Android (any)|Larger, but works on every architecture."
  )

  for spec in "${specs[@]}"; do
    local key="${spec%%|*}" rest="${spec#*|}"
    local name="${rest%%|*}" note="${rest#*|}"

    jq -e --arg k "$key" '.artifacts[$k]' "$MANIFEST" >/dev/null 2>&1 || continue

    local url size sha
    url="$(jq -r --arg k "$key" '.artifacts[$k].url' "$MANIFEST")"
    size="$(jq -r --arg k "$key" '.artifacts[$k].size' "$MANIFEST")"
    sha="$(jq -r --arg k "$key" '.artifacts[$k].sha256' "$MANIFEST")"

    cat <<ROW
      <a class="download" href="$url">
        <span class="platform">$name</span>
        <span class="note">$note</span>
        <span class="meta">$(( size / 1048576 )) MB · <code>${sha:0:16}…</code></span>
      </a>
ROW
  done
}

cat > "$PAGES/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Caelo — a VPN client for subscription links</title>
<meta name="description" content="Free and open-source VPN client. AmneziaWG, no account, no telemetry.">
<style>
  :root {
    --bg: #090B0E; --fg: #F0F2F4; --muted: #8A9099;
    --accent: #54C69A; --line: #1C2127; --surface: #0F1317;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--fg);
    font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  main { max-width: 44rem; margin: 0 auto; padding: 4rem 1.5rem 6rem; }
  h1 { font-size: 3rem; letter-spacing: -0.04em; margin: 0 0 .5rem; }
  h1 .dot { color: var(--accent); }
  .tagline { color: var(--muted); font-size: 1.15rem; margin: 0 0 3rem; }
  h2 {
    font-size: .75rem; text-transform: uppercase; letter-spacing: .12em;
    color: var(--muted); margin: 3rem 0 1rem; font-weight: 600;
  }
  .download {
    display: grid; grid-template-columns: 1fr auto; gap: .15rem 1rem;
    padding: 1rem 1.25rem; margin-bottom: .5rem; text-decoration: none;
    background: var(--surface); border: 1px solid var(--line); border-radius: 12px;
    color: inherit; transition: border-color .15s, transform .15s;
  }
  .download:hover { border-color: var(--accent); transform: translateY(-1px); }
  .platform { font-weight: 600; }
  .note { grid-column: 1; color: var(--muted); font-size: .9rem; }
  .meta {
    grid-column: 2; grid-row: 1 / 3; align-self: center;
    color: var(--muted); font-size: .8rem; text-align: right; white-space: nowrap;
  }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .85em; }
  .warn {
    border-left: 2px solid var(--accent); padding: .25rem 0 .25rem 1rem;
    color: var(--muted); font-size: .95rem;
  }
  .warn strong { color: var(--fg); font-weight: 600; }
  footer {
    margin-top: 4rem; padding-top: 1.5rem; border-top: 1px solid var(--line);
    color: var(--muted); font-size: .875rem;
  }
  a { color: var(--accent); }
  ul { padding-left: 1.1rem; }
  li { margin: .35rem 0; color: var(--muted); }
  li strong { color: var(--fg); font-weight: 600; }
  @media (prefers-color-scheme: light) {
    :root {
      --bg: #D7E7E1; --fg: #0A3735; --muted: #4A6B66;
      --accent: #2FA982; --line: #B9D3CB; --surface: #E6F1ED;
    }
  }
</style>
</head>
<body>
<main>
  <h1>Caelo<span class="dot">.</span></h1>
  <p class="tagline">A VPN client for subscription links. One link, every device, no account.</p>

  <ul>
    <li><strong>No account.</strong> Paste a subscription link and connect. Caelo never asks who you are.</li>
    <li><strong>No telemetry.</strong> The only thing it sends on its own is a request for this page's update manifest, identical from every installation — and you can turn that off.</li>
    <li><strong>AmneziaWG.</strong> WireGuard with traffic shaping, so the handshake does not look like a handshake.</li>
    <li><strong>Free software</strong>, GPL-3.0-or-later, all of it readable.</li>
  </ul>

  <h2>Download — $VERSION (build $BUILD)</h2>
$(rows)

  <h2>About the Windows build</h2>
  <p class="warn">
    <strong>Windows will warn you, and it is right to.</strong>
    The installer carries no commercial code-signing certificate, so SmartScreen
    says the publisher is unknown. Everything works — but do not take that on
    faith. Every file above is listed with its SHA-256 in
    <a href="latest.json">latest.json</a>, so you can check that what you
    downloaded is what we published:
    <br><br>
    <code>certutil -hashfile Caelo-$VERSION-windows-x64-setup.exe SHA256</code>
    <br><br>
    macOS is signed with a Developer ID and notarised by Apple, and opens without
    ceremony.
  </p>

  <h2>Updates</h2>
  <p class="warn">
    macOS updates itself. Linux packages come from your package manager, and the
    AppImage updates in place. Caelo checks by fetching one static file from this
    site; the request carries no identifier, is the same from every installation,
    and goes through the tunnel when one is up. Settings turns it off.
  </p>

  <footer>
    <a href="https://github.com/TeamGDB/Caelo">Source</a> ·
    <a href="$NOTES">Release notes</a> ·
    <a href="https://github.com/TeamGDB/Caelo/blob/main/LICENSE">GPL-3.0-or-later</a> ·
    <a href="appcast.xml">appcast</a>
  </footer>
</main>
</body>
</html>
HTML

echo "==> $PAGES/index.html"
