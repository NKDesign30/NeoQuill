#!/usr/bin/env python3
# Renders the NeoQuill DMG installer background.
#
# DMG window is 540x400. The PNG is rendered at exactly 1080x800 (2x retina)
# and the same image is placed in the DMG twice — once at 1x size and once
# as background@2x.png via the create-dmg post-processing step — so Finder
# always picks the matching resolution and stays sharp.
#
# This script writes the @2x file. build-dmg.sh handles the 1x downscale.

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT_2X = ROOT / "Resources" / "installer" / "background@2x.png"
OUT_1X = ROOT / "Resources" / "installer" / "background.png"
FONT_DIR = ROOT / "Sources" / "NeoQuill" / "Resources" / "Fonts"

# DMG window content area in logical (1x) pixels — small + cinema-aspect.
WIN_W, WIN_H = 540, 420
SCALE = 2
W, H = WIN_W * SCALE, WIN_H * SCALE

BG = (14, 14, 13)             # #0E0E0D Neon black
EMERALD = (46, 171, 115)      # #2EAB73
WHITE = (255, 255, 255)


def load_font(name: str, size: int) -> ImageFont.FreeTypeFont:
    path = FONT_DIR / name
    if not path.exists():
        raise SystemExit(f"font missing: {path}")
    return ImageFont.truetype(str(path), size=size)


def radial_glow(img: Image.Image, cx: int, cy: int, radius: int, peak_alpha: int) -> None:
    """Soft radial emerald blob composited onto img."""
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    steps = 64
    for i in range(steps, 0, -1):
        r = int(radius * (i / steps))
        a = int(peak_alpha * (i / steps) ** 2.4)
        draw.ellipse(
            (cx - r, cy - r, cx + r, cy + r),
            fill=(EMERALD[0], EMERALD[1], EMERALD[2], a),
        )
    img.alpha_composite(glow)


def draw_arrow(draw: ImageDraw.ImageDraw, x1: int, y: int, x2: int,
               color, shaft: int = 4, head: int = 18) -> None:
    """Thin arrow from x1 -> x2 at vertical y."""
    draw.line((x1, y, x2 - head, y), fill=color, width=shaft)
    draw.polygon(
        [(x2, y), (x2 - head, y - head + 2), (x2 - head, y + head - 2)],
        fill=color,
    )


def main() -> None:
    img = Image.new("RGBA", (W, H), (*BG, 255))

    # Background atmosphere: large soft emerald glow below the icon row,
    # second smaller glow top-left for depth.
    radial_glow(img, cx=W // 2, cy=int(H * 1.05), radius=int(W * 0.85), peak_alpha=85)
    radial_glow(img, cx=int(W * 0.15), cy=int(H * 0.18), radius=int(W * 0.32), peak_alpha=30)

    draw = ImageDraw.Draw(img)

    # ----- Top band: wordmark + eyebrow -----------------------------------
    # Both scaled by SCALE so the @2x render stays crisp.
    eyebrow_font = load_font("GeistMono-Variable.ttf", 9 * SCALE)
    eyebrow = "INSTALLATION"
    ew = draw.textlength(eyebrow, font=eyebrow_font)
    draw.text(((W - ew) // 2, 22 * SCALE), eyebrow, font=eyebrow_font,
              fill=(EMERALD[0], EMERALD[1], EMERALD[2], 220))

    title_font = load_font("DMSerifDisplay-Regular.ttf", 32 * SCALE)
    title_italic = load_font("DMSerifDisplay-Italic.ttf", 32 * SCALE)
    neo_w = draw.textlength("Neo", font=title_font)
    quill_w = draw.textlength("quill", font=title_italic)
    title_x = (W - (neo_w + quill_w)) // 2
    title_y = 38 * SCALE
    draw.text((title_x, title_y), "Neo", font=title_font, fill=WHITE)
    draw.text((title_x + neo_w, title_y), "quill", font=title_italic, fill=EMERALD)

    sub_font = load_font("InterVariable.ttf", 11 * SCALE)
    sub_text = "Local-first meeting intelligence."
    sw = draw.textlength(sub_text, font=sub_font)
    draw.text(((W - sw) // 2, 95 * SCALE), sub_text, font=sub_font,
              fill=(255, 255, 255, 170))

    # ----- Drag arrow ----------------------------------------------------
    # DMG icon row sits at y=290 (logical). Arrow runs between icon centers
    # at x=130 (app) and x=410 (Applications), so the visible shaft spans
    # roughly x=185 -> x=355 to clear the icon glyphs.
    arrow_y = 290 * SCALE
    draw_arrow(
        draw,
        x1=185 * SCALE,
        y=arrow_y,
        x2=355 * SCALE,
        color=(EMERALD[0], EMERALD[1], EMERALD[2], 230),
        shaft=2 * SCALE,
        head=10 * SCALE,
    )

    # ----- Footer hint ---------------------------------------------------
    hint_font = load_font("GeistMono-Variable.ttf", 8 * SCALE)
    hint = "github.com/NKDesign30/NeoQuill"
    hw = draw.textlength(hint, font=hint_font)
    draw.text(((W - hw) // 2, H - 22 * SCALE), hint, font=hint_font,
              fill=(255, 255, 255, 110))

    OUT_2X.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT_2X, "PNG", optimize=True)
    print(f"wrote {OUT_2X.relative_to(ROOT)} ({W}x{H})")

    one_x = img.resize((WIN_W, WIN_H), Image.LANCZOS)
    one_x.convert("RGB").save(OUT_1X, "PNG", optimize=True)
    print(f"wrote {OUT_1X.relative_to(ROOT)} ({WIN_W}x{WIN_H})")


if __name__ == "__main__":
    main()
