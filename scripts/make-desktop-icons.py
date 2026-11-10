#!/usr/bin/env python3
"""Desktop icons from the square brand artwork: rounded corners, transparent outside.

The artwork (macOS/iOS 1024 px) is full-bleed: macOS and iOS round it themselves,
Windows and Linux show whatever the file contains — which was a plain square on
Linux and Flutter's default logo on Windows. Run from the repository root:

    python3 scripts/make-desktop-icons.py

Needs Pillow. Writes windows/runner/resources/app_icon.ico, packaging/linux/caelo.png
and docs/caelo.png (the welcome screen and the X11 window icon).
"""
from PIL import Image, ImageDraw

SOURCE = "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
RADIUS = 0.225  # of the side, close to the platforms' own app-icon rounding
SS = 4          # supersampling for smooth corners


def rounded(size: int, margin: float) -> Image.Image:
    art = Image.open(SOURCE).convert("RGBA")
    big = size * SS
    inner = round(big * (1 - 2 * margin))
    offset = (big - inner) // 2
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (offset, offset, offset + inner - 1, offset + inner - 1), radius=round(inner * RADIUS), fill=255)
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    canvas.paste(art.resize((inner, inner), Image.LANCZOS), (offset, offset))
    canvas.putalpha(mask)
    return canvas.resize((size, size), Image.LANCZOS)


# A little air around it on the desktop, as system icons have; none in the app,
# where the welcome screen already frames it.
desktop = rounded(1024, margin=0.04)
desktop.resize((512, 512), Image.LANCZOS).save("packaging/linux/caelo.png", optimize=True)
desktop.save("windows/runner/resources/app_icon.ico",
             sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)])
rounded(320, margin=0).save("docs/caelo.png", optimize=True)
