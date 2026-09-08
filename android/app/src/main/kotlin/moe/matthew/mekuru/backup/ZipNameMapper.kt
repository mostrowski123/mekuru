package moe.matthew.mekuru.backup

import java.io.File

/**
 * The archive layout, shared by contract with the Dart side
 * (`FullBackupManifest`): a person unzipping the file finds their books by
 * title, and the app finds its own files under one folder.
 */
object ZipLayout {
    const val MANIFEST = "manifest.json"
    const val README = "README.txt"
    const val DATA_PREFIX = "Mekuru data/"
    const val COVERS_PREFIX = DATA_PREFIX + "covers/"
    const val DATABASE_FILE = "mekuru_db.sqlite"
    const val SETTINGS_FILE = "settings.mekuru"
    const val DATABASE = DATA_PREFIX + DATABASE_FILE
    const val SETTINGS = DATA_PREFIX + SETTINGS_FILE
    const val BOOKS_DIR = "books"
}

/**
 * Maps archive entry names back to the on-device layout under the staging
 * directory using the manifest's `folders` map (zip prefix → import
 * directory name). Entries that belong to no known place are skipped rather
 * than failing a multi-gigabyte restore.
 */
class ZipNameMapper(folders: Map<String, String>) {
    private val folders: Map<String, String> =
        folders.mapKeys { (key, _) -> if (key.endsWith("/")) key else "$key/" }

    /** Path relative to staging, or null when the entry is not restored. */
    fun map(name: String): String? {
        if (name.endsWith("/")) return null
        when (name) {
            ZipLayout.MANIFEST, ZipLayout.README -> return null
            ZipLayout.DATABASE -> return ZipLayout.DATABASE_FILE
            ZipLayout.SETTINGS -> return ZipLayout.SETTINGS_FILE
        }
        if (name.startsWith(ZipLayout.COVERS_PREFIX)) {
            val rest = name.removePrefix(ZipLayout.COVERS_PREFIX)
            if (rest.isEmpty() || rest.contains('/')) return null
            return "${ZipLayout.BOOKS_DIR}/$rest"
        }
        for ((prefix, dir) in folders) {
            if (!name.startsWith(prefix)) continue
            val rest = name.removePrefix(prefix)
            if (rest.isEmpty()) return null
            return "${ZipLayout.BOOKS_DIR}/$dir/$rest"
        }
        return null
    }

    companion object {
        /** Zip-slip guard: [rel] must resolve inside [destCanonical]. */
        fun resolveInside(destCanonical: File, rel: String): File {
            val escapes = rel.isEmpty() ||
                rel.startsWith("/") ||
                rel.startsWith("\\") ||
                rel.split('/', '\\').any { it == ".." }
            if (escapes) throw SecurityException("Refusing zip entry that escapes the destination")
            val target = File(destCanonical, rel).canonicalFile
            val inside = target.path == destCanonical.path ||
                target.path.startsWith(destCanonical.path + File.separator)
            if (!inside) throw SecurityException("Refusing zip entry that escapes the destination")
            return target
        }
    }
}
