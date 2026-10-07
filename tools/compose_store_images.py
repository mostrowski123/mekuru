#!/usr/bin/env python3
"""Compose the Google Play and App Store images from raw Mekuru screenshots.

Raw captures (tools/capture_android_store_shots.py, tools/capture_ios_store_shots.py) are read from
`<raw>/<device>/<lang>/<nn>.png`, where device is phone, tablet, iphone or
ipad and lang is en, es, id or zh (the app's UI languages). Captions come from
store_listing/captions/<caption-lang>.txt; Japanese captions go over the
English UI, since the app has no Japanese UI. Output, flattened RGB PNGs:

  <out>/play/<lang>/{phone,tablet-7,tablet-10}/<nn>.png
  <out>/play/<lang>/feature/feature.png
  <out>/app_store/<lang>/{iphone,ipad}/<nn>.png
  <out>/contact-<store>-<lang>.png   (one sheet per store and language, for review)

Fonts are macOS's Hiragino Sans (Hiragino Sans GB for Chinese).

  python3 tools/compose_store_images.py --raw build/store_images/raw --out build/store_images
  python3 tools/compose_store_images.py ... --only play:en:phone:01,03   # samples
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CAPTIONS = ROOT / 'store_listing' / 'captions'
ICON = ROOT / 'assets' / 'app_icon' / 'marketing' / 'google_play_icon_512.png'

# The icon's reds, and warm neutrals that sit well next to them.
RED = (185, 69, 81)
WINE = (74, 26, 31)
INK = (46, 17, 20)
MUTED = (122, 90, 85)
BG_TOP = (255, 248, 243)
BG_BOTTOM = (247, 228, 221)
BODY = (23, 17, 15)

CAPTION_LANGS = ('en', 'es', 'id', 'ja', 'zh')
# The UI language each caption language's screens were captured in.
UI_LANG = {'en': 'en', 'es': 'es', 'id': 'id', 'ja': 'en', 'zh': 'zh'}

# Shots that show a Pro feature, and shots that show Black Jack's pages.
PRO: set[str] = set()  # shots that only show a Pro feature get a PRO pill
MANGA = {'01', '08'}
CREDIT = {
    'ja': 'ブラックジャックによろしく　佐藤秀峰',
    None: 'Give My Regards to Black Jack SHUHO SATO',
}
PRO_LABEL = 'PRO'


@dataclass(frozen=True)
class Target:
    store: str
    name: str
    raw_device: str
    size: tuple[int, int]
    tablet: bool


TARGETS = (
    Target('play', 'phone', 'phone', (1080, 1920), False),
    Target('play', 'tablet-7', 'tablet', (1200, 1920), True),
    Target('play', 'tablet-10', 'tablet', (1600, 2560), True),
    Target('app_store', 'iphone', 'iphone', (1320, 2868), False),
    Target('app_store', 'ipad', 'ipad', (2064, 2752), True),
)


def font(lang: str, bold: bool, size: int) -> ImageFont.FreeTypeFont:
    if lang == 'zh':
        # Hiragino Sans has no simplified-only characters such as 对, 语, 读.
        return ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc', size, index=2 if bold else 0)
    weight = 'W7' if bold else 'W4'
    return ImageFont.truetype(f'/System/Library/Fonts/ヒラギノ角ゴシック {weight}.ttc', size)


def load_captions(lang: str) -> dict[str, tuple[str, str]]:
    """`01 | Headline, \\n for a line break | Subline` per line; # comments."""
    captions = {}
    for line in (CAPTIONS / f'{lang}.txt').read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        key, headline, subline = (part.strip() for part in line.split('|'))
        captions[key] = (headline.replace('\\n', '\n'), subline)
    return captions


def background(size: tuple[int, int]) -> Image.Image:
    w, h = size
    gradient = Image.linear_gradient('L').resize((w, h))
    image = Image.composite(Image.new('RGB', size, BG_BOTTOM), Image.new('RGB', size, BG_TOP), gradient)
    glow = Image.new('L', size, 0)
    d = ImageDraw.Draw(glow)
    d.ellipse((int(w * 0.55), int(-h * 0.08), int(w * 1.35), int(h * 0.32)), fill=70)
    d.ellipse((int(-w * 0.45), int(h * 0.62), int(w * 0.35), int(h * 1.1)), fill=45)
    glow = glow.filter(ImageFilter.GaussianBlur(w // 10))
    return Image.composite(Image.new('RGB', size, (236, 175, 178)), image, glow)


def wrap_lines(draw: ImageDraw.ImageDraw, text: str, fnt, max_width: int) -> list[str]:
    """Breaks on the caption's own \\n, then on spaces (or anywhere, for CJK) to fit."""
    lines = []
    for paragraph in text.split('\n'):
        # Latin text breaks at spaces; CJK anywhere, but never inside a Latin word.
        words = paragraph.split(' ') if ' ' in paragraph else re.findall(r'[A-Za-z0-9()（）]+|.', paragraph)
        sep = ' ' if ' ' in paragraph else ''
        line = ''
        for word in words:
            trial = f'{line}{sep}{word}' if line else word
            if draw.textlength(trial, font=fnt) <= max_width or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def device(screen: Image.Image, tablet: bool) -> Image.Image:
    """The screenshot inside a drawn device body, on a transparent canvas."""
    sw, sh = screen.size
    bezel = int(sw * (0.035 if tablet else 0.028))
    radius = int(sw * (0.06 if tablet else 0.13))
    bw, bh = sw + 2 * bezel, sh + 2 * bezel
    body = Image.new('RGBA', (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((0, 0, bw - 1, bh - 1), radius=radius, fill=BODY + (255,))
    # A thin lighter edge reads as metal at small sizes.
    d.rounded_rectangle((2, 2, bw - 3, bh - 3), radius=radius - 2, outline=(70, 58, 55, 255), width=max(2, bw // 400))
    mask = Image.new('L', screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=max(0, radius - bezel), fill=255)
    body.paste(screen.convert('RGB'), (bezel, bezel), mask)
    return body


def shadow(size: tuple[int, int], box: tuple[int, int, int, int], radius: int) -> Image.Image:
    layer = Image.new('L', size, 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(layer).rounded_rectangle((x0, y0 + radius // 3, x1, y1 + radius // 3), radius=radius, fill=110)
    return layer.filter(ImageFilter.GaussianBlur(max(8, (x1 - x0) // 18)))


def pill(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, fnt) -> int:
    x, y = xy
    tw = draw.textlength(text, font=fnt)
    pad_x, height = fnt.size * 0.7, fnt.size * 1.6
    draw.rounded_rectangle((x, y, x + tw + 2 * pad_x, y + height), radius=height / 2, fill=RED)
    draw.text((x + pad_x, y + height / 2), text, font=fnt, fill=(255, 255, 255), anchor='lm')
    return int(height)


def compose(raw: Image.Image, target: Target, lang: str, key: str, captions) -> Image.Image:
    w, h = target.size
    image = background(target.size)
    draw = ImageDraw.Draw(image)
    margin = int(w * (0.075 if not target.tablet else 0.09))
    headline, subline = captions[key]
    scale = w if not target.tablet else int(w * 0.8)

    y = int(h * 0.05)
    if key in PRO:
        y += pill(draw, (margin, y), PRO_LABEL, font(lang, True, int(scale * 0.03))) + int(h * 0.014)
    else:
        bar = int(scale * 0.012)
        draw.rounded_rectangle((margin, y, margin + int(scale * 0.09), y + bar), radius=bar // 2, fill=RED)
        y += bar + int(h * 0.02)

    # Shrink the headline (by up to a fifth) until each written line fits on one line.
    size = int(scale * (0.068 if lang not in ('ja', 'zh') else 0.064))
    hfont = font(lang, True, size)
    while size > scale * 0.054 and any(
            draw.textlength(line, font=hfont) > w - 2 * margin for line in headline.split('\n')):
        size -= 2
        hfont = font(lang, True, size)
    for line in wrap_lines(draw, headline, hfont, w - 2 * margin):
        draw.text((margin, y), line, font=hfont, fill=INK)
        y += int(hfont.size * 1.22)
    sfont = font(lang, False, int(scale * 0.037))
    y += int(h * 0.006)
    for line in wrap_lines(draw, subline, sfont, w - 2 * margin):
        draw.text((margin, y), line, font=sfont, fill=MUTED)
        y += int(sfont.size * 1.4)

    if key in MANGA:
        cfont = font(lang if lang in ('ja', 'zh') else 'en', False, int(scale * 0.021))
        text = CREDIT['ja'] if lang == 'ja' else CREDIT[None]
        draw.text((margin, y), text, font=cfont, fill=MUTED)
        y += int(cfont.size * 1.4)

    # The device is sized by width and runs off the bottom edge: the top of
    # the screen carries the point, and a bigger screen reads better small.
    top = y + int(h * 0.03)
    framed = device(raw, target.tablet)
    fit = w * (0.84 if target.tablet else 0.8) / framed.width
    # Play's Anki shot has its button at the very bottom: show the whole device.
    whole = key == '05' and target.store == 'play'
    fit = min(fit, (h - top) * (0.97 if whole else 1.25) / framed.height)
    framed = framed.resize((int(framed.width * fit), int(framed.height * fit)), Image.LANCZOS)
    x = (w - framed.width) // 2
    box = (x, top, x + framed.width, top + framed.height)
    image = Image.composite(Image.new('RGB', target.size, (60, 25, 28)), image, shadow(target.size, box, framed.width // 9))
    image.paste(framed, (x, top), framed)
    return image


def feature_graphic(raw: Image.Image, lang: str, captions) -> Image.Image:
    w, h = 1024, 500
    image = background((w, h))
    draw = ImageDraw.Draw(image)
    icon = Image.open(ICON).convert('RGBA').resize((96, 96), Image.LANCZOS)
    mask = Image.new('L', icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 95, 95), radius=22, fill=255)
    image.paste(icon, (56, 56), mask)
    draw.text((168, 104), 'Mekuru', font=font('en', True, 40), fill=WINE, anchor='lm')
    headline, subline = captions['feature']
    size = 44 if lang not in ('ja', 'zh') else 42
    hfont = font(lang, True, size)
    while size > 34 and any(draw.textlength(line, font=hfont) > 540 for line in headline.split('\n')):
        size -= 2
        hfont = font(lang, True, size)
    y = 186
    for line in wrap_lines(draw, headline, hfont, 540):
        draw.text((56, y), line, font=hfont, fill=INK)
        y += int(hfont.size * 1.2)
    sfont = font(lang, False, 24)
    for line in wrap_lines(draw, subline, sfont, 540):
        draw.text((56, y + 10), line, font=sfont, fill=MUTED)
        y += int(sfont.size * 1.4)
    cfont = font('ja' if lang == 'ja' else 'en', False, 15)
    draw.text((56, h - 28), CREDIT['ja'] if lang == 'ja' else CREDIT[None], font=cfont, fill=MUTED)
    # Only the page and the dictionary sheet: drop the black band above the page.
    rw, rh = raw.size
    framed = device(raw.crop((0, int(rh * 0.17), rw, rh)), False)
    fit = 330 / framed.width
    framed = framed.resize((int(framed.width * fit), int(framed.height * fit)), Image.LANCZOS)
    x, top = w - framed.width - 60, 36
    image = Image.composite(Image.new('RGB', (w, h), (60, 25, 28)), image, shadow((w, h), (x, top, x + framed.width, top + framed.height), 30))
    image.paste(framed, (x, top), framed)
    return image


def contact_sheet(paths: list[Path], out: Path) -> None:
    thumbs = []
    for path in paths:
        im = Image.open(path)
        im.thumbnail((360, 640))
        thumbs.append(im)
    if not thumbs:
        return
    cols = min(8, len(thumbs))
    rows = -(-len(thumbs) // cols)
    cw, ch = max(t.width for t in thumbs), max(t.height for t in thumbs)
    sheet = Image.new('RGB', (cols * (cw + 16) + 16, rows * (ch + 16) + 16), (200, 200, 200))
    for i, t in enumerate(thumbs):
        sheet.paste(t, (16 + (i % cols) * (cw + 16), 16 + (i // cols) * (ch + 16)))
    sheet.save(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--raw', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--only', help='store:lang:target:nn[,nn]; e.g. play:en:phone:01,03')
    args = parser.parse_args()

    only = args.only.split(':') if args.only else None
    written: dict[tuple[str, str], list[Path]] = {}
    for lang in CAPTION_LANGS:
        if only and lang != only[1]:
            continue
        captions = load_captions(lang)
        for target in TARGETS:
            if only and (target.store != only[0] or target.name != only[2]):
                continue
            raw_dir = args.raw / target.raw_device / UI_LANG[lang]
            for raw_path in sorted(raw_dir.glob('[0-9][0-9].png')):
                key = raw_path.stem
                if only and key not in only[3].split(','):
                    continue
                if key not in captions:
                    continue
                dest = args.out / target.store / lang / target.name / f'{key}.png'
                dest.parent.mkdir(parents=True, exist_ok=True)
                compose(Image.open(raw_path), target, lang, key, captions).save(dest, optimize=True)
                written.setdefault((target.store, lang), []).append(dest)
        feature_raw = args.raw / 'phone' / UI_LANG[lang] / '01.png'
        if not only and feature_raw.exists():
            dest = args.out / 'play' / lang / 'feature' / 'feature.png'
            dest.parent.mkdir(parents=True, exist_ok=True)
            feature_graphic(Image.open(feature_raw), lang, captions).save(dest, optimize=True)
            written.setdefault(('play', lang), []).append(dest)
    for (store, lang), paths in written.items():
        contact_sheet(paths, args.out / f'contact-{store}-{lang}.png')
        print(f'{store} {lang}: {len(paths)} images')


if __name__ == '__main__':
    main()
