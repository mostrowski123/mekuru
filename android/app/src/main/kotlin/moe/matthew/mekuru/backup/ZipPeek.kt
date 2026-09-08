package moe.matthew.mekuru.backup

import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.zip.ZipInputStream

/** What a restore learns about an archive before committing to it. */
object ZipPeek {
    data class Result(val isZip: Boolean, val text: String?)

    /** Bytes of tail that can hold an end-of-central-directory record. */
    const val END_RECORD_TAIL = (64 shl 10) + 22

    private val LOCAL_SIGNATURE = byteArrayOf(0x50, 0x4B, 0x03, 0x04)
    private val END_SIGNATURE = byteArrayOf(0x50, 0x4B, 0x05, 0x06)

    /**
     * [readEntryText] plus a signature check, so the caller can tell "not a
     * zip at all" (a `.mekuru` JSON file picked by mistake) from "a zip
     * without that entry". Closes [input].
     */
    fun peek(input: InputStream, name: String, maxBytes: Int = 1 shl 20): Result {
        val buffered = BufferedInputStream(input)
        buffered.mark(4)
        val head = ByteArray(4)
        val read = buffered.read(head)
        buffered.reset()
        if (read != 4 || !head.contentEquals(LOCAL_SIGNATURE)) {
            buffered.close()
            return Result(isZip = false, text = null)
        }
        return Result(isZip = true, text = readEntryText(buffered, name, maxBytes))
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
     * True when [tail] (the last [END_RECORD_TAIL] bytes of a file, or the
     * whole file if shorter) contains an end-of-central-directory signature:
     * a zip that was written to completion, as opposed to one cut short by a
     * crash or an interrupted copy.
     */
    fun hasEndRecord(tail: ByteArray): Boolean {
        var i = tail.size - END_SIGNATURE.size
        while (i >= 0) {
            if (tail[i] == END_SIGNATURE[0] &&
                tail[i + 1] == END_SIGNATURE[1] &&
                tail[i + 2] == END_SIGNATURE[2] &&
                tail[i + 3] == END_SIGNATURE[3]
            ) {
                return true
            }
            i--
        }
        return false
    }
}
