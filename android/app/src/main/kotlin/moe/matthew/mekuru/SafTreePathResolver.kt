package moe.matthew.mekuru

import java.text.Normalizer

/** A child document as reported by a SAF provider's children cursor. */
data class SafChildDocument(
    val documentId: String,
    val displayName: String,
    /** Bytes, or -1 when the provider reports none. */
    val size: Long = -1L,
    /** Milliseconds since the epoch, or 0 when unknown. */
    val lastModified: Long = 0L,
    val isDirectory: Boolean = false,
)

/**
 * Remembers what earlier SAF lookups learned about a tree.
 *
 * Resolving a path on a provider with opaque document IDs costs one children
 * query per path segment, and the reader resolves one path per page. On a local
 * provider that is free; on a cloud or network provider every one of those is a
 * round trip, so a 200-page volume would pay for the same directory listings
 * over and over. Caching turns page two onwards into map lookups.
 *
 * Entries are only ever populated from successful lookups. A failed read
 * invalidates the whole tree via [invalidateTree] so a retry starts cold rather
 * than re-using an ID that has since gone away.
 *
 * Safe for concurrent use: every SAF method channel call runs on its own
 * thread.
 */
class SafResolutionCache(private val maxEntries: Int = 512) {

    private companion object {
        /** Cannot occur in a URI or a file name. */
        val SEPARATOR: String = 0.toChar().toString()
    }

    private fun <K, V> lru(): MutableMap<K, V> =
        object : LinkedHashMap<K, V>(16, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean =
                size > maxEntries
        }

    private val documentIds = lru<String, String>()
    private val childIndexes = lru<String, Map<String, String>>()
    private val opaqueTrees = mutableSetOf<String>()
    private val lock = Any()

    // NUL-separated so the two halves cannot run together: a space would
    // let tree "a" + path "b c" collide with tree "a b" + path "c", and
    // relative paths routinely contain spaces.
    private fun key(treeUri: String, suffix: String) =
        treeUri + SEPARATOR + suffix

    fun documentId(treeUri: String, relativePath: String): String? =
        synchronized(lock) { documentIds[key(treeUri, relativePath)] }

    fun putDocumentId(treeUri: String, relativePath: String, documentId: String) {
        synchronized(lock) { documentIds[key(treeUri, relativePath)] = documentId }
    }

    /** Display-name-to-document-ID index for one directory, if already read. */
    fun childIndex(treeUri: String, parentDocumentId: String): Map<String, String>? =
        synchronized(lock) { childIndexes[key(treeUri, parentDocumentId)] }

    fun putChildIndex(
        treeUri: String,
        parentDocumentId: String,
        index: Map<String, String>,
    ) {
        synchronized(lock) { childIndexes[key(treeUri, parentDocumentId)] = index }
    }

    /**
     * Whether this tree is known to reject appended document IDs, so the cheap
     * path-shaped attempt can be skipped instead of costing a doomed query.
     */
    fun isKnownOpaque(treeUri: String): Boolean =
        synchronized(lock) { treeUri in opaqueTrees }

    fun markOpaque(treeUri: String) {
        synchronized(lock) { opaqueTrees.add(treeUri) }
    }

    /** Drops everything learned about [treeUri]. */
    fun invalidateTree(treeUri: String) {
        val prefix = treeUri + SEPARATOR
        synchronized(lock) {
            documentIds.keys.removeAll { it.startsWith(prefix) }
            childIndexes.keys.removeAll { it.startsWith(prefix) }
            opaqueTrees.remove(treeUri)
        }
    }

    fun clear() {
        synchronized(lock) {
            documentIds.clear()
            childIndexes.clear()
            opaqueTrees.clear()
        }
    }
}

/**
 * Maps a path relative to a SAF tree root onto the provider's real document ID.
 *
 * SAF document IDs are opaque by contract. Only path-shaped providers — chiefly
 * `com.android.externalstorage.documents`, whose IDs look like
 * `primary:Download/Manga` — encode the path in the ID, so deriving a child's
 * ID by appending to its parent's works there and nowhere else. Providers such
 * as `com.android.providers.downloads.documents` (`msf:1001`) and the cloud,
 * MTP and network providers hand out IDs with no relationship to the path, and
 * appending to one names a document that does not exist.
 *
 * Resolution therefore tries the cheap append first and falls back to walking
 * the tree a segment at a time, matching display names against each children
 * cursor — the same approach as `DocumentFile.findFile()`.
 *
 * Deliberately free of Android imports so it can be unit tested on the JVM.
 */
object SafTreePathResolver {

    /**
     * Splits [relativePath] into segments relative to the tree root.
     *
     * Returns an empty list for the tree root itself, and `null` when the path
     * tries to escape the tree via `..`.
     */
    fun splitSegments(relativePath: String): List<String>? {
        if (relativePath.isBlank() || relativePath == ".") return emptyList()
        val segments = relativePath
            .replace('\\', '/')
            .split('/')
            .filter { it.isNotEmpty() && it != "." }
        if (segments.any { it == ".." }) return null
        return segments
    }

    /**
     * Appends [segments] to [treeDocumentId] — the fast path, valid only for
     * path-shaped providers.
     *
     * Volume roots arrive as `primary:` with nothing after the colon, so no
     * separator is inserted there; `primary:` + `Vol 1.mokuro` has to produce
     * `primary:Vol 1.mokuro`, not `primary:/Vol 1.mokuro`.
     */
    fun joinDocumentId(treeDocumentId: String, segments: List<String>): String {
        if (segments.isEmpty()) return treeDocumentId
        val suffix = segments.joinToString("/")
        val needsSeparator = treeDocumentId.isNotEmpty() &&
            !treeDocumentId.endsWith(':') &&
            !treeDocumentId.endsWith('/')
        return if (needsSeparator) "$treeDocumentId/$suffix" else "$treeDocumentId$suffix"
    }

    /**
     * Canonical form used when a display name does not match byte for byte.
     *
     * The same Japanese filename can be encoded two ways — `が` is one code
     * point composed (NFC) and two decomposed (NFD) — and archives written on
     * macOS are decomposed. A mokuro manifest and the provider serving the
     * files can disagree, so an exact miss is retried against this form. NFC
     * and NFD are the same text, so this matches equal names, not similar ones.
     */
    fun canonicalName(displayName: String): String =
        Normalizer.normalize(displayName, Normalizer.Form.NFC)

    /**
     * Builds the display-name lookup for one directory.
     *
     * Names are indexed as reported, then again under [canonicalName] when that
     * differs. Raw names are inserted first so a file named exactly as
     * requested always wins over another file's normalization alias.
     */
    fun indexChildren(children: List<SafChildDocument>): Map<String, String> {
        val index = LinkedHashMap<String, String>(children.size * 2)
        for (child in children) {
            index.putIfAbsent(child.displayName, child.documentId)
        }
        for (child in children) {
            val canonical = canonicalName(child.displayName)
            if (canonical != child.displayName) {
                index.putIfAbsent(canonical, child.documentId)
            }
        }
        return index
    }

    /** Looks [segment] up in an index built by [indexChildren]. */
    fun lookupChild(index: Map<String, String>, segment: String): String? =
        index[segment] ?: index[canonicalName(segment)]

    /**
     * Walks [segments] down from [treeDocumentId], resolving each one to the
     * provider's own document ID via [listChildren].
     *
     * Returns `null` as soon as a segment has no matching child.
     */
    fun walkDocumentId(
        treeDocumentId: String,
        segments: List<String>,
        listChildren: (parentDocumentId: String) -> List<SafChildDocument>,
    ): String? {
        var documentId = treeDocumentId
        for (segment in segments) {
            documentId = lookupChild(indexChildren(listChildren(documentId)), segment)
                ?: return null
        }
        return documentId
    }

    /**
     * Resolves [segments] using [cache], reading only the directories it has
     * not already seen.
     *
     * Each prefix is cached as it is resolved, so sibling lookups under a
     * directory already visited — every page after the first — cost no provider
     * calls at all.
     */
    fun resolveCached(
        treeUri: String,
        treeDocumentId: String,
        segments: List<String>,
        cache: SafResolutionCache,
        listChildren: (parentDocumentId: String) -> List<SafChildDocument>,
    ): String? {
        if (segments.isEmpty()) return treeDocumentId

        cache.documentId(treeUri, segments.joinToString("/"))?.let { return it }

        var documentId = treeDocumentId
        segments.forEachIndexed { index, segment ->
            val parentId = documentId
            val childIndex = cache.childIndex(treeUri, parentId)
                ?: indexChildren(listChildren(parentId)).also {
                    cache.putChildIndex(treeUri, parentId, it)
                }
            documentId = lookupChild(childIndex, segment) ?: return null
            cache.putDocumentId(
                treeUri,
                segments.subList(0, index + 1).joinToString("/"),
                documentId,
            )
        }
        return documentId
    }
}
