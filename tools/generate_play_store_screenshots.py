#!/usr/bin/env python3
"""Build deterministic Google Play screenshots from real Mekuru captures."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Final

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


MANGA_CREDIT: Final = "Manga: Give My Regards to Black Jack / SHUHO SATO"


@dataclass(frozen=True)
class DeviceProfile:
    source_size: tuple[int, int]
    canvas_size: tuple[int, int]
    screenshot_top: int
    screenshot_max_size: tuple[int, int]
    header_left: int
    headline_top: int
    subheading_top: int
    headline_size: int
    subheading_size: int
    credit_size: int


@dataclass(frozen=True)
class Slide:
    source: str
    output: str
    manga_credit: bool = False


@dataclass(frozen=True)
class Caption:
    headline: str
    subheading: str


DEVICE_PROFILES: Final = {
    "phone": DeviceProfile(
        source_size=(1080, 2400),
        canvas_size=(1080, 1920),
        screenshot_top=250,
        screenshot_max_size=(940, 1600),
        header_left=78,
        headline_top=98,
        subheading_top=174,
        headline_size=58,
        subheading_size=29,
        credit_size=20,
    ),
    "7-inch": DeviceProfile(
        source_size=(1200, 1920),
        canvas_size=(1200, 1920),
        screenshot_top=235,
        screenshot_max_size=(1080, 1600),
        header_left=82,
        headline_top=91,
        subheading_top=163,
        headline_size=55,
        subheading_size=28,
        credit_size=20,
    ),
    "10-inch": DeviceProfile(
        source_size=(1600, 2560),
        canvas_size=(1600, 2560),
        screenshot_top=320,
        screenshot_max_size=(1450, 2160),
        header_left=108,
        headline_top=122,
        subheading_top=220,
        headline_size=74,
        subheading_size=38,
        credit_size=27,
    ),
}


SLIDES: Final = (
    Slide("01-library.png", "01-japanese-reader.png", True),
    Slide("02-dictionary.png", "02-instant-dictionary.png"),
    Slide("03-vertical.png", "03-vertical-reading.png"),
    Slide("04-manga-mokuro.png", "04-manga-mokuro.png", True),
    Slide("05-vocabulary.png", "05-save-vocabulary.png"),
    Slide("06-ankidroid.png", "06-ankidroid-export.png"),
)


CAPTIONS: Final = {
    "en-US": (
        Caption("Japanese EPUB & Manga Reader", "Read EPUBs and Mokuro manga offline"),
        Caption("Instant Japanese Dictionary", "Tap text for fast offline definitions"),
        Caption("Vertical Japanese Reading", "Tategaki, furigana, themes, and bookmarks"),
        Caption("Manga OCR with Mokuro", "Tap OCR text directly on manga pages"),
        Caption("Save Japanese Vocabulary", "Keep the word, definition, and source sentence"),
        Caption("Export to AnkiDroid", "Turn saved words into flashcards"),
    ),
    "es-ES": (
        Caption("Lector de EPUB y manga japonés", "Lee EPUB y manga de Mokuro sin conexión"),
        Caption("Diccionario japonés instantáneo", "Toca el texto para ver definiciones sin conexión"),
        Caption("Lectura vertical en japonés", "Tategaki, furigana, temas y marcadores"),
        Caption("OCR de manga con Mokuro", "Toca el texto OCR directamente en el manga"),
        Caption("Guarda vocabulario japonés", "Conserva la palabra, definición y frase original"),
        Caption("Exporta a AnkiDroid", "Convierte palabras guardadas en tarjetas"),
    ),
    "id": (
        Caption("Pembaca EPUB & Manga Jepang", "Baca EPUB dan manga Mokuro secara offline"),
        Caption("Kamus Jepang Instan", "Ketuk teks untuk definisi offline cepat"),
        Caption("Bacaan Jepang Vertikal", "Tategaki, furigana, tema, dan penanda"),
        Caption("OCR Manga dengan Mokuro", "Ketuk teks OCR langsung pada halaman manga"),
        Caption("Simpan Kosakata Jepang", "Simpan kata, arti, dan kalimat sumber"),
        Caption("Ekspor ke AnkiDroid", "Ubah kata tersimpan menjadi kartu"),
    ),
    "zh-CN": (
        Caption("日语 EPUB 与漫画阅读器", "离线阅读 EPUB 和 Mokuro 漫画"),
        Caption("即时日语词典", "轻触文本，快速查看离线释义"),
        Caption("日语竖排阅读", "纵书、振假名、主题与书签"),
        Caption("Mokuro 漫画 OCR", "直接轻触漫画页面中的 OCR 文本"),
        Caption("保存日语词汇", "保存单词、释义与原句"),
        Caption("导出到 AnkiDroid", "将已保存单词制作为记忆卡"),
    ),
}


LOCALE_ALIASES: Final = {"es-US": "es-ES"}


def canonical_locale(locale: str) -> str:
    return LOCALE_ALIASES.get(locale, locale)


def font_path(bold: bool, locale: str) -> str:
    windows_font_dir = Path("C:/Windows/Fonts")
    if locale == "zh-CN":
        candidates = ("msyhbd.ttc", "msyh.ttc") if bold else ("msyh.ttc",)
    else:
        candidates = ("segoeuib.ttf",) if bold else ("segoeui.ttf",)
    for candidate in candidates:
        path = windows_font_dir / candidate
        if path.exists():
            return str(path)
    return "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"


def scaled(value: int, canvas_width: int) -> int:
    return round(value * canvas_width / 1080)


def make_gradient(profile: DeviceProfile) -> Image.Image:
    top = (207, 85, 98)
    bottom = (139, 42, 53)
    width, height = profile.canvas_size
    rows = []
    for y in range(height):
        blend = y / (height - 1)
        color = tuple(round(a + (b - a) * blend) for a, b in zip(top, bottom))
        rows.append(color)
    strip = Image.new("RGB", (1, height))
    strip.putdata(rows)
    return strip.resize((width, height))


def add_background_accents(image: Image.Image) -> None:
    width, height = image.size
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.ellipse(
        (-round(width * 0.21), -round(height * 0.09), round(width * 0.46), round(height * 0.29)),
        fill=(255, 226, 230, 32),
    )
    draw.ellipse(
        (round(width * 0.71), round(height * 0.02), round(width * 1.14), round(height * 0.26)),
        fill=(255, 255, 255, 22),
    )
    draw.ellipse(
        (round(width * 0.73), round(height * 0.80), round(width * 1.17), round(height * 1.04)),
        fill=(255, 222, 228, 18),
    )
    image.paste(Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB"))


def fit_single_line_font(
    text: str,
    max_width: int,
    start_size: int,
    locale: str,
    *,
    bold: bool,
) -> ImageFont.FreeTypeFont:
    minimum = max(24, round(start_size * 0.58))
    for size in range(start_size, minimum - 1, -1):
        font = ImageFont.truetype(font_path(bold, locale), size)
        if font.getlength(text) <= max_width:
            return font
    raise ValueError(f"Caption does not fit at the minimum font size: {text}")


def add_header(
    image: Image.Image,
    caption: Caption,
    profile: DeviceProfile,
    locale: str,
) -> None:
    draw = ImageDraw.Draw(image)
    width, _ = profile.canvas_size
    header_left = profile.header_left
    max_width = width - header_left * 2
    brand_size = scaled(22, width)
    brand_font = ImageFont.truetype(font_path(True, locale), brand_size)
    headline_font = fit_single_line_font(
        caption.headline,
        max_width,
        profile.headline_size,
        locale,
        bold=True,
    )
    subheading_font = fit_single_line_font(
        caption.subheading,
        max_width,
        profile.subheading_size,
        locale,
        bold=False,
    )

    badge_top = scaled(44, width)
    badge_bottom = scaled(80, width)
    badge_right = header_left + scaled(131, width)
    draw.rounded_rectangle(
        (header_left, badge_top, badge_right, badge_bottom),
        radius=scaled(18, width),
        fill=(255, 238, 241),
    )
    draw.text(
        (header_left + scaled(18, width), scaled(50, width)),
        "MEKURU",
        font=brand_font,
        fill=(139, 42, 53),
    )
    draw.text(
        (header_left, profile.headline_top),
        caption.headline,
        font=headline_font,
        fill="white",
    )
    draw.text(
        (header_left + scaled(2, width), profile.subheading_top),
        caption.subheading,
        font=subheading_font,
        fill=(255, 231, 235),
    )


def rounded_screenshot(source: Image.Image, profile: DeviceProfile) -> Image.Image:
    screenshot = source.copy()
    screenshot.thumbnail(profile.screenshot_max_size, Image.Resampling.LANCZOS)
    radius = scaled(30, profile.canvas_size[0])
    mask = Image.new("L", screenshot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, screenshot.width - 1, screenshot.height - 1),
        radius=radius,
        fill=255,
    )
    card = screenshot.convert("RGBA")
    card.putalpha(mask)
    return card


def add_screenshot(
    image: Image.Image,
    card: Image.Image,
    profile: DeviceProfile,
) -> tuple[int, int, int, int]:
    canvas_width, _ = profile.canvas_size
    x = (canvas_width - card.width) // 2
    y = profile.screenshot_top
    radius = scaled(34, canvas_width)

    shadow = Image.new("RGBA", profile.canvas_size, (0, 0, 0, 0))
    shadow_mask = Image.new("L", profile.canvas_size, 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        (x + 4, y + 12, x + card.width + 4, y + card.height + 12),
        radius=radius,
        fill=145,
    )
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(scaled(20, canvas_width)))
    shadow.putalpha(shadow_mask)
    image.paste(Image.alpha_composite(image.convert("RGBA"), shadow).convert("RGB"))
    image.paste(card, (x, y), card)
    return (x, y, x + card.width, y + card.height)


def add_manga_credit(image: Image.Image, profile: DeviceProfile, locale: str) -> None:
    draw = ImageDraw.Draw(image)
    width, height = profile.canvas_size
    font = ImageFont.truetype(font_path(False, locale), profile.credit_size)
    text_width = draw.textlength(MANGA_CREDIT, font=font)
    x = (width - text_width) / 2
    text_y = height - scaled(50, width)
    draw.rounded_rectangle(
        (x - scaled(18, width), text_y - scaled(6, width), x + text_width + scaled(18, width), text_y + scaled(34, width)),
        radius=scaled(20, width),
        fill=(112, 29, 39),
    )
    draw.text((x, text_y), MANGA_CREDIT, font=font, fill=(255, 238, 241))


def build_slide(
    slide: Slide,
    caption: Caption,
    raw_dir: Path,
    output_dir: Path,
    profile: DeviceProfile,
    locale: str,
) -> tuple[Path, tuple[int, int, int, int]]:
    source_path = raw_dir / slide.source
    with Image.open(source_path) as opened:
        source = ImageOps.exif_transpose(opened).convert("RGB")
    if source.size != profile.source_size:
        raise ValueError(
            f"{source_path} must be {profile.source_size[0]}x{profile.source_size[1]}, got {source.size}"
        )

    image = make_gradient(profile)
    add_background_accents(image)
    add_header(image, caption, profile, locale)
    bounds = add_screenshot(image, rounded_screenshot(source, profile), profile)
    if slide.manga_credit:
        add_manga_credit(image, profile, locale)

    output_path = output_dir / slide.output
    image.convert("RGB").save(output_path, format="PNG", optimize=True)
    return output_path, bounds


def build_contact_sheet(
    outputs: list[Path],
    captions: tuple[Caption, ...],
    output_dir: Path,
    locale: str,
) -> Path:
    thumb_size = (270, 480)
    gutter = 24
    label_height = 76
    margin = 32
    width = margin * 2 + thumb_size[0] * 3 + gutter * 2
    height = margin * 2 + (thumb_size[1] + label_height) * 2 + gutter
    sheet = Image.new("RGB", (width, height), (247, 239, 240))
    draw = ImageDraw.Draw(sheet)
    label_font = ImageFont.truetype(font_path(True, locale), 16)

    for index, output in enumerate(outputs):
        row, column = divmod(index, 3)
        x = margin + column * (thumb_size[0] + gutter)
        y = margin + row * (thumb_size[1] + label_height + gutter)
        with Image.open(output) as image:
            thumbnail = ImageOps.contain(image.convert("RGB"), thumb_size, Image.Resampling.LANCZOS)
        thumb_x = x + (thumb_size[0] - thumbnail.width) // 2
        sheet.paste(thumbnail, (thumb_x, y))
        label = f"{index + 1}. {captions[index].headline}"
        words = label.split()
        lines: list[str] = []
        current = ""
        for word in words:
            candidate = f"{current} {word}".strip()
            if current and draw.textlength(candidate, font=label_font) > thumb_size[0]:
                lines.append(current)
                current = word
            else:
                current = candidate
        if current:
            lines.append(current)
        if len(lines) > 2 or any(
            draw.textlength(line, font=label_font) > thumb_size[0] for line in lines
        ):
            raise ValueError(f"Contact sheet label does not fit: {label}")
        draw.multiline_text(
            (x, y + thumb_size[1] + 8),
            "\n".join(lines),
            font=label_font,
            fill=(91, 29, 37),
            spacing=2,
        )

    path = output_dir / "contact-sheet.png"
    sheet.save(path, format="PNG", optimize=True)
    return path


def validate(
    outputs: list[Path],
    bounds: list[tuple[int, int, int, int]],
    profile: DeviceProfile,
) -> None:
    minimum_height = round(profile.screenshot_max_size[1] * 0.90)
    for path, screenshot_bounds in zip(outputs, bounds):
        with Image.open(path) as image:
            if image.size != profile.canvas_size:
                raise ValueError(f"{path} has size {image.size}, expected {profile.canvas_size}")
            if image.mode != "RGB":
                raise ValueError(f"{path} has mode {image.mode}, expected RGB")
        screenshot_height = screenshot_bounds[3] - screenshot_bounds[1]
        if screenshot_height < minimum_height:
            raise ValueError(f"{path} screenshot is only {screenshot_height}px tall")


def default_asset_dirs(
    project_root: Path,
    locale: str,
    device_class: str,
) -> tuple[Path, Path]:
    if locale == "en-US" and device_class == "phone":
        return (
            project_root / "assets" / "play_store" / "raw",
            project_root / "assets" / "play_store" / "final",
        )
    canonical = canonical_locale(locale)
    return (
        project_root / "assets" / "play_store" / "raw" / canonical / device_class,
        project_root / "assets" / "play_store" / "final" / canonical / device_class,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--locale",
        choices=tuple(CAPTIONS) + tuple(LOCALE_ALIASES),
        default="en-US",
    )
    parser.add_argument(
        "--device-class",
        choices=tuple(DEVICE_PROFILES),
        default="phone",
    )
    parser.add_argument("--raw-dir", type=Path)
    parser.add_argument("--output-dir", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    project_root = Path(__file__).resolve().parents[1]
    default_raw_dir, default_output_dir = default_asset_dirs(
        project_root,
        args.locale,
        args.device_class,
    )
    raw_dir = args.raw_dir or default_raw_dir
    output_dir = args.output_dir or default_output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    locale = canonical_locale(args.locale)
    captions = CAPTIONS[locale]
    profile = DEVICE_PROFILES[args.device_class]
    outputs: list[Path] = []
    bounds: list[tuple[int, int, int, int]] = []
    for slide, caption in zip(SLIDES, captions):
        output, screenshot_bounds = build_slide(
            slide,
            caption,
            raw_dir,
            output_dir,
            profile,
            locale,
        )
        outputs.append(output)
        bounds.append(screenshot_bounds)
    validate(outputs, bounds, profile)
    contact_sheet = build_contact_sheet(outputs, captions, output_dir, locale)
    print(
        f"Generated {len(outputs)} {locale} {args.device_class} Play screenshots "
        f"and {contact_sheet}"
    )


if __name__ == "__main__":
    main()
