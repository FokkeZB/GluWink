#!/usr/bin/env python3
"""Re-render the iMessage sticker pack's app-icon set and round the sticker
corners.

Run from the repo root:

    python3 iOS/Stickers/scripts/process-assets.py

This is idempotent — re-running it after the master `icons/iOS.png` changes
(or after adding new stickers under `iOS/Stickers/Stickers.xcassets/Sticker
Pack.stickerpack/`) regenerates the affected PNGs in place.

Two passes:

1. ``regen_app_icon`` — re-renders every size in
   ``iMessage App Icon.stickersiconset/`` from ``icons/iOS.png``. The brand
   blue (#4285F4) fills the entire canvas at every aspect ratio so the
   Messages drawer slot doesn't show white pillars next to a square
   letterboxed mascot. The shield artwork itself is fit to the canvas's
   shorter side and centred — matching the visual weight of the square
   1024×1024 home-screen icon.

2. ``round_stickers`` — converts each sticker PNG under
   ``Sticker Pack.stickerpack/`` to RGBA and applies a ~22% corner-radius
   mask (matches the iOS app-icon squircle proportion) so the stickers
   read as friendly rounded tiles instead of hard-edged squares in the
   Messages picker.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

BRAND_BLUE = (66, 133, 244)  # icons/iOS.svg <rect fill="#4285F4">

ROOT = Path(__file__).resolve().parents[3]
SOURCE_ICON = ROOT / "icons" / "iOS.png"
ICONSET = (
    ROOT
    / "iOS/Stickers/Stickers.xcassets/iMessage App Icon.stickersiconset"
)
STICKERPACK = ROOT / "iOS/Stickers/Stickers.xcassets/Sticker Pack.stickerpack"

# Target physical pixel dimensions per Apple's iMessage App Icon spec. Keep in
# sync with the iconset's Contents.json — the filenames are what Xcode reads.
ICON_TARGETS = [
    ("icon-27x20@2x.png", 54, 40),
    ("icon-27x20@3x.png", 81, 60),
    ("icon-29x29@2x.png", 58, 58),
    ("icon-29x29@3x.png", 87, 87),
    ("icon-32x24@2x.png", 64, 48),
    ("icon-32x24@3x.png", 96, 72),
    ("icon-60x45@2x.png", 120, 90),
    ("icon-60x45@3x.png", 180, 135),
    ("icon-67x50@2x.png", 134, 100),
    ("icon-74x55@2x.png", 148, 110),
    ("icon-marketing-1024.png", 1024, 1024),
    ("icon-marketing-1024x768.png", 1024, 768),
]


def regen_app_icon() -> None:
    if not SOURCE_ICON.exists():
        sys.exit(f"missing source: {SOURCE_ICON}")
    source = Image.open(SOURCE_ICON).convert("RGB")
    sw, sh = source.size

    for name, tw, th in ICON_TARGETS:
        # Fit the square mascot to the shorter target dimension and let the
        # blue background fill the rest. For square targets this is a
        # straight resize; for wider (Messages drawer / landscape marketing)
        # targets it produces extra blue on the sides instead of white.
        scale = min(tw / sw, th / sh)
        new_w = max(1, round(sw * scale))
        new_h = max(1, round(sh * scale))
        scaled = source.resize((new_w, new_h), Image.LANCZOS)

        canvas = Image.new("RGB", (tw, th), BRAND_BLUE)
        canvas.paste(scaled, ((tw - new_w) // 2, (th - new_h) // 2))
        out = ICONSET / name
        canvas.save(out, format="PNG", optimize=True)
        print(f"icon  {name:30s} {tw:4d}x{th:<4d}")


def round_stickers() -> None:
    # ~22% radius matches Apple's iOS app-icon squircle proportion well enough
    # at sticker-picker render sizes (PIL uses circular corners, not the true
    # superellipse, but the difference is invisible at <= 408 px).
    RADIUS_RATIO = 0.22

    stickers = sorted(STICKERPACK.glob("*.sticker/*.png"))
    if not stickers:
        sys.exit(f"no stickers found under {STICKERPACK}")

    for path in stickers:
        src = Image.open(path).convert("RGBA")
        w, h = src.size
        radius = round(min(w, h) * RADIUS_RATIO)

        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, w - 1, h - 1), radius=radius, fill=255
        )

        out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        out.paste(src, (0, 0), mask=mask)
        out.save(path, format="PNG", optimize=True)
        print(f"round {path.relative_to(ROOT)} r={radius}")


if __name__ == "__main__":
    regen_app_icon()
    round_stickers()
