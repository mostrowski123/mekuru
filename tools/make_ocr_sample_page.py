"""Render the synthetic manga page bundled for the on-device OCR speed test.

The page is script-generated, not taken from any manga: panel borders, speech
bubbles and short vertical lines of original Japanese text. Only the JPEG ships
in the plugin (as `assets/local_manga_ocr/sample.jpg`); the font is used at
generation time only.

    python tools/make_ocr_sample_page.py [--font PATH] [--out PATH]
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1000, 1500
MAX_BYTES = 300_000
OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "packages/local_manga_ocr/android/src/main/assets/local_manga_ocr/sample.jpg"
)
FONT_CANDIDATES = ("NotoSansJP-VF.ttf", "BIZ-UDGothicR.ttc", "meiryo.ttc")
FONT_SIZE = 44

# Original dialogue; every bubble reads top-to-bottom, right-to-left.
BUBBLES = (
    ("今日は", "いい天気だね"),
    ("そうだね", "散歩に", "行こうか"),
    ("ちょっと", "待って"),
    ("お腹が", "すいたな"),
    ("あの店の", "ラーメンは", "おいしいよ"),
    ("じゃあ", "決まりだ"),
)
PANELS = ((40, 40, 960, 700), (40, 740, 480, 1460), (520, 740, 960, 1460))
# Bubble centre and size, placed inside the panels above.
BUBBLE_BOXES = (
    (250, 250, 260, 340),
    (720, 300, 300, 400),
    (250, 540, 240, 250),
    (260, 950, 230, 300),
    (740, 900, 300, 400),
    (740, 1250, 240, 250),
)


def font_path(explicit: str | None) -> str:
    if explicit:
        return explicit
    windows_font_dir = Path("C:/Windows/Fonts")
    for candidate in FONT_CANDIDATES:
        path = windows_font_dir / candidate
        if path.exists():
            return str(path)
    raise SystemExit("no Japanese font found; pass --font <path to a TTF/TTC>")


def draw_vertical(
    draw: ImageDraw.ImageDraw,
    font: ImageFont.FreeTypeFont,
    lines: tuple[str, ...],
    center_x: int,
    center_y: int,
) -> None:
    column_gap = int(FONT_SIZE * 1.3)
    tallest = max(len(line) for line in lines)
    top = center_y - tallest * FONT_SIZE // 2
    x = center_x + (len(lines) - 1) * column_gap // 2
    for line in lines:
        for row, glyph in enumerate(line):
            draw.text(
                (x, top + row * FONT_SIZE),
                glyph,
                fill="black",
                font=font,
                anchor="mt",
            )
        x -= column_gap


def render(font_file: str | None) -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(font_path(font_file), FONT_SIZE)
    for panel in PANELS:
        draw.rectangle(panel, outline="black", width=4)
    for lines, (cx, cy, w, h) in zip(BUBBLES, BUBBLE_BOXES):
        draw.ellipse(
            (cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2),
            fill="white",
            outline="black",
            width=3,
        )
        draw_vertical(draw, font, lines, cx, cy)
    return image


def main(argv: list[str] | None = None) -> Path:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--font", help="TTF/TTC with Japanese glyphs")
    parser.add_argument("--out", type=Path, default=OUTPUT)
    args = parser.parse_args(argv)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    render(args.font).save(args.out, "JPEG", quality=85, optimize=True)
    size = args.out.stat().st_size
    if size > MAX_BYTES:
        raise SystemExit(f"{args.out} is {size} bytes; keep it under {MAX_BYTES}")
    print(f"wrote {args.out} ({size} bytes)")
    return args.out


if __name__ == "__main__":
    main()
