#!/usr/bin/env python3
"""Compose the App Store iMessage promo screenshots for the sticker pack.

App Store Connect requires at least one iMessage screenshot per required
device tier whenever the app bundles an iMessage extension (our sticker
pack). There is no on-device "sticker pack screen" worth screenshotting, so
we compose a branded promo image instead — the standard approach for sticker
packs. Outputs, for each locale:

    iOS/fastlane/screenshots/iMessage/<locale>/01_stickers.png  (1242x2688 → IMESSAGE_APP_IPHONE_65)
    iOS/fastlane/screenshots/iMessage/<locale>/02_stickers.png  (2048x2732 → IMESSAGE_APP_IPAD_PRO_3GEN_129)

`deliver`'s loader treats `iMessage/` as a special expandable folder and
buckets each PNG into a display type by pixel dimensions (see
`deliver/lib/deliver/loader.rb` + `app_screenshot.rb`), so the two sizes can
live side by side in one locale folder under distinct filenames.

Composition (proportional to the canvas, so it works for both aspect ratios):
  - Light iOS grouped-background wash (#F2F2F7) — reads as the Messages
    sticker drawer rather than app chrome.
  - Brand mark (icons/iOS.png) + localized title near the top.
  - The three mascot stickers (green / orange / red — the brand traffic
    light) in a row on soft drop shadows.
  - Localized subtitle below.

Run from the repo root (needs Pillow):

    python3 scripts/stickers/generate-imessage-promos.py

Idempotent: re-running overwrites the PNGs deterministically.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ICON_PATH = ROOT / "icons" / "iOS.png"
STICKERPACK = ROOT / "iOS/Stickers/Stickers.xcassets/Sticker Pack.stickerpack"
MASCOTS = [
    STICKERPACK / "Mascot Green.sticker" / "mascot-green.png",
    STICKERPACK / "Mascot Orange.sticker" / "mascot-orange.png",
    STICKERPACK / "Mascot Red.sticker" / "mascot-red.png",
]
OUT_ROOT = ROOT / "iOS/fastlane/screenshots/iMessage"

BG_COLOR = (242, 242, 247)        # #F2F2F7 — iOS grouped background
TITLE_COLOR = (28, 28, 30)        # #1C1C1E
SUBTITLE_COLOR = (110, 110, 115)  # #6E6E73

# (filename, width, height) — fastlane buckets by dimensions, names are free.
DEVICES = [
    ("01_stickers.png", 1242, 2688),  # IMESSAGE_APP_IPHONE_65
    ("02_stickers.png", 2048, 2732),  # IMESSAGE_APP_IPAD_PRO_3GEN_129
]

BOLD_FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNS.ttf",
]
REGULAR_FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNS.ttf",
]


@dataclass(frozen=True)
class Locale:
    code: str
    title: str
    subtitle: str


LOCALES = [
    Locale("en-US", "GluWink Stickers", "The GluWink mascot, right in Messages."),
    Locale("nl-NL", "GluWink-stickers", "De GluWink-mascotte, direct in Berichten."),
]


def load_font(candidates: list[str], size: int) -> ImageFont.FreeTypeFont:
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    print("WARN: no system font usable, falling back to default", file=sys.stderr)
    return ImageFont.load_default()


def text_size(draw: ImageDraw.ImageDraw, text: str, font) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=font)
    return box[2] - box[0], box[3] - box[1]


def wrap(draw: ImageDraw.ImageDraw, text: str, font, max_w: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for word in words:
        trial = f"{cur} {word}".strip()
        if text_size(draw, trial, font)[0] <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def drop_shadow(canvas: Image.Image, tile: Image.Image, x: int, y: int) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer = Image.new("RGBA", tile.size, (0, 0, 0, 70))
    layer.putalpha(tile.split()[3].point(lambda a: int(a * 0.35)))
    offset = max(6, tile.width // 28)
    shadow.paste(layer, (x + offset // 2, y + offset), layer)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(8, tile.width // 18)))
    canvas.alpha_composite(shadow)


def render(locale: Locale, out_name: str, w: int, h: int) -> Path:
    canvas = Image.new("RGBA", (w, h), BG_COLOR + (255,))
    draw = ImageDraw.Draw(canvas)

    side = round(w * 0.085)
    inner_w = w - 2 * side

    # --- Brand mark ---
    icon_size = round(w * 0.16)
    icon = Image.open(ICON_PATH).convert("RGBA").resize((icon_size, icon_size), Image.LANCZOS)
    icon_x = (w - icon_size) // 2
    icon_y = round(h * 0.085)
    canvas.alpha_composite(icon, (icon_x, icon_y))

    # --- Title ---
    title_font = load_font(BOLD_FONT_CANDIDATES, round(w * 0.062))
    tw, th = text_size(draw, locale.title, title_font)
    title_y = icon_y + icon_size + round(h * 0.025)
    draw.text(((w - tw) // 2, title_y), locale.title, font=title_font, fill=TITLE_COLOR)

    # --- Mascot row ---
    gap = round(w * 0.045)
    tile_w = (inner_w - 2 * gap) // 3
    row_y = round(h * 0.40)
    for i, mascot_path in enumerate(MASCOTS):
        tile = Image.open(mascot_path).convert("RGBA").resize((tile_w, tile_w), Image.LANCZOS)
        x = side + i * (tile_w + gap)
        drop_shadow(canvas, tile, x, row_y)
        canvas.alpha_composite(tile, (x, row_y))

    # --- Subtitle ---
    subtitle_font = load_font(REGULAR_FONT_CANDIDATES, round(w * 0.038))
    lines = wrap(draw, locale.subtitle, subtitle_font, inner_w)
    line_h = text_size(draw, "Ag", subtitle_font)[1]
    line_gap = round(line_h * 0.4)
    sub_y = row_y + tile_w + round(h * 0.05)
    for line in lines:
        lw, _ = text_size(draw, line, subtitle_font)
        draw.text(((w - lw) // 2, sub_y), line, font=subtitle_font, fill=SUBTITLE_COLOR)
        sub_y += line_h + line_gap

    out_dir = OUT_ROOT / locale.code
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / out_name
    canvas.convert("RGB").save(out_path, format="PNG", optimize=True)
    return out_path


def main() -> int:
    if not ICON_PATH.exists():
        print(f"ERROR: brand icon missing at {ICON_PATH}", file=sys.stderr)
        return 1
    for mascot in MASCOTS:
        if not mascot.exists():
            print(f"ERROR: mascot missing at {mascot}", file=sys.stderr)
            return 1
    for locale in LOCALES:
        for out_name, w, h in DEVICES:
            out = render(locale, out_name, w, h)
            print(f"  {out.relative_to(ROOT)}  ({w}x{h})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
