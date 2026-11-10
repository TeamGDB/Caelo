# CaeloFlags.ttf

Country flags for Windows, which has none of its own (#168): Segoe UI Emoji leaves
the flag sequences out, so a flag there comes out as two letters.

- **From:** `Twemoji.Mozilla.ttf`, release
  [v0.7.0](https://github.com/mozilla/twemoji-colr/releases/tag/v0.7.0) of
  [mozilla/twemoji-colr](https://github.com/mozilla/twemoji-colr) (COLR/CPAL colour font).
- **Artwork:** [Twemoji](https://github.com/twitter/twemoji), © Twitter, Inc and other
  contributors, licensed under [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- **Font build:** © Mozilla Foundation, [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0).
- **Changed:** cut down to the regional indicators U+1F1E6–U+1F1FF and the ligatures that
  join a pair of them into a flag; nothing redrawn. The font's own name is unchanged.

To cut it again (fontTools 4.55.3):

```sh
pyftsubset Twemoji.Mozilla.ttf --unicodes=U+1F1E6-1F1FF --layout-features='*' \
  --name-IDs='*' --notdef-outline --output-file=CaeloFlags.ttf
```

`test/flag_font_test.dart` checks the result: colour tables, the ligatures, all 26
letters, the size.
