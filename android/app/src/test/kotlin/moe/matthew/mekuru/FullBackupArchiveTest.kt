package moe.matthew.mekuru

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.random.Random

/**
 * The full-backup zip is written and read by [FullBackupArchive] with plain
 * java.util.zip streams. These tests pin the layout contract the Dart side
 * relies on: entry order, exclusions, byte fidelity, progress, cancellation,
 * a peekable first entry, and the zip-slip guard on extraction.
 */
class FullBackupArchiveTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun writeText(file: File, text: String): File {
        file.parentFile?.mkdirs()
        file.writeText(text, Charsets.UTF_8)
        return file
    }

    private fun writeBytes(file: File, bytes: ByteArray): File {
        file.parentFile?.mkdirs()
        file.writeBytes(bytes)
        return file
    }

    /** A books tree with one EPUB-like dir, one manga dir, trash, and a tmp file. */
    private fun seedBooks(): File {
        val books = tmp.newFolder("books")
        writeText(File(books, "book_1/content/章一.xhtml"), "<p>メロスは激怒した。</p>")
        writeText(File(books, "book_1/pages_cache.json"), "{\"imageDirPath\":\"/x\"}")
        writeBytes(File(books, "manga_2/pages/001.jpg"), Random(7).nextBytes(100 * 1024))
        writeBytes(File(books, ".trash/1_book_9/old.bin"), ByteArray(10))
        writeText(File(books, "book_1/pages_cache.json.tmp"), "partial")
        File(books, "manga_3_empty").mkdirs()
        return books
    }

    private fun topLevelFiles(): List<FullBackupArchive.Entry> {
        val manifest = writeText(tmp.newFile("manifest.json"), "{\"format\":1}")
        val settings = writeText(tmp.newFile("settings.mekuru"), "{\"version\":1}")
        return listOf(
            FullBackupArchive.Entry(manifest, "manifest.json", 6),
            FullBackupArchive.Entry(settings, "settings.mekuru", 6),
        )
    }

    @Test
    fun planListsTopLevelFilesFirstAndPrunesTrashAndTmp() {
        val books = seedBooks()
        val plan = FullBackupArchive.plan(
            files = topLevelFiles(),
            root = books,
            walked = FullBackupArchive.walk(books, setOf(".trash")),
            prefix = "books/",
        )

        val names = plan.entries.map { it.name }
        assertEquals("manifest.json", names[0])
        assertEquals("settings.mekuru", names[1])
        assertTrue(names.contains("books/book_1/content/章一.xhtml"))
        assertTrue(names.contains("books/book_1/pages_cache.json"))
        assertTrue(names.contains("books/manga_2/pages/001.jpg"))
        assertFalse(names.any { it.contains(".trash") })
        assertFalse(names.any { it.endsWith(".tmp") })
        assertFalse(names.any { it.contains("manga_3_empty") })
        assertEquals(5, names.size)

        val expectedBytes = plan.entries.sumOf { it.file.length() }
        assertEquals(expectedBytes, plan.totalBytes)
        // Book payload is stored, top-level JSON is deflated.
        assertTrue(plan.entries.filter { it.name.startsWith("books/") }.all { it.level == 0 })
    }

    @Test
    fun writeThenExtractRoundTripsEveryByte() {
        val books = seedBooks()
        val plan = FullBackupArchive.plan(
            files = topLevelFiles(),
            root = books,
            walked = FullBackupArchive.walk(books, setOf(".trash")),
            prefix = "books/",
        )

        val progress = mutableListOf<Long>()
        val zipBytes = ByteArrayOutputStream()
        val result = FullBackupArchive.write(zipBytes, plan, onBytes = { progress.add(it) })

        assertEquals(plan.entries.size, result.entries)
        assertEquals(0, result.skippedFiles)
        assertEquals(plan.totalBytes, result.bytes)
        assertEquals(plan.totalBytes, progress.last())
        assertEquals(progress, progress.sorted())

        val dest = tmp.newFolder("dest")
        val extractProgress = mutableListOf<Long>()
        val extracted = FullBackupArchive.extract(
            ByteArrayInputStream(zipBytes.toByteArray()),
            dest,
            onBytes = { extractProgress.add(it) },
        )
        assertEquals(plan.entries.size, extracted)
        assertEquals(extractProgress, extractProgress.sorted())
        assertTrue(extractProgress.last() > 0)

        for (entry in plan.entries) {
            val out = File(dest, entry.name)
            assertTrue("missing ${entry.name}", out.isFile)
            assertArrayEquals(entry.file.readBytes(), out.readBytes())
        }
        assertFalse(File(dest, "books/.trash").exists())
        assertFalse(File(dest, "books/book_1/pages_cache.json.tmp").exists())
    }

    @Test
    fun deflateLevelIsAppliedPerEntry() {
        val zeros = writeBytes(tmp.newFile("zeros.bin"), ByteArray(256 * 1024))
        fun sizeAtLevel(level: Int): Int {
            val plan = FullBackupArchive.Plan(
                listOf(FullBackupArchive.Entry(zeros, "zeros.bin", level)),
                zeros.length(),
            )
            val out = ByteArrayOutputStream()
            FullBackupArchive.write(out, plan)
            return out.size()
        }
        val stored = sizeAtLevel(0)
        val deflated = sizeAtLevel(6)
        assertTrue("stored=$stored", stored > 256 * 1024)
        assertTrue("deflated=$deflated", deflated < 4 * 1024)
    }

    @Test
    fun fileVanishingBetweenPlanAndWriteIsSkippedNotFatal() {
        val books = seedBooks()
        val plan = FullBackupArchive.plan(
            files = topLevelFiles(),
            root = books,
            walked = FullBackupArchive.walk(books, setOf(".trash")),
            prefix = "books/",
        )
        assertTrue(File(books, "manga_2/pages/001.jpg").delete())

        val out = ByteArrayOutputStream()
        val result = FullBackupArchive.write(out, plan)

        assertEquals(1, result.skippedFiles)
        assertEquals(plan.entries.size - 1, result.entries)

        val dest = tmp.newFolder("dest")
        FullBackupArchive.extract(ByteArrayInputStream(out.toByteArray()), dest)
        assertTrue(File(dest, "manifest.json").isFile)
        assertFalse(File(dest, "books/manga_2/pages/001.jpg").exists())
    }

    @Test
    fun readEntryTextFindsTheFirstEntryWithoutTheRestOfTheStream() {
        val books = seedBooks()
        val plan = FullBackupArchive.plan(
            files = topLevelFiles(),
            root = books,
            walked = FullBackupArchive.walk(books, setOf(".trash")),
            prefix = "books/",
        )
        val out = ByteArrayOutputStream()
        FullBackupArchive.write(out, plan)
        val full = out.toByteArray()

        // Cut the stream inside the second entry: a manifest peek must not
        // need the central directory or the rest of the archive.
        val truncated = full.copyOf(full.size / 2)
        val text = FullBackupArchive.readEntryText(ByteArrayInputStream(truncated), "manifest.json")
        assertEquals("{\"format\":1}", text)

        assertNull(FullBackupArchive.readEntryText(ByteArrayInputStream(full), "missing.json"))
    }

    @Test
    fun peekTellsNonZipInputApartFromAZipWithoutTheEntry() {
        val json = "{\"version\":1,\"settings\":{}}".toByteArray()
        val notZip = FullBackupArchive.peek(ByteArrayInputStream(json), "manifest.json")
        assertFalse(notZip.isZip)
        assertNull(notZip.text)

        val plan = FullBackupArchive.Plan(
            listOf(FullBackupArchive.Entry(writeText(tmp.newFile("other.json"), "{}"), "other.json", 6)),
            2,
        )
        val zip = ByteArrayOutputStream().also { FullBackupArchive.write(it, plan) }.toByteArray()
        val noEntry = FullBackupArchive.peek(ByteArrayInputStream(zip), "manifest.json")
        assertTrue(noEntry.isZip)
        assertNull(noEntry.text)

        val found = FullBackupArchive.peek(ByteArrayInputStream(zip), "other.json")
        assertEquals("{}", found.text)
    }

    @Test
    fun readEntryTextRefusesOversizedEntries() {
        val big = writeBytes(tmp.newFile("big.json"), ByteArray(2048) { 'a'.code.toByte() })
        val plan = FullBackupArchive.Plan(listOf(FullBackupArchive.Entry(big, "big.json", 0)), 2048)
        val out = ByteArrayOutputStream()
        FullBackupArchive.write(out, plan)
        assertNull(
            FullBackupArchive.readEntryText(ByteArrayInputStream(out.toByteArray()), "big.json", maxBytes = 1024),
        )
    }

    @Test
    fun extractRejectsZipSlipNamesAndWritesNothingOutside() {
        val outside = tmp.newFolder("outside")
        val dest = File(outside, "dest").apply { mkdirs() }
        for (evil in listOf("../evil.txt", "/abs.txt", "books/../../evil2.txt", "..")) {
            val bytes = ByteArrayOutputStream().also { buf ->
                ZipOutputStream(buf).use { zos ->
                    zos.putNextEntry(ZipEntry("manifest.json"))
                    zos.write("{}".toByteArray())
                    zos.closeEntry()
                    zos.putNextEntry(ZipEntry(evil))
                    zos.write("pwned".toByteArray())
                    zos.closeEntry()
                }
            }.toByteArray()
            try {
                FullBackupArchive.extract(ByteArrayInputStream(bytes), dest)
                fail("expected rejection for $evil")
            } catch (e: SecurityException) {
                // expected
            }
        }
        val leaked = outside.walkTopDown().filter { it.isFile && it.name.contains("evil") || it.name == "abs.txt" }
        assertTrue(leaked.toList().isEmpty())
    }

    @Test
    fun cancellationStopsWriteAndExtract() {
        val books = seedBooks()
        val plan = FullBackupArchive.plan(
            files = topLevelFiles(),
            root = books,
            walked = FullBackupArchive.walk(books, setOf(".trash")),
            prefix = "books/",
        )
        var writeCalls = 0
        try {
            FullBackupArchive.write(
                ByteArrayOutputStream(),
                plan,
                onBytes = { writeCalls++ },
                isCancelled = { writeCalls >= 1 },
            )
            fail("expected cancellation")
        } catch (e: FullBackupArchive.CancelledException) {
            // expected
        }

        val zip = ByteArrayOutputStream()
        FullBackupArchive.write(zip, plan)
        var extractCalls = 0
        val dest = tmp.newFolder("dest")
        try {
            FullBackupArchive.extract(
                ByteArrayInputStream(zip.toByteArray()),
                dest,
                onBytes = { extractCalls++ },
                isCancelled = { extractCalls >= 1 },
            )
            fail("expected cancellation")
        } catch (e: FullBackupArchive.CancelledException) {
            // expected
        }
    }
}
