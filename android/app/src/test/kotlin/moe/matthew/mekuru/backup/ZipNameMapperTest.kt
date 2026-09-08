package moe.matthew.mekuru.backup

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ZipNameMapperTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val mapper = ZipNameMapper(
        mapOf("Books/メロス/" to "book_1_abcdef12", "Manga/漫画" to "manga_2_00000000"),
    )

    @Test
    fun mapsTheArchiveLayoutBackToTheDeviceLayout() {
        assertEquals("mekuru_db.sqlite", mapper.map("Mekuru data/mekuru_db.sqlite"))
        assertEquals("settings.mekuru", mapper.map("Mekuru data/settings.mekuru"))
        assertEquals("books/custom_cover_1.jpg", mapper.map("Mekuru data/covers/custom_cover_1.jpg"))
        assertEquals("books/book_1_abcdef12/本.epub", mapper.map("Books/メロス/本.epub"))
        assertEquals("books/book_1_abcdef12/content/ch1.xhtml", mapper.map("Books/メロス/content/ch1.xhtml"))
        assertEquals("books/manga_2_00000000/001.jpg", mapper.map("Manga/漫画/001.jpg"))
        assertEquals("books/manga_2_00000000/pages/001.jpg", mapper.map("Manga/漫画/pages/001.jpg"))
        assertEquals("unidic-lite/sys.dic", mapper.map("Mekuru data/unidic-lite/sys.dic"))
        assertEquals("unidic-lite/.install_complete", mapper.map("Mekuru data/unidic-lite/.install_complete"))
    }

    @Test
    fun skipsSidecarsAndDirectories() {
        assertNull(mapper.map("manifest.json"))
        assertNull(mapper.map("README.txt"))
        assertNull(mapper.map("Books/メロス/"))
        assertNull(mapper.map("Books/"))
        assertNull(mapper.map("Mekuru data/unidic-lite/"))
    }

    @Test
    fun skipsEntriesThatBelongNowhere() {
        assertNull(mapper.map("Unknown/x.txt"))
        assertNull(mapper.map("Books/Other title/a.epub"))
        assertNull(mapper.map("Mekuru data/covers/nested/x.jpg"))
    }

    @Test
    fun resolveInsideRefusesEscapes() {
        val dest = tmp.newFolder("staging").canonicalFile
        for (evil in listOf("../evil.txt", "/abs.txt", "books/../../evil2.txt", "..", "")) {
            try {
                ZipNameMapper.resolveInside(dest, evil)
                fail("expected rejection for '$evil'")
            } catch (_: SecurityException) {
                // expected
            }
        }
        assertEquals(File(dest, "books/x/y.txt").canonicalFile, ZipNameMapper.resolveInside(dest, "books/x/y.txt"))
    }
}
