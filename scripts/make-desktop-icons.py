#!/usr/bin/env python3
"""Desktop icons from the square brand artwork: rounded corners, transparent outside.

The artwork (1024 px) is full-bleed, which is right only for iOS: iOS rounds app
icons itself. macOS since Big Sur expects the rounded shape, its margin and its
shadow to be drawn in the file (macOS 26 frames anything else in a grey tile),
and Windows and Linux show whatever the file contains — which was a plain square
everywhere but iOS, and Flutter's default logo on Windows. Run from the
repository root:

    python3 scripts/make-desktop-icons.py

Needs Pillow. Writes windows/runner/resources/app_icon.ico, packaging/linux/caelo.png,
docs/caelo.png (the welcome screen and the X11 window icon) and the macOS AppIcon set.
"""
from PIL import Image, ImageDraw, ImageFilter

# The full-bleed artwork. The iOS copy stays full-bleed and is the source; the
# macOS set is generated from it.
SOURCE = "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
MACOS = "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{}.png"
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

# macOS app-icon grid: an 824 px rounded square centred on a 1024 canvas, with
# the soft drop shadow Apple's template draws under it.
body = rounded(1024, margin=100 / 1024)
shadow_mask = body.getchannel("A").filter(ImageFilter.GaussianBlur(14))
shadow = Image.new("RGBA", body.size, (0, 0, 0, 0))
shadow.putalpha(shadow_mask.point(lambda a: a * 0.32))
mac = Image.new("RGBA", body.size, (0, 0, 0, 0))
mac.alpha_composite(shadow, (0, 12))
mac.alpha_composite(body)
for px in (16, 32, 64, 128, 256, 512, 1024):
    mac.resize((px, px), Image.LANCZOS).save(MACOS.format(px), optimize=True)
