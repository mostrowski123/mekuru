package moe.matthew.mekuru.backup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ZipJournalTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun record(i: Int) = ResumableZipWriter.EntryRecord("e$i", 1000L, i.toLong(), 10L, 20L, i * 100L)

    @Test
    fun exportParseKeepsOnlyCheckpointedBatches() {
        val journal = ZipJournal(tmp.newFile("j"))
        journal.append(listOf(ZipJournal.entryLine(0, record(0)), ZipJournal.entryLine(1, record(1))))
        journal.append(listOf(ZipJournal.ckptLine(300L, 2, 40L)))
        journal.append(listOf(ZipJournal.skipLine(2), ZipJournal.entryLine(3, record(3))))

        val state = journal.parseExport()
        assertEquals(listOf(record(0), record(1)), state.records)
        assertEquals(0, state.skipped)
        assertEquals(300L, state.ckptOffset)
        assertEquals(2, state.next)
        assertEquals(40L, state.done)
        assertFalse(state.finished)
    }

    @Test
    fun aTornLastLineIsDropped() {
        val file = tmp.newFile("j")
        val journal = ZipJournal(file)
        journal.append(listOf(ZipJournal.entryLine(0, record(0)), ZipJournal.ckptLine(100L, 1, 20L)))
        file.appendText("{\"e\":1,\"n\":\"e1\",\"mt\":1000,\"crc\":1,\"cs\":10,\"s\"")

        val state = journal.parseExport()
        assertEquals(1, state.records.size)
        assertEquals(100L, state.ckptOffset)
    }

    @Test
    fun resumesAreCountedSinceTheLastCheckpoint() {
        val journal = ZipJournal(tmp.newFile("j"))
        journal.append(listOf(ZipJournal.resumeLine(), ZipJournal.resumeLine()))
        assertEquals(2, journal.resumesSinceCheckpoint())
        journal.append(listOf(ZipJournal.ckptLine(10L, 1, 5L), ZipJournal.resumeLine()))
        assertEquals(1, journal.resumesSinceCheckpoint())
    }

    @Test
    fun finishedCarriesTheArchiveSize() {
        val journal = ZipJournal(tmp.newFile("j"))
        journal.append(listOf(ZipJournal.ckptLine(10L, 1, 5L), ZipJournal.finishedLine(1234L)))
        val state = journal.parseExport()
        assertTrue(state.finished)
        assertEquals(1234L, state.finishedBytes)
    }

    @Test
    fun restoreParseCommitsNamesAtCheckpoints() {
        val journal = ZipJournal(tmp.newFile("j"))
        journal.append(listOf(ZipJournal.nameLine("books/a/1.jpg"), ZipJournal.restoreCkptLine(50L)))
        journal.append(listOf(ZipJournal.nameLine("books/a/2.jpg")))

        val state = journal.parseRestore()
        assertEquals(setOf("books/a/1.jpg"), state.names)
        assertEquals(50L, state.done)
    }

    @Test
    fun aMissingJournalIsEmpty() {
        val state = ZipJournal(tmp.root.resolve("absent")).parseExport()
        assertEquals(ZipJournal.ExportState.EMPTY, state)
    }
}
