package moe.matthew.mekuru

/** A child document as reported by a SAF provider's children cursor. */
data class SafChildDocument(
    val documentId: String,
    val displayName: String,
)

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
            val match = listChildren(documentId)
                .firstOrNull { it.displayName == segment }
                ?: return null
            documentId = match.documentId
        }
        return documentId
    }
}
