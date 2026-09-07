package moe.matthew.mekuru

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.Deflater
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Streams the full-backup zip with java.util.zip so neither direction ever
 * holds more than one I/O buffer, whatever the library size. Pure JVM (no
 * Android imports) so the Gradle unit suite can round-trip it.
 *
 * Layout contract shared with the Dart side (`FullBackupManifest`): the
 * caller-supplied [Entry]s come first, in order, so `manifest.json` can be
 * peeked with [readEntryText] before the rest of the stream is read; then each
 * root's files under its prefix. Root payload is written stored (level 0)
 * because EPUB and CBZ contents are already compressed.
 */
object FullBackupArchive {
    class CancelledException : Exception("Archive operation cancelled")

    data class Entry(val file: File, val name: String, val level: Int)

    data class Plan(val entries: List<Entry>, val totalBytes: Long)

    data class WriteResult(val bytes: Long, val entries: Int, val skippedFiles: Int)

    private const val BUFFER_SIZE = 1 shl 20

    /**
     * Lists what [write] will emit: [files] first, then every regular file under
     * each root (sorted for determinism) named `prefix + relativePath`. Directories
     * named in [excludeDirNames] are pruned at any depth; `*.tmp` files (in-flight
     * atomic writes) are skipped.
     */
    fun plan(
        roots: List<Pair<File, String>>,
        files: List<Entry>,
        excludeDirNames: Set<String>,
    ): Plan {
        val entries = ArrayList<Entry>(files)
        for ((root, prefix) in roots) {
            if (!root.isDirectory) continue
            root.walkTopDown()
                .onEnter { dir -> dir == root || dir.name !in excludeDirNames }
                .filter { it.isFile && !it.name.endsWith(".tmp") }
                .sortedBy { it.path }
                .forEach { file ->
                    val relative = file.relativeTo(root).invariantSeparatorsPath
                    entries.add(Entry(file, prefix + relative, Deflater.NO_COMPRESSION))
                }
        }
        return Plan(entries, entries.sumOf { it.file.length() })
    }

    /**
     * Writes [plan] to [out] (closing it) and reports cumulative source bytes
     * through [onBytes]. A file that can no longer be opened (deleted since
     * [plan]) is counted in [WriteResult.skippedFiles] rather than failing a
     * long export near its end. Throws [CancelledException] as soon as
     * [isCancelled] returns true; the caller owns cleanup of the partial output.
     */
    fun write(
        out: OutputStream,
        plan: Plan,
        onBytes: (Long) -> Unit = {},
        isCancelled: () -> Boolean = { false },
    ): WriteResult {
        var written = 0L
        var count = 0
        var skipped = 0
        val buffer = ByteArray(BUFFER_SIZE)
        ZipOutputStream(BufferedOutputStream(out)).use { zos ->
            zos.setMethod(ZipOutputStream.DEFLATED)
            for (entry in plan.entries) {
                val input = try {
                    FileInputStream(entry.file)
                } catch (_: IOException) {
                    skipped++
                    continue
                }
                input.use { stream ->
                    zos.setLevel(entry.level)
                    zos.putNextEntry(ZipEntry(entry.name).apply { time = entry.file.lastModified() })
                    while (true) {
                        if (isCancelled()) throw CancelledException()
                        val n = stream.read(buffer)
                        if (n < 0) break
                        zos.write(buffer, 0, n)
                        written += n
                        onBytes(written)
                    }
                    zos.closeEntry()
                }
                count++
            }
        }
        return WriteResult(written, count, skipped)
    }

    data class Peek(val isZip: Boolean, val text: String?)

    /**
     * [readEntryText] plus a signature check, so the caller can tell "not a
     * zip at all" (a `.mekuru` JSON file picked by mistake) from "a zip
     * without that entry". Closes [input].
     */
    fun peek(input: InputStream, name: String, maxBytes: Int = 1 shl 20): Peek {
        val buffered = BufferedInputStream(input)
        buffered.mark(4)
        val head = ByteArray(4)
        val read = buffered.read(head)
        buffered.reset()
        val isZip = read == 4 &&
            head[0] == 0x50.toByte() && head[1] == 0x4B.toByte() &&
            head[2] == 0x03.toByte() && head[3] == 0x04.toByte()
        if (!isZip) {
            buffered.close()
            return Peek(isZip = false, text = null)
        }
        return Peek(isZip = true, text = readEntryText(buffered, name, maxBytes))
    }

    /**
     * Returns the UTF-8 text of the first entry called [name], reading no
     * further than that entry, or null when it is absent, unreadable, or
     * larger than [maxBytes]. Closes [input].
     */
    fun readEntryText(input: InputStream, name: String, maxBytes: Int = 1 shl 20): String? {
        ZipInputStream(input).use { zis ->
            while (true) {
                val entry = try {
                    zis.nextEntry ?: return null
                } catch (_: IOException) {
                    return null
                }
                if (entry.name != name) continue
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(8 * 1024)
                while (true) {
                    val n = zis.read(buffer)
                    if (n < 0) break
                    if (out.size() + n > maxBytes) return null
                    out.write(buffer, 0, n)
                }
                return String(out.toByteArray(), Charsets.UTF_8)
            }
        }
    }

    /**
     * Extracts every entry of [input] under [destDir] and returns the entry
     * count. [onBytes] reports compressed bytes consumed, so the document size
     * works as the progress total. Any name that would land outside [destDir]
     * raises [SecurityException] before a byte is written. Throws
     * [CancelledException] when [isCancelled] turns true; the caller deletes
     * the partial tree.
     */
    fun extract(
        input: InputStream,
        destDir: File,
        onBytes: (Long) -> Unit = {},
        isCancelled: () -> Boolean = { false },
    ): Int {
        val destCanonical = destDir.canonicalFile
        val counting = CountingInputStream(input)
        var count = 0
        val buffer = ByteArray(BUFFER_SIZE)
        ZipInputStream(counting).use { zis ->
            while (true) {
                val entry = zis.nextEntry ?: break
                val target = resolveInside(destCanonical, entry.name)
                if (entry.isDirectory) {
                    target.mkdirs()
                    continue
                }
                target.parentFile?.mkdirs()
                FileOutputStream(target).use { fos ->
                    while (true) {
                        if (isCancelled()) throw CancelledException()
                        val n = zis.read(buffer)
                        if (n < 0) break
                        fos.write(buffer, 0, n)
                        onBytes(counting.count)
                    }
                }
                count++
            }
        }
        return count
    }

    private fun resolveInside(destCanonical: File, name: String): File {
        val escapes = name.isEmpty() ||
            name.startsWith("/") ||
            name.startsWith("\\") ||
            name.split('/', '\\').any { it == ".." }
        if (escapes) throw SecurityException("Refusing zip entry that escapes the destination")
        val target = File(destCanonical, name).canonicalFile
        val inside = target.path == destCanonical.path ||
            target.path.startsWith(destCanonical.path + File.separator)
        if (!inside) throw SecurityException("Refusing zip entry that escapes the destination")
        return target
    }

    private class CountingInputStream(input: InputStream) : FilterInputStream(input) {
        @Volatile
        var count = 0L
            private set

        override fun read(): Int = super.read().also { if (it >= 0) count++ }

        override fun read(b: ByteArray, off: Int, len: Int): Int =
            super.read(b, off, len).also { if (it > 0) count += it }

        override fun skip(n: Long): Long = super.skip(n).also { if (it > 0) count += it }
    }
}
