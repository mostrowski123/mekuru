from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from PIL import Image

import make_ocr_sample_page as sample


class SamplePageTests(unittest.TestCase):
    def test_render_is_a_small_page_with_text(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "sample.jpg"
            sample.main(["--out", str(out)])
            self.assertLess(out.stat().st_size, sample.MAX_BYTES)
            with Image.open(out) as image:
                self.assertEqual(image.format, "JPEG")
                self.assertEqual(image.mode, "RGB")
                self.assertEqual(image.size, (sample.WIDTH, sample.HEIGHT))
                pixels = list(image.convert("L").getdata())
        dark = sum(1 for value in pixels if value < 128) / len(pixels)
        # Blank pages measure detection only; solid pages are not manga.
        self.assertGreater(dark, 0.005)
        self.assertLess(dark, 0.3)


if __name__ == "__main__":
    unittest.main()
