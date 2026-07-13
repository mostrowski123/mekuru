from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from PIL import Image

import generate_play_store_screenshots as screenshots
import publish_play_store_listings as listings


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class StoreListingTests(unittest.TestCase):
    def test_all_configured_listings_are_complete_and_within_limits(self) -> None:
        for locale, filename in listings.LOCALE_SOURCES.items():
            listing = listings.parse_listing(
                PROJECT_ROOT / "store_listing" / filename,
                locale,
            )
            self.assertEqual(locale, listing.locale)

    def test_spanish_us_reuses_spanish_assets(self) -> None:
        self.assertEqual(
            listings.screenshot_dir(PROJECT_ROOT, "es-ES", "phone"),
            listings.screenshot_dir(PROJECT_ROOT, "es-US", "phone"),
        )

    def test_screenshot_validation_rejects_wrong_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for index in range(6):
                Image.new("RGB", (100, 100)).save(root / f"{index}.png")
            with self.assertRaisesRegex(ValueError, "expected"):
                listings.validate_screenshots(root, (1080, 1920))


class ScreenshotGeneratorTests(unittest.TestCase):
    def test_locale_alias_and_device_profiles_are_configured(self) -> None:
        self.assertEqual("es-ES", screenshots.canonical_locale("es-US"))
        self.assertEqual((1080, 1920), screenshots.DEVICE_PROFILES["phone"].canvas_size)
        self.assertEqual((1200, 1920), screenshots.DEVICE_PROFILES["7-inch"].canvas_size)
        self.assertEqual((1600, 2560), screenshots.DEVICE_PROFILES["10-inch"].canvas_size)

    def test_every_caption_fits_its_device_header(self) -> None:
        for locale, captions in screenshots.CAPTIONS.items():
            for profile in screenshots.DEVICE_PROFILES.values():
                maximum_width = profile.canvas_size[0] - profile.header_left * 2
                for caption in captions:
                    screenshots.fit_single_line_font(
                        caption.headline,
                        maximum_width,
                        profile.headline_size,
                        locale,
                        bold=True,
                    )
                    screenshots.fit_single_line_font(
                        caption.subheading,
                        maximum_width,
                        profile.subheading_size,
                        locale,
                        bold=False,
                    )


if __name__ == "__main__":
    unittest.main()
