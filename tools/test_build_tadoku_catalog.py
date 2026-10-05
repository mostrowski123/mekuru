"""Tests for build_tadoku_catalog.py: python tools/test_build_tadoku_catalog.py"""

import unittest

from build_tadoku_catalog import page_has_text


class PageHasTextTest(unittest.TestCase):
    def test_japanese_text(self):
        self.assertTrue(page_has_text("きょうは がっこうで にほんごを べんきょうします。 1"))

    def test_junk_from_a_wrongly_mapped_font(self):
        self.assertFalse(page_has_text("äĝĀťıĻķ Ē Þ è ä ÿ Õý øê"))
        self.assertFalse(page_has_text("䛣䜜䛿䚷䛔䛱䛤䛾䜿䞊䜻"))
        self.assertFalse(page_has_text('日 本 ! " # # $ % 正 月 $ % & ( ( % ) * +'))

    def test_english_around_japanese_examples(self):
        self.assertTrue(page_has_text("The word for school is 学校（がっこう）."))

    def test_too_little_text(self):
        self.assertFalse(page_has_text("- 1 -"))


if __name__ == "__main__":
    unittest.main()
