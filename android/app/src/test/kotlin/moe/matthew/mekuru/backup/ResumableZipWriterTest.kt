package moe.matthew.mekuru.backup

import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.Channels
import java.util.zip.ZipFile
import kotlin.random.Random
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The writer must produce archives that stock readers accept and that are
 * byte-identical whether written in one go or across a resume.
 */
class ResumableZipWriterTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val mtime = 1_700_000_000_000L

    private val samples: List<Triple<String, ByteArray, Int>> = listOf(
        Triple("Books/メロス/本.epub", Random(3).nextBytes(200 * 1024), 0),
        Triple("Mekuru data/settings.mekuru", "{\"version\":1}".toByteArray(), 6),
        Triple("empty.txt", ByteArray(0), 0),
        Triple("Mekuru data/mekuru_db.sqlite", ByteArray(64 * 1024) { (it % 5).toByte() }, 6),
    )

    private fun writeAll(file: File, forceZip64: Boolean = false): List<ResumableZipWriter.EntryRecord> {
        RandomAccessFile(file, "rw").use { raf ->
            val out = BufferedOutputStream(Channels.newOutputStream(raf.channel))
            val writer = ResumableZipWriter(out, 0L, forceZip64)
            val records = samples.map { (name, bytes, level) -> writer.add(name, mtime, level, bytes.inputStream()) }
            writer.finish(records)
            out.flush()
            return records
        }
    }

    @Test
    fun roundTripsThroughZipFileAndZipInputStream() {
        val file = tmp.newFile("a.zip")
        val records = writeAll(file)

        val random = JobTestSupport.readZip(file)
        val sequential = JobTestSupport.readZipSequential(file)
        assertEquals(samples.map { it.first }, random.keys.toList())
        assertEquals(samples.map { it.first }, sequential.keys.toList())
        for ((name, bytes, _) in samples) {
            assertArrayEquals(name, bytes, random[name])
            assertArrayEquals(name, bytes, sequential[name])
        }
        ZipFile(file).use { zip ->
            for (record in records) {
                val entry = zip.getEntry(record.name)
                assertEquals(record.size, entry.size)
                assertEquals(record.csize, entry.compressedSize)
                assertEquals(record.crc, entry.crc)
            }
        }
    }

    @Test
    fun deflateLevelIsAppliedPerEntry() {
        val zeros = ByteArray(256 * 1024)
        fun compressedSize(level: Int): Long {
            val writer = ResumableZipWriter(ByteArrayOutputStream(), 0L)
            return writer.add("zeros.bin", mtime, level, zeros.inputStream()).csize
        }
        assertTrue(compressedSize(0) > zeros.size)
        assertTrue(compressedSize(6) < 4 * 1024)
    }

    @Test
    fun forcedZip64RecordsAreReadBack() {
        val file = tmp.newFile("z64.zip")
        val records = writeAll(file, forceZip64 = true)

        val random = JobTestSupport.readZip(file)
        val sequential = JobTestSupport.readZipSequential(file)
        for ((name, bytes, _) in samples) {
            assertArrayEquals(name, bytes, random[name])
            assertArrayEquals(name, bytes, sequential[name])
        }
        ZipFile(file).use { zip ->
            assertEquals(samples.size, zip.size())
            for (record in records) {
                val entry = zip.getEntry(record.name)
                assertEquals(record.size, entry.size)
                assertEquals(record.csize, entry.compressedSize)
            }
        }
    }

    @Test
    fun aResumedWriteIsByteIdenticalToOneShot() {
        val oneShot = tmp.newFile("one.zip")
        writeAll(oneShot)

        val resumed = tmp.newFile("two.zip")
        val records = ArrayList<ResumableZipWriter.EntryRecord>()
        var offset = 0L
        // Session 1: two entries, then the process "dies".
        RandomAccessFile(resumed, "rw").use { raf ->
            val out = BufferedOutputStream(Channels.newOutputStream(raf.channel))
            val writer = ResumableZipWriter(out, 0L)
            for ((name, bytes, level) in samples.take(2)) records.add(writer.add(name, mtime, level, bytes.inputStream()))
            out.flush()
            offset = writer.offset
            assertEquals(offset, raf.length())
        }
        // Session 2: a fresh writer continues at the recorded offset.
        RandomAccessFile(resumed, "rw").use { raf ->
            raf.channel.position(offset)
            val out = BufferedOutputStream(Channels.newOutputStream(raf.channel))
            val writer = ResumableZipWriter(out, offset)
            for ((name, bytes, level) in samples.drop(2)) records.add(writer.add(name, mtime, level, bytes.inputStream()))
            writer.finish(records)
            out.flush()
        }
        assertArrayEquals(oneShot.readBytes(), resumed.readBytes())
    }

    @Test
    fun theGateStopsTheWrite() {
        val writer = ResumableZipWriter(ByteArrayOutputStream(), 0L)
        var calls = 0
        try {
            writer.add("x.bin", mtime, 0, ByteArray(1 shl 20).inputStream(), gate = {
                if (++calls == 2) throw PausedException()
            })
            fail("expected the gate to stop the write")
        } catch (_: PausedException) {
            assertEquals(2, calls)
        }
    }
}
