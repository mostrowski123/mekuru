package moe.matthew.mekuru.backup

import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ZipPeekTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun archive(): ByteArray = JobTestSupport.buildArchive(
        tmp.newFile("a.zip"),
        listOf(
            "manifest.json" to "{\"format\":1}".toByteArray(),
            "Books/x/big.jpg" to ByteArray(100 * 1024) { it.toByte() },
        ),
    ).readBytes()

    @Test
    fun peekTellsJsonFromAZipWithoutTheEntry() {
        val notZip = ZipPeek.peek(ByteArrayInputStream("{\"version\":1}".toByteArray()), "manifest.json")
        assertFalse(notZip.isZip)
        assertNull(notZip.text)

        val zip = archive()
        val missing = ZipPeek.peek(ByteArrayInputStream(zip), "other.json")
        assertTrue(missing.isZip)
        assertNull(missing.text)
        assertEquals("{\"format\":1}", ZipPeek.peek(ByteArrayInputStream(zip), "manifest.json").text)
    }

    @Test
    fun readEntryTextNeedsOnlyTheHeadOfTheStream() {
        val zip = archive()
        val truncated = zip.copyOf(zip.size / 2)
        assertEquals("{\"format\":1}", ZipPeek.readEntryText(ByteArrayInputStream(truncated), "manifest.json"))
        assertNull(ZipPeek.readEntryText(ByteArrayInputStream(zip), "Books/x/big.jpg", maxBytes = 1024))
    }

    @Test
    fun endRecordDistinguishesAFinishedArchiveFromATruncatedOne() {
        val zip = archive()
        assertTrue(ZipPeek.hasEndRecord(zip.copyOfRange(zip.size - 100, zip.size)))
        assertFalse(ZipPeek.hasEndRecord(zip.copyOf(zip.size - 22)))
        assertFalse(ZipPeek.hasEndRecord(ByteArray(3)))
    }
}
