package moe.matthew.mekuru

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Regression coverage for MEKURU-15: a manga import from a SAF folder failed
 * with "Could not read selected file from folder access grant" because child
 * document IDs were derived by string-concatenating the tree document ID with
 * the relative path. That only holds for path-shaped providers, so listing the
 * tree root succeeded (it uses the real tree document ID) while reading a file
 * that the listing had just returned failed.
 */
class SafTreePathResolverTest {

    /**
     * Stands in for a SAF provider's children cursor. [children] is keyed by
     * parent document ID.
     */
    private class FakeProvider(private val children: Map<String, List<SafChildDocument>>) {
        var listCalls = 0
            private set

        fun listChildren(parentDocumentId: String): List<SafChildDocument> {
            listCalls++
            return children[parentDocumentId] ?: emptyList()
        }
    }

    // A Downloads-style provider: document IDs are opaque and say nothing about
    // where the document sits in the tree.
    private fun opaqueProvider() = FakeProvider(
        mapOf(
            "downloads" to listOf(
                SafChildDocument("msf:1001", "Volume 1.mokuro"),
                SafChildDocument("msf:1002", "Volume 1"),
                SafChildDocument("msf:1003", "readme.txt"),
            ),
            "msf:1002" to listOf(
                SafChildDocument("msf:2001", "page_001.jpg"),
                SafChildDocument("msf:2002", "page_002.jpg"),
            ),
        ),
    )

    @Test
    fun `resolves a file under a provider with opaque document ids`() {
        val provider = opaqueProvider()
        val segments = SafTreePathResolver.splitSegments("Volume 1.mokuro")!!

        val resolved = SafTreePathResolver.walkDocumentId(
            "downloads",
            segments,
            provider::listChildren,
        )

        assertEquals("msf:1001", resolved)
    }

    @Test
    fun `concatenating document ids cannot address an opaque provider`() {
        // This is the exact derivation that shipped in 1.17.0. It must not be
        // relied on alone: the ID it produces names no document in a provider
        // whose IDs are opaque, which is why the read returned null.
        val segments = SafTreePathResolver.splitSegments("Volume 1.mokuro")!!
        val joined = SafTreePathResolver.joinDocumentId("downloads", segments)

        assertEquals("downloads/Volume 1.mokuro", joined)
        val realIds = opaqueProvider().listChildren("downloads").map { it.documentId }
        assertEquals(false, realIds.contains(joined))
    }

    @Test
    fun `walks nested directories one segment at a time`() {
        val provider = opaqueProvider()
        val segments = SafTreePathResolver.splitSegments("Volume 1/page_002.jpg")!!

        val resolved = SafTreePathResolver.walkDocumentId(
            "downloads",
            segments,
            provider::listChildren,
        )

        assertEquals("msf:2002", resolved)
        assertEquals(2, provider.listCalls)
    }

    @Test
    fun `returns null when a segment has no matching child`() {
        val provider = opaqueProvider()
        val segments = SafTreePathResolver.splitSegments("Volume 9.mokuro")!!

        assertNull(
            SafTreePathResolver.walkDocumentId("downloads", segments, provider::listChildren),
        )
    }

    @Test
    fun `stops walking as soon as a directory segment is missing`() {
        val provider = opaqueProvider()
        val segments = SafTreePathResolver.splitSegments("Volume 9/page_001.jpg")!!

        assertNull(
            SafTreePathResolver.walkDocumentId("downloads", segments, provider::listChildren),
        )
        assertEquals(1, provider.listCalls)
    }

    @Test
    fun `resolves display names containing spaces and japanese text`() {
        val provider = FakeProvider(
            mapOf(
                "tree" to listOf(SafChildDocument("msf:77", "よつばと！ 第1巻.mokuro")),
            ),
        )
        val segments = SafTreePathResolver.splitSegments("よつばと！ 第1巻.mokuro")!!

        assertEquals(
            "msf:77",
            SafTreePathResolver.walkDocumentId("tree", segments, provider::listChildren),
        )
    }

    @Test
    fun `matches display names exactly rather than by case`() {
        val provider = FakeProvider(
            mapOf("tree" to listOf(SafChildDocument("msf:5", "Volume 1.mokuro"))),
        )
        val segments = SafTreePathResolver.splitSegments("volume 1.MOKURO")!!

        assertNull(
            SafTreePathResolver.walkDocumentId("tree", segments, provider::listChildren),
        )
    }

    @Test
    fun `an empty path resolves to the tree root without querying children`() {
        val provider = opaqueProvider()

        assertEquals(
            "downloads",
            SafTreePathResolver.walkDocumentId("downloads", emptyList(), provider::listChildren),
        )
        assertEquals(0, provider.listCalls)
    }

    @Test
    fun `keeps the path-shaped fast path intact for external storage`() {
        val segments = SafTreePathResolver.splitSegments("Volume 1.mokuro")!!

        assertEquals(
            "primary:Download/Manga/Volume 1.mokuro",
            SafTreePathResolver.joinDocumentId("primary:Download/Manga", segments),
        )
    }

    @Test
    fun `does not double the separator when the tree is a volume root`() {
        val segments = SafTreePathResolver.splitSegments("Volume 1.mokuro")!!

        // A grant over the whole volume yields "primary:" with nothing after
        // the colon; blindly inserting "/" produced "primary:/Volume 1.mokuro".
        val joined = SafTreePathResolver.joinDocumentId("primary:", segments)
        assertEquals("primary:Volume 1.mokuro", joined)
        assertNotEquals("primary:/Volume 1.mokuro", joined)
    }

    @Test
    fun `joins nested segments for path-shaped providers`() {
        val segments = SafTreePathResolver.splitSegments("Volume 1/page_001.jpg")!!

        assertEquals(
            "1234-5678:Manga/Volume 1/page_001.jpg",
            SafTreePathResolver.joinDocumentId("1234-5678:Manga", segments),
        )
    }

    @Test
    fun `splits paths into segments and ignores empty and dot parts`() {
        assertEquals(listOf("a", "b"), SafTreePathResolver.splitSegments("a/b"))
        assertEquals(listOf("a", "b"), SafTreePathResolver.splitSegments("//a//b//"))
        assertEquals(listOf("a", "b"), SafTreePathResolver.splitSegments("./a/./b"))
        assertEquals(listOf("a", "b"), SafTreePathResolver.splitSegments("a\\b"))
    }

    @Test
    fun `treats blank paths as the tree root`() {
        assertEquals(emptyList<String>(), SafTreePathResolver.splitSegments(""))
        assertEquals(emptyList<String>(), SafTreePathResolver.splitSegments("   "))
        assertEquals(emptyList<String>(), SafTreePathResolver.splitSegments("."))
        assertEquals(emptyList<String>(), SafTreePathResolver.splitSegments("/"))
    }

    @Test
    fun `rejects paths that escape the tree`() {
        assertNull(SafTreePathResolver.splitSegments(".."))
        assertNull(SafTreePathResolver.splitSegments("../secrets"))
        assertNull(SafTreePathResolver.splitSegments("Volume 1/../../secrets"))
    }
}
