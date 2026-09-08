package moe.matthew.mekuru.backup

import java.io.BufferedOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.Channels
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream
import kotlin.random.Random

/** Fixtures shared by the job tests: a small library, a plan, read-back. */
object JobTestSupport {
    fun write(file: File, bytes: ByteArray): File {
        file.parentFile?.mkdirs()
        file.writeBytes(bytes)
        return file
    }

    fun write(file: File, text: String): File = write(file, text.toByteArray(Charsets.UTF_8))

    /** Five sources: three deflated sidecars and two stored payload files. */
    fun seedSources(dir: File): List<PlanEntry> {
        val manifest = write(File(dir, "manifest.json"), "{\"format\":1}")
        val settings = write(File(dir, "settings.mekuru"), "{\"version\":1}")
        val db = write(File(dir, "mekuru_db.sqlite"), ByteArray(300 * 1024) { (it % 7).toByte() })
        val epub = write(File(dir, "books/book_1_abcdef12/本.epub"), Random(1).nextBytes(120 * 1024))
        val page = write(File(dir, "books/manga_2_00000000/001.jpg"), Random(2).nextBytes(90 * 1024))
        val fixedTime = 1_700_000_000_000L
        for (f in listOf(manifest, settings, db, epub, page)) f.setLastModified(fixedTime)
        return listOf(
            PlanEntry(manifest.path, ZipLayout.MANIFEST, manifest.length(), 6),
            PlanEntry(settings.path, ZipLayout.SETTINGS, settings.length(), 6),
            PlanEntry(db.path, ZipLayout.DATABASE, db.length(), 6),
            PlanEntry(epub.path, "Books/メロス/本.epub", epub.length(), 0),
            PlanEntry(page.path, "Manga/漫画/001.jpg", page.length(), 0),
        )
    }

    fun writePlan(store: JobStore, entries: List<PlanEntry>) {
        store.dir.mkdirs()
        store.planFile.writeText(
            entries.joinToString("") { e ->
                "{\"p\":${quote(e.path)},\"n\":${quote(e.name)},\"s\":${e.size},\"l\":${e.level},\"m\":${e.mtime}}\n"
            },
        )
    }

    private fun quote(s: String) = org.json.JSONObject.quote(s)

    fun exportSpec(target: File, entries: List<PlanEntry>): JobSpec = JobSpec(
        kind = JobSpec.KIND_EXPORT,
        displayName = target.name,
        targetPath = target.path,
        totalBytes = entries.sumOf { it.size },
    )

    fun readZip(file: File): Map<String, ByteArray> = ZipFile(file).use { zip ->
        zip.entries().asSequence().associate { it.name to zip.getInputStream(it).readBytes() }
    }

    fun readZipSequential(file: File): Map<String, ByteArray> = ZipInputStream(file.inputStream()).use { zis ->
        val out = LinkedHashMap<String, ByteArray>()
        while (true) {
            val entry = zis.nextEntry ?: break
            out[entry.name] = zis.readBytes()
        }
        out
    }

    /** Writes [entries] (name to bytes) as a complete archive with the resumable writer. */
    fun buildArchive(file: File, entries: List<Pair<String, ByteArray>>, forceZip64: Boolean = false): File {
        file.parentFile?.mkdirs()
        RandomAccessFile(file, "rw").use { raf ->
            val out = BufferedOutputStream(Channels.newOutputStream(raf.channel))
            val writer = ResumableZipWriter(out, 0L, forceZip64)
            val records = entries.map { (name, bytes) ->
                writer.add(name, 1_700_000_000_000L, if (name.endsWith(".jpg")) 0 else 6, bytes.inputStream())
            }
            writer.finish(records)
            out.flush()
        }
        return file
    }
}
