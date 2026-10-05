from __future__ import annotations

import unittest

import build_aozora_catalog as catalog


class CatalogMappingTests(unittest.TestCase):
    def test_genre_from_ndc(self) -> None:
        self.assertEqual(catalog.genre("NDC K913"), "kid")
        self.assertEqual(catalog.genre("NDC 913"), "fic")
        self.assertEqual(catalog.genre("NDC 933"), "fic")  # translated fiction
        self.assertEqual(catalog.genre("NDC 911"), "poe")
        self.assertEqual(catalog.genre("NDC 912"), "pla")
        self.assertEqual(catalog.genre("NDC 914 915"), "ess")  # first code wins
        self.assertEqual(catalog.genre("NDC 915"), "dia")
        self.assertEqual(catalog.genre("NDC 210"), "his")
        self.assertEqual(catalog.genre("NDC 121"), "phi")
        self.assertEqual(catalog.genre("NDC 410"), "non")
        self.assertEqual(catalog.genre(""), "oth")

    def test_only_modern_xhtml_names_are_kept(self) -> None:
        self.assertTrue(catalog._XHTML_NAME.search("https://www.aozora.gr.jp/cards/000035/files/1567_14913.html"))
        self.assertFalse(catalog._XHTML_NAME.search("https://www.aozora.gr.jp/cards/000148/files/790.html"))


class LevelEstimateTests(unittest.TestCase):
    levels = {ord("日"): 5, ord("本"): 5, ord("語"): 5, ord("難"): 2, ord("解"): 3}

    def estimate(self, text: str, coverage: float = 0.8, long: tuple[int, ...] = (45, 75)) -> int:
        return catalog.estimate_level(catalog.text_stats(text, self.levels), coverage, long)

    def test_kana_only_text_is_easiest(self) -> None:
        self.assertEqual(self.estimate("これはほんです。"), 5)

    def test_level_is_where_kanji_coverage_reaches_the_threshold(self) -> None:
        # 4 of 5 kanji are N5 (80%), the fifth is N2.
        self.assertEqual(self.estimate("日本語日難。"), 5)
        # 3 of 5 at N5, 4 of 5 by N3, all by N2.
        self.assertEqual(self.estimate("日本語解難。", coverage=0.8), 3)
        self.assertEqual(self.estimate("日本語解難。", coverage=1.0), 2)

    def test_unlisted_kanji_count_as_beyond_n1(self) -> None:
        self.assertEqual(self.estimate("鬱鬱鬱日。"), 0)

    def test_repeat_mark_inherits_the_previous_kanji(self) -> None:
        self.assertEqual(catalog.text_stats("日々", self.levels)["k"][5], 2)

    def test_long_sentences_make_it_harder(self) -> None:
        short = "これはほんです。" * 10
        long = "これはほんです、" * 7 + "。"  # one 56-character sentence
        self.assertEqual(self.estimate(short), 5)
        self.assertEqual(self.estimate(long), 4)
        self.assertEqual(self.estimate("あ" * 80 + "。"), 3)


if __name__ == "__main__":
    unittest.main()
