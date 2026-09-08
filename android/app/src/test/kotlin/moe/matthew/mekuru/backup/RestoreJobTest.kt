package moe.matthew.mekuru.backup

import java.io.File
import java.io.RandomAccessFile
import java.util.zip.ZipException
import kotlin.random.Random
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RestoreJobTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private lateinit var support: File
    private lateinit var store: JobStore
    private lateinit var archive: File
    private lateinit var spec: JobSpec

    private val entries: List<Pair<String, ByteArray>> = listOf(
        "manifest.json" to "{\"format\":1}".toByteArray(),
        "README.txt" to "hello".toByteArray(),
        "Mekuru data/settings.mekuru" to "{\"version\":1}".toByteArray(),
        "Mekuru data/mekuru_db.sqlite" to ByteArray(200 * 1024) { (it % 3).toByte() },
        "Mekuru data/covers/custom_cover_9.jpg" to Random(9).nextBytes(30 * 1024),
        "Books/メロス/本.epub" to Random(1).nextBytes(150 * 1024),
        "Books/メロス/content/ch1.xhtml" to "<p>走れ</p>".toByteArray(),
        "Manga/漫画/001.jpg" to Random(2).nextBytes(120 * 1024),
        "Manga/漫画/pages_cache.json" to "{}".toByteArray(),
        "Unknown/stray.txt" to "?".toByteArray(),
    )

    private val expectedFiles = mapOf(
        "mekuru_db.sqlite" to 3,
        "settings.mekuru" to 2,
        "books/custom_cover_9.jpg" to 4,
        "books/book_1_abcdef12/本.epub" to 5,
        "books/book_1_abcdef12/content/ch1.xhtml" to 6,
        "books/manga_2_00000000/001.jpg" to 7,
        "books/manga_2_00000000/pages_cache.json" to 8,
    )

    @Before
    fun setUp() {
        support = tmp.newFolder("support")
        store = JobStore.forRoot(support)
        archive = JobTestSupport.buildArchive(File(tmp.newFolder("src"), "a.zip"), entries)
        spec = JobSpec(
            kind = JobSpec.KIND_RESTORE,
            sourceUri = archive.toURI().toString(),
            stagingPath = store.stagingDir.path,
            totalBytes = entries.sumOf { it.second.size.toLong() },
            folders = mapOf("Books/メロス/" to "book_1_abcdef12", "Manga/漫画/" to "manga_2_00000000"),
            manifestJson = "{\"format\":1,\"bookCount\":2}",
        )
        store.writeSpec(spec)
    }

    private fun run(control: JobControl = JobControl(), checkpointEntries: Int = 1) =
        RestoreJob(store, spec, FileJobIo(), control, checkpointEntries = checkpointEntries).run()

    private fun assertRestored() {
        for ((rel, index) in expectedFiles) {
            val file = File(store.stagingDir, rel)
            assertTrue("missing $rel", file.isFile)
            assertArrayEquals(rel, entries[index].second, file.readBytes())
        }
        assertFalse(File(store.stagingDir, "Unknown").exists())
        assertFalse(File(store.stagingDir, "manifest.json").exists())
        assertEquals(spec.manifestJson, store.extractedMarker.readText())
        assertFalse(store.specFile.exists())
        assertFalse(store.journalFile.exists())
        assertFalse(store.resultFile.exists())
    }

    @Test
    fun extractsIntoTheDeviceLayoutAndWritesExtractedLast() {
        val control = JobControl()
        run(control)
        assertRestored()
        assertEquals(JobControl.PHASE_FINISHING, control.phase)
        assertTrue(control.done >= expectedFiles.keys.sumOf { entries[expectedFiles[it]!!].second.size.toLong() })
    }

    @Test
    fun abortThenResumeRewritesOnlyWhatTheJournalDoesNotList() {
        try {
            run(JobControl().apply { abortAfterBytes = 300 * 1024 })
            fail("expected the abort")
        } catch (_: AbortedForTestException) {
        }
        val journaled = ZipJournal(store.journalFile).parseRestore().names
        assertTrue("some files should be checkpointed", journaled.isNotEmpty())
        assertTrue(journaled.size < expectedFiles.size)
        val ancient = 1_000_000_000_000L
        for (rel in journaled) File(store.stagingDir, rel).setLastModified(ancient)

        val control = JobControl()
        run(control)
        assertRestored()
        for (rel in journaled) assertEquals(rel, ancient, File(store.stagingDir, rel).lastModified())
        for (rel in expectedFiles.keys - journaled) assertTrue(rel, File(store.stagingDir, rel).lastModified() > ancient)
    }

    @Test
    fun aSecondRunAfterExtractedIsANoOp() {
        run()
        val marker = store.extractedMarker.readText()
        File(store.stagingDir, "books/manga_2_00000000/001.jpg").delete()
        run()
        assertEquals(marker, store.extractedMarker.readText())
        assertFalse(File(store.stagingDir, "books/manga_2_00000000/001.jpg").exists())
    }

    @Test
    fun aCorruptEntryFailsBeforeAnythingIsCommitted() {
        // Flip a byte inside the first data descriptor's payload region.
        RandomAccessFile(archive, "rw").use { raf ->
            raf.seek(30L + "manifest.json".length + 3)
            val b = raf.read()
            raf.seek(raf.filePointer - 1)
            raf.write(b xor 0x55)
        }
        try {
            run()
            fail("expected a CRC failure")
        } catch (_: ZipException) {
        }
        assertFalse(store.extractedMarker.exists())
    }

    @Test
    fun anEscapingEntryIsRefused() {
        val evil = JobTestSupport.buildArchive(
            File(tmp.newFolder("evil"), "e.zip"),
            listOf("Books/メロス/../../../evil.txt" to "pwned".toByteArray()),
        )
        spec = spec.copy(sourceUri = evil.toURI().toString())
        store.writeSpec(spec)
        try {
            run()
            fail("expected rejection")
        } catch (_: SecurityException) {
        }
        assertFalse(File(support, "evil.txt").exists())
        assertFalse(store.stagingDir.walkTopDown().any { it.name == "evil.txt" })
    }

    @Test
    fun aMissingSourceFailsForGood() {
        spec = spec.copy(sourceUri = File(tmp.root, "gone.zip").toURI().toString())
        store.writeSpec(spec)
        try {
            run()
            fail("expected source_missing")
        } catch (e: JobFailedException) {
            assertEquals("source_missing", e.code)
        }
    }

    @Test
    fun cancelStopsTheExtraction() {
        try {
            run(JobControl().apply { cancelled = true })
            fail("expected cancel")
        } catch (_: CancelledException) {
        }
        assertFalse(store.extractedMarker.exists())
    }
}
