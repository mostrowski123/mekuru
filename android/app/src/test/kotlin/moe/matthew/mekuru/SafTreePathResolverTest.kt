package moe.matthew.mekuru

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.text.Normalizer

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

    // --- Caching -----------------------------------------------------------
    //
    // Every walk costs one children query per path segment. On a cloud or
    // network provider those are round trips, and the reader resolves one path
    // per page, so these assert on the call count rather than just the result.

    private fun resolve(
        cache: SafResolutionCache,
        provider: FakeProvider,
        path: String,
        treeDocumentId: String = "downloads",
    ): String? = SafTreePathResolver.resolveCached(
        TREE,
        treeDocumentId,
        SafTreePathResolver.splitSegments(path)!!,
        cache,
        provider::listChildren,
    )

    @Test
    fun `reading a second page in a known directory costs no provider calls`() {
        val provider = opaqueProvider()
        val cache = SafResolutionCache()

        assertEquals("msf:2001", resolve(cache, provider, "Volume 1/page_001.jpg"))
        val afterFirstPage = provider.listCalls
        assertEquals(2, afterFirstPage)

        assertEquals("msf:2002", resolve(cache, provider, "Volume 1/page_002.jpg"))

        // The whole point: paging through a volume must not re-list the tree
        // root and the volume directory for every image.
        assertEquals(afterFirstPage, provider.listCalls)
    }

    @Test
    fun `repeating the same path costs no provider calls`() {
        val provider = opaqueProvider()
        val cache = SafResolutionCache()

        assertEquals("msf:1001", resolve(cache, provider, "Volume 1.mokuro"))
        val afterFirst = provider.listCalls

        assertEquals("msf:1001", resolve(cache, provider, "Volume 1.mokuro"))
        assertEquals(afterFirst, provider.listCalls)
    }

    @Test
    fun `caches each prefix so a sibling directory reuses the root listing`() {
        val provider = opaqueProvider()
        val cache = SafResolutionCache()

        resolve(cache, provider, "Volume 1/page_001.jpg")
        assertEquals("msf:1002", cache.documentId(TREE, "Volume 1"))
        assertEquals("msf:2001", cache.documentId(TREE, "Volume 1/page_001.jpg"))
    }

    @Test
    fun `does not cache a path that failed to resolve`() {
        val provider = opaqueProvider()
        val cache = SafResolutionCache()

        assertNull(resolve(cache, provider, "Volume 9.mokuro"))
        assertNull(cache.documentId(TREE, "Volume 9.mokuro"))
    }

    @Test
    fun `invalidating a tree forces the next resolve to read again`() {
        val provider = opaqueProvider()
        val cache = SafResolutionCache()

        resolve(cache, provider, "Volume 1.mokuro")
        val afterFirst = provider.listCalls
        cache.invalidateTree(TREE)

        assertEquals("msf:1001", resolve(cache, provider, "Volume 1.mokuro"))
        assertEquals(afterFirst + 1, provider.listCalls)
    }

    @Test
    fun `invalidating one tree leaves another tree cached`() {
        val cache = SafResolutionCache()
        cache.putDocumentId(TREE, "a", "id-a")
        cache.putDocumentId("content://other/tree/x", "a", "id-b")

        cache.invalidateTree(TREE)

        assertNull(cache.documentId(TREE, "a"))
        assertEquals("id-b", cache.documentId("content://other/tree/x", "a"))
    }

    @Test
    fun `remembers that a tree rejects appended document ids`() {
        val cache = SafResolutionCache()
        assertEquals(false, cache.isKnownOpaque(TREE))

        cache.markOpaque(TREE)
        assertEquals(true, cache.isKnownOpaque(TREE))

        // Invalidation re-tests the tree rather than trusting the old verdict.
        cache.invalidateTree(TREE)
        assertEquals(false, cache.isKnownOpaque(TREE))
    }

    @Test
    fun `evicts the least recently used entry past its bound`() {
        val cache = SafResolutionCache(maxEntries = 2)
        cache.putDocumentId(TREE, "a", "id-a")
        cache.putDocumentId(TREE, "b", "id-b")
        cache.documentId(TREE, "a") // touch "a" so "b" becomes the eldest
        cache.putDocumentId(TREE, "c", "id-c")

        assertEquals("id-a", cache.documentId(TREE, "a"))
        assertEquals("id-c", cache.documentId(TREE, "c"))
        assertNull(cache.documentId(TREE, "b"))
    }

    @Test
    fun `an empty path needs no provider call`() {
        val provider = opaqueProvider()
        val cache = SafResolutionCache()

        assertEquals(
            "downloads",
            SafTreePathResolver.resolveCached(
                TREE,
                "downloads",
                emptyList(),
                cache,
                provider::listChildren,
            ),
        )
        assertEquals(0, provider.listCalls)
    }

    // --- Unicode normalization ---------------------------------------------
    //
    // The same Japanese filename can be composed (NFC) or decomposed (NFD).
    // Archives written on macOS are decomposed, so a mokuro manifest and the
    // provider serving the files can disagree byte for byte about equal names.

    @Test
    fun `the two encodings really are different strings`() {
        // Guards the cases below: were these equal, the normalization tests
        // would pass without exercising anything.
        assertNotEquals(COMPOSED, DECOMPOSED)
        assertEquals(COMPOSED, SafTreePathResolver.canonicalName(DECOMPOSED))
        assertEquals(COMPOSED, SafTreePathResolver.canonicalName(COMPOSED))
    }

    @Test
    fun `matches a decomposed manifest name against a composed display name`() {
        val provider = FakeProvider(
            mapOf("tree" to listOf(SafChildDocument("msf:9", COMPOSED))),
        )

        assertEquals(
            "msf:9",
            SafTreePathResolver.walkDocumentId(
                "tree",
                listOf(DECOMPOSED),
                provider::listChildren,
            ),
        )
    }

    @Test
    fun `matches a composed manifest name against a decomposed display name`() {
        val provider = FakeProvider(
            mapOf("tree" to listOf(SafChildDocument("msf:9", DECOMPOSED))),
        )

        assertEquals(
            "msf:9",
            SafTreePathResolver.walkDocumentId(
                "tree",
                listOf(COMPOSED),
                provider::listChildren,
            ),
        )
    }

    @Test
    fun `an exact name still wins over another file's normalization alias`() {
        val provider = FakeProvider(
            mapOf(
                "tree" to listOf(
                    SafChildDocument("msf:decomposed", DECOMPOSED),
                    SafChildDocument("msf:composed", COMPOSED),
                ),
            ),
        )

        assertEquals(
            "msf:decomposed",
            SafTreePathResolver.walkDocumentId(
                "tree",
                listOf(DECOMPOSED),
                provider::listChildren,
            ),
        )
        assertEquals(
            "msf:composed",
            SafTreePathResolver.walkDocumentId(
                "tree",
                listOf(COMPOSED),
                provider::listChildren,
            ),
        )
    }

    @Test
    fun `normalization does not make different names match`() {
        val provider = FakeProvider(
            mapOf("tree" to listOf(SafChildDocument("msf:9", "ぱぴぷ.jpg"))),
        )

        assertNull(
            SafTreePathResolver.walkDocumentId(
                "tree",
                listOf("ばびぶ.jpg"),
                provider::listChildren,
            ),
        )
    }

    @Test
    fun `leaves ascii names untouched`() {
        assertEquals("Volume 1.mokuro", SafTreePathResolver.canonicalName("Volume 1.mokuro"))
    }

    @Test
    fun `indexes children under both their reported and canonical names`() {
        val decomposed = "が.jpg"
        val index = SafTreePathResolver.indexChildren(
            listOf(SafChildDocument("msf:9", decomposed)),
        )

        assertEquals("msf:9", SafTreePathResolver.lookupChild(index, decomposed))
        assertEquals("msf:9", SafTreePathResolver.lookupChild(index, "が.jpg"))
        assertNull(SafTreePathResolver.lookupChild(index, "ほか.jpg"))
    }

    private companion object {
        const val TREE = "content://com.android.providers.downloads.documents/tree/downloads"

        // Derived rather than written out: how a literal is stored in this
        // file is not under the test's control, and an editor or formatter
        // can silently renormalize it, which would leave both constants
        // equal and the normalization cases passing vacuously.
        private const val KANA = "がぎぐ.jpg"

        /** One code point per kana. */
        val COMPOSED: String = Normalizer.normalize(KANA, Normalizer.Form.NFC)

        /** Base kana plus a combining dakuten. */
        val DECOMPOSED: String = Normalizer.normalize(KANA, Normalizer.Form.NFD)

    }
}
