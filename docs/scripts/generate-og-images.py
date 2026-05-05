#!/usr/bin/env python3
"""Generate the per-locale Open Graph cards for the marketing site.

Outputs:
  docs/assets/og-en.png  (1200x630, ≤ 300 KB)
  docs/assets/og-nl.png  (1200x630, ≤ 300 KB)

Composition:
  - Solid green wash (#34A853, BrandTint.green — see AGENTS.md → "App Icon
    Variants"). Picks the "all clear" tint because the marketing message is
    everyday peace of mind.
  - Brand mark (docs/assets/icons/iOS.png) at 120x120 in the top-left corner
    with 60px padding.
  - Two-line headline left-aligned under the icon: "GluWink" plus a locale
    subtitle ("Diabetes status everywhere" / "Diabetes-status overal").
  - 01_greenShield phone screenshot for the locale, occupying the right ~40 %
    of the canvas with 40 px vertical padding, behind a soft drop shadow.

Idempotent: re-running overwrites the PNGs deterministically. Wired into the
root Makefile via `make docs-og-images`.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
ASSETS = DOCS / "assets"
ICON_PATH = ASSETS / "icons" / "iOS.png"

CANVAS = (1200, 630)
BG_COLOR = (52, 168, 83)  # #34A853 — BrandTint.green
TEXT_COLOR = (255, 255, 255)

ICON_SIZE = 120
ICON_PADDING = 60
PHONE_RIGHT_PADDING = 60
PHONE_VERT_PADDING = 40

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNS.ttf",
]


@dataclass(frozen=True)
class Locale:
    code: str          # "en-US" / "nl-NL"
    out_name: str      # "og-en.png"
    title: str
    subtitle: str


LOCALES = [
    Locale("en-US", "og-en.png", "GluWink", "Diabetes status everywhere"),
    Locale("nl-NL", "og-nl.png", "GluWink", "Diabetes-status overal"),
]


def load_font(size: int) -> ImageFont.ImageFont:
    """Try the macOS system fonts in order; fall back to Pillow's default."""
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    print("WARN: no system font usable, falling back to default", file=sys.stderr)
    return ImageFont.load_default()


def composite_phone(canvas: Image.Image, phone_path: Path) -> None:
    """Resize the phone screenshot to fit vertically with padding and paste it
    on the right edge of the canvas with a soft drop shadow."""
    phone = Image.open(phone_path).convert("RGBA")
    target_h = CANVAS[1] - 2 * PHONE_VERT_PADDING
    scale = target_h / phone.height
    target_w = int(phone.width * scale)
    phone = phone.resize((target_w, target_h), Image.LANCZOS)

    x = CANVAS[0] - target_w - PHONE_RIGHT_PADDING
    y = PHONE_VERT_PADDING

    # Soft drop shadow: render the alpha into a black layer, blur, paste.
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_layer = Image.new("RGBA", phone.size, (0, 0, 0, 90))
    shadow_layer.putalpha(phone.split()[3].point(lambda a: int(a * 0.45)))
    shadow.paste(shadow_layer, (x + 12, y + 18), shadow_layer)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=18))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(phone, (x, y))


def composite_icon(canvas: Image.Image) -> None:
    icon = Image.open(ICON_PATH).convert("RGBA")
    icon = icon.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
    canvas.alpha_composite(icon, (ICON_PADDING, ICON_PADDING))


def draw_headline(canvas: Image.Image, locale: Locale) -> None:
    draw = ImageDraw.Draw(canvas)
    title_font = load_font(96)
    subtitle_font = load_font(48)

    # Place the title block roughly under the icon, in the left ~55 % of the
    # canvas, vertically centred around the canvas midline.
    x = ICON_PADDING
    title_h = title_font.getbbox(locale.title)[3] - title_font.getbbox(locale.title)[1]
    subtitle_h = subtitle_font.getbbox(locale.subtitle)[3] - subtitle_font.getbbox(locale.subtitle)[1]
    gap = 24
    block_h = title_h + gap + subtitle_h
    y = (CANVAS[1] - block_h) // 2

    draw.text((x, y), locale.title, font=title_font, fill=TEXT_COLOR)
    draw.text((x, y + title_h + gap), locale.subtitle, font=subtitle_font, fill=TEXT_COLOR)


def render(locale: Locale) -> Path:
    canvas = Image.new("RGBA", CANVAS, BG_COLOR + (255,))
    phone_path = ASSETS / "screenshots" / locale.code / "01_greenShield.png"
    composite_phone(canvas, phone_path)
    composite_icon(canvas)
    draw_headline(canvas, locale)

    out_path = ASSETS / locale.out_name
    canvas.convert("RGB").save(out_path, format="PNG", optimize=True)
    return out_path


def main() -> int:
    if not ICON_PATH.exists():
        print(f"ERROR: icon missing at {ICON_PATH}", file=sys.stderr)
        return 1
    for locale in LOCALES:
        out = render(locale)
        size_kb = out.stat().st_size / 1024
        print(f"  {out.relative_to(ROOT)}  ({size_kb:.0f} KB)")
        if size_kb > 300:
            print(f"WARN: {out.name} is {size_kb:.0f} KB (>300 KB target)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
