"""Generate all platform app icons from the masters in assets/icons/.

Run from the repo root:  python tool/generate_icons.py

Sources (checked in, do not delete):
  assets/icons/android/icon-{light,dark}-*.png      full-bleed icon, mark at ~76%
  assets/icons/android-adaptive/adaptive-{fg,bg}-*  adaptive layers, mark at ~51%
                                                    (lands at ~76% after the
                                                    launcher's 72/108dp crop)
  assets/icons/ios/icon-{light,dark}-1024.png
  assets/icons/notification/ic_stat_f95portal-*.png
  assets/icons/svg/*.svg                            editable masters

The full-bleed art is used as-is everywhere the whole image is shown (legacy
mipmaps, iOS, web, favicon, Windows, macOS); only the Android adaptive icon
uses the padded layer set. The dark variant is the Android launcher default.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "icons"

# Ring outer edge spans this fraction of the adaptive layer canvas (mark at
# 51%: (182+11)*2/512*0.51); the monochrome layer is scaled to match so themed
# icons render at the same apparent size as the color icon.
ADAPTIVE_RING_FRACTION = 0.385


def load(rel: str) -> Image.Image:
    return Image.open(SRC / rel).convert("RGBA")


def resized(im: Image.Image, size: int) -> Image.Image:
    return im.resize((size, size), Image.LANCZOS)


def save_png(im: Image.Image, path: Path, mode: str = "RGBA") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if mode == "RGB":
        im = im.convert("RGB")
    im.save(path, "PNG")


# --- monochrome glyph (mirrors assets/icons/svg/ic_stat_f95portal.svg) -----

GLYPH_VIEWBOX = 512.0
ARC_R = 182.0
ARC_STROKE = 30.0
ARC_START_DEG = 118.0
ARC_SWEEP_DEG = math.degrees(720.0 / ARC_R)
F_PATH = [(180, 140), (356, 140), (332, 192), (236, 192), (236, 250),
          (304, 250), (284, 294), (236, 294), (236, 396), (180, 396)]


def render_glyph(size: int, content_scale: float, supersample: int = 4) -> Image.Image:
    """White F95 glyph + arc on transparency, content scaled about the center."""
    ss = size * supersample
    px = ss / GLYPH_VIEWBOX  # svg units -> pixels

    def pt(x: float, y: float) -> tuple[float, float]:
        # scale about the viewbox center, then map to pixels
        return ((x - 256) * content_scale + 256) * px, ((y - 256) * content_scale + 256) * px

    mask = Image.new("L", (ss, ss), 0)
    d = ImageDraw.Draw(mask)

    r_out = (ARC_R + ARC_STROKE / 2) * content_scale * px
    r_in = (ARC_R - ARC_STROKE / 2) * content_scale * px
    c = 256 * px
    end_deg = ARC_START_DEG + ARC_SWEEP_DEG
    d.pieslice([c - r_out, c - r_out, c + r_out, c + r_out], ARC_START_DEG, end_deg, fill=255)
    d.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=0)
    cap_r = ARC_STROKE / 2 * content_scale * px
    for ang in (ARC_START_DEG, end_deg):
        a = math.radians(ang)
        cx = c + ARC_R * content_scale * px * math.cos(a)
        cy = c + ARC_R * content_scale * px * math.sin(a)
        d.ellipse([cx - cap_r, cy - cap_r, cx + cap_r, cy + cap_r], fill=255)

    # F glyph: svg transform translate(268 268) scale(0.86) translate(-268 -268) translate(-12 -12)
    poly = [pt((x - 12 - 268) * 0.86 + 268, (y - 12 - 268) * 0.86 + 268) for x, y in F_PATH]
    d.polygon(poly, fill=255)

    mask = mask.resize((size, size), Image.LANCZOS)
    white = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    white.putalpha(mask)
    return white


# --- platforms --------------------------------------------------------------

DPIS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def android() -> None:
    # dark variant is the launcher default; the light art serves web/desktop
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    legacy = load("android/icon-dark-512.png")
    layers = {
        "ic_launcher_foreground": (load("android-adaptive/adaptive-fg-dark-108.png"),
                                   load("android-adaptive/adaptive-fg-dark-432.png")),
        "ic_launcher_background": (load("android-adaptive/adaptive-bg-dark-108.png"),
                                   load("android-adaptive/adaptive-bg-dark-432.png")),
    }
    mono_scale = ADAPTIVE_RING_FRACTION / ((ARC_R + ARC_STROKE / 2) * 2 / GLYPH_VIEWBOX)

    for dpi, mult in DPIS.items():
        size = round(108 * mult)
        for name, (px108, px432) in layers.items():
            im = {108: px108, 432: px432}.get(size) or resized(px432, size)
            save_png(im, res / f"mipmap-{dpi}" / f"{name}.png")
        save_png(render_glyph(size, mono_scale), res / f"mipmap-{dpi}" / "ic_launcher_monochrome.png")
        save_png(resized(legacy, round(48 * mult)), res / f"mipmap-{dpi}" / "ic_launcher.png")

        stat = SRC / "notification" / f"ic_stat_f95portal-{dpi}-{round(24 * mult)}.png"
        save_png(Image.open(stat), res / f"drawable-{dpi}" / "ic_stat_f95portal.png")

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n'
    )
    colors = res / "values" / "colors.xml"
    if colors.exists():
        colors.unlink()


def ios() -> None:
    iconset = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for old in iconset.glob("Icon-App-*.png"):
        old.unlink()
    save_png(load("ios/icon-light-1024.png"), iconset / "AppIcon-1024.png", mode="RGB")
    save_png(load("ios/icon-dark-1024.png"), iconset / "AppIcon-dark-1024.png", mode="RGB")
    (iconset / "Contents.json").write_text(
        '{\n'
        '  "images" : [\n'
        '    {\n'
        '      "filename" : "AppIcon-1024.png",\n'
        '      "idiom" : "universal",\n'
        '      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n'
        '    },\n'
        '    {\n'
        '      "appearances" : [\n'
        '        {\n'
        '          "appearance" : "luminosity",\n'
        '          "value" : "dark"\n'
        '        }\n'
        '      ],\n'
        '      "filename" : "AppIcon-dark-1024.png",\n'
        '      "idiom" : "universal",\n'
        '      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n'
        '    }\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n'
    )


def web() -> None:
    webdir = ROOT / "web"
    full = load("android/icon-light-512.png")
    save_png(resized(full, 32), webdir / "favicon.png")
    for size in (192, 512):
        save_png(resized(full, size), webdir / "icons" / f"Icon-{size}.png", mode="RGB")
        # mark at 76% keeps the ring inside the maskable 80% safe-zone circle
        save_png(resized(full, size), webdir / "icons" / f"Icon-maskable-{size}.png")


def windows() -> None:
    full = load("android/icon-light-512.png")
    ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    resized(full, 256).save(
        ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    )


def macos() -> None:
    """Apple-style rounded rect with transparent margins (icon fills ~80%)."""
    iconset = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    base = 1024
    inner = round(base * 824 / 1024)
    art = resized(load("ios/icon-light-1024.png"), inner)
    mask = Image.new("L", (inner * 4,) * 2, 0)
    radius = round(inner * 4 * 0.2237)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner * 4 - 1, inner * 4 - 1], radius, fill=255)
    art.putalpha(mask.resize((inner, inner), Image.LANCZOS))
    canvas = Image.new("RGBA", (base, base), (0, 0, 0, 0))
    canvas.paste(art, ((base - inner) // 2,) * 2, art)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_png(resized(canvas, size), iconset / f"app_icon_{size}.png")


if __name__ == "__main__":
    android()
    ios()
    web()
    windows()
    macos()
    print("done")
