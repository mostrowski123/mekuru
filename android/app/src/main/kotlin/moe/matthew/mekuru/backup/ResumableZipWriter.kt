package moe.matthew.mekuru.backup

import java.io.InputStream
import java.io.OutputStream
import java.util.Calendar
import java.util.zip.CRC32
import java.util.zip.Deflater

/**
 * Writes a zip in the exact on-disk shape `java.util.zip.ZipOutputStream`
 * produces in streaming mode (data descriptors, UTF-8 names, every entry
 * DEFLATED, ZIP64 records only where a field overflows), but keeps its state
 * in plain values the caller persists: an export can stop after any entry and
 * continue later, from the same byte offset, with a fresh instance.
 * ZipOutputStream cannot do that: its entry table and byte counter are
 * private and die with the process.
 *
 * The caller owns [out] (buffer it, flush it before syncing the file) and the
 * list of [EntryRecord]s; [finish] turns that list into the central directory.
 * Every entry is DEFLATED because `ZipInputStream` refuses STORED entries
 * with a data descriptor; level 0 still yields stored blocks, so already
 * compressed payload costs only the block headers.
 *
 * [forceZip64] exists for tests only: it writes the ZIP64 central-directory
 * extra and end records for small archives so that branch is exercised
 * without multi-gigabyte fixtures. Data descriptors are never forced; their
 * width is decided by the actual sizes, exactly as ZipInputStream expects.
 */
class ResumableZipWriter(
    private val out: OutputStream,
    startOffset: Long,
    private val forceZip64: Boolean = false,
) {
    data class EntryRecord(
        val name: String,
        val mtimeMs: Long,
        val crc: Long,
        val csize: Long,
        val size: Long,
        val offset: Long,
    )

    /** Bytes handed to [out] so far, counted from the start of the archive. */
    var offset: Long = startOffset
        private set

    private val inBuf = ByteArray(IO_BUFFER)
    private val outBuf = ByteArray(IO_BUFFER)

    /**
     * Appends one entry. [gate] runs before every input buffer and may throw
     * to stop the write (cancel, pause); [onBytes] gets cumulative source
     * bytes for progress.
     */
    fun add(
        name: String,
        mtimeMs: Long,
        level: Int,
        input: InputStream,
        onBytes: (Long) -> Unit = {},
        gate: () -> Unit = {},
    ): EntryRecord {
        val nameBytes = name.toByteArray(Charsets.UTF_8)
        val locOffset = offset
        writeInt(LOCSIG)
        writeShort(VERSION_DEFAULT)
        writeShort(FLAGS)
        writeShort(METHOD_DEFLATED)
        writeInt(dosTime(mtimeMs))
        writeInt(0) // crc, csize, size follow in the data descriptor
        writeInt(0)
        writeInt(0)
        writeShort(nameBytes.size)
        writeShort(0)
        writeBytes(nameBytes)

        val crc = CRC32()
        val deflater = Deflater(level, true)
        var size = 0L
        var csize = 0L
        try {
            while (true) {
                gate()
                val n = input.read(inBuf)
                if (n < 0) break
                crc.update(inBuf, 0, n)
                size += n
                deflater.setInput(inBuf, 0, n)
                while (!deflater.needsInput()) csize += drain(deflater)
                onBytes(size)
            }
            deflater.finish()
            while (!deflater.finished()) csize += drain(deflater)
        } finally {
            deflater.end()
        }

        writeInt(EXTSIG)
        writeInt(crc.value)
        if (csize >= ZIP64_MAGICVAL || size >= ZIP64_MAGICVAL) {
            writeLong(csize)
            writeLong(size)
        } else {
            writeInt(csize)
            writeInt(size)
        }
        return EntryRecord(name, mtimeMs, crc.value, csize, size, locOffset)
    }

    /** Writes the central directory and end records for [records], in order. */
    fun finish(records: List<EntryRecord>) {
        val cenStart = offset
        for (record in records) writeCen(record)
        writeEnd(cenStart, offset - cenStart, records.size)
        out.flush()
    }

    private fun drain(deflater: Deflater): Long {
        val n = deflater.deflate(outBuf)
        if (n > 0) {
            out.write(outBuf, 0, n)
            offset += n
        }
        return n.toLong()
    }

    private fun writeCen(r: EntryRecord) {
        val nameBytes = r.name.toByteArray(Charsets.UTF_8)
        var csize = r.csize
        var size = r.size
        var locOffset = r.offset
        var zip64Len = 0
        if (forceZip64 || r.csize >= ZIP64_MAGICVAL) {
            csize = ZIP64_MAGICVAL
            zip64Len += 8
        }
        if (forceZip64 || r.size >= ZIP64_MAGICVAL) {
            size = ZIP64_MAGICVAL
            zip64Len += 8
        }
        if (forceZip64 || r.offset >= ZIP64_MAGICVAL) {
            locOffset = ZIP64_MAGICVAL
            zip64Len += 8
        }
        val zip64 = zip64Len > 0
        val version = if (zip64) VERSION_ZIP64 else VERSION_DEFAULT

        writeInt(CENSIG)
        writeShort(version) // made by
        writeShort(version) // needed to extract
        writeShort(FLAGS)
        writeShort(METHOD_DEFLATED)
        writeInt(dosTime(r.mtimeMs))
        writeInt(r.crc)
        writeInt(csize)
        writeInt(size)
        writeShort(nameBytes.size)
        writeShort(if (zip64) zip64Len + 4 else 0) // extra length
        writeShort(0) // comment length
        writeShort(0) // disk number start
        writeShort(0) // internal attributes
        writeInt(0) // external attributes
        writeInt(locOffset)
        writeBytes(nameBytes)
        if (zip64) {
            writeShort(ZIP64_EXTID)
            writeShort(zip64Len)
            if (size == ZIP64_MAGICVAL) writeLong(r.size)
            if (csize == ZIP64_MAGICVAL) writeLong(r.csize)
            if (locOffset == ZIP64_MAGICVAL) writeLong(r.offset)
        }
    }

    private fun writeEnd(cenOffset: Long, cenLength: Long, count: Int) {
        var xlen = cenLength
        var xoff = cenOffset
        var xcount = count
        var zip64 = forceZip64
        if (xlen >= ZIP64_MAGICVAL) {
            xlen = ZIP64_MAGICVAL
            zip64 = true
        }
        if (xoff >= ZIP64_MAGICVAL) {
            xoff = ZIP64_MAGICVAL
            zip64 = true
        }
        if (xcount >= ZIP64_MAGICCOUNT) {
            xcount = ZIP64_MAGICCOUNT
            zip64 = true
        }
        if (zip64) {
            // Forced mode also masks the END fields so a reader must consult
            // the ZIP64 records, as it would for a real >4 GiB archive.
            if (forceZip64) {
                xlen = ZIP64_MAGICVAL
                xoff = ZIP64_MAGICVAL
                xcount = ZIP64_MAGICCOUNT
            }
            val end64Offset = offset
            writeInt(ZIP64_ENDSIG)
            writeLong((ZIP64_ENDHDR - 12).toLong())
            writeShort(VERSION_ZIP64)
            writeShort(VERSION_ZIP64)
            writeInt(0) // this disk
            writeInt(0) // disk with the central directory
            writeLong(count.toLong())
            writeLong(count.toLong())
            writeLong(cenLength)
            writeLong(cenOffset)
            writeInt(ZIP64_LOCSIG)
            writeInt(0)
            writeLong(end64Offset)
            writeInt(1)
        }
        writeInt(ENDSIG)
        writeShort(0)
        writeShort(0)
        writeShort(xcount)
        writeShort(xcount)
        writeInt(xlen)
        writeInt(xoff)
        writeShort(0) // comment length
    }

    private fun writeBytes(bytes: ByteArray) {
        out.write(bytes)
        offset += bytes.size
    }

    private fun writeShort(v: Int) {
        out.write(v and 0xFF)
        out.write((v ushr 8) and 0xFF)
        offset += 2
    }

    private fun writeInt(v: Long) {
        for (shift in 0 until 32 step 8) out.write(((v ushr shift) and 0xFF).toInt())
        offset += 4
    }

    private fun writeInt(v: Int) = writeInt(v.toLong() and 0xFFFFFFFFL)

    private fun writeLong(v: Long) {
        for (shift in 0 until 64 step 8) out.write(((v ushr shift) and 0xFF).toInt())
        offset += 8
    }

    companion object {
        private const val IO_BUFFER = 1 shl 16
        private const val LOCSIG = 0x04034b50L
        private const val EXTSIG = 0x08074b50L
        private const val CENSIG = 0x02014b50L
        private const val ENDSIG = 0x06054b50L
        private const val ZIP64_ENDSIG = 0x06064b50L
        private const val ZIP64_LOCSIG = 0x07064b50L
        private const val ZIP64_ENDHDR = 56
        private const val ZIP64_EXTID = 0x0001
        private const val ZIP64_MAGICVAL = 0xFFFFFFFFL
        private const val ZIP64_MAGICCOUNT = 0xFFFF
        private const val VERSION_DEFAULT = 20
        private const val VERSION_ZIP64 = 45
        private const val METHOD_DEFLATED = 8

        /** Bit 3: sizes in a data descriptor; bit 11: UTF-8 names. */
        private const val FLAGS = 0x0808

        /** MS-DOS date/time, as ZipEntry.setTime would store it. */
        fun dosTime(ms: Long): Long {
            val cal = Calendar.getInstance()
            cal.timeInMillis = ms
            val year = cal.get(Calendar.YEAR)
            if (year < 1980) return ((1 shl 21) or (1 shl 16)).toLong()
            val value = ((year - 1980) shl 25) or
                ((cal.get(Calendar.MONTH) + 1) shl 21) or
                (cal.get(Calendar.DAY_OF_MONTH) shl 16) or
                (cal.get(Calendar.HOUR_OF_DAY) shl 11) or
                (cal.get(Calendar.MINUTE) shl 5) or
                (cal.get(Calendar.SECOND) shr 1)
            return value.toLong() and 0xFFFFFFFFL
        }
    }
}
