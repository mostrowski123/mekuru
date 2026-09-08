package moe.matthew.mekuru.backup

import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.URI
import java.nio.channels.Channels
import java.nio.channels.FileChannel

/**
 * Where an export writes. [channel] is null when the target cannot seek
 * (a cloud provider handing out a pipe), in which case a resume has to
 * start the archive over.
 */
class Sink(val stream: OutputStream, private val channel: FileChannel?) : Closeable {
    val seekable: Boolean get() = channel != null

    fun size(): Long = channel?.size() ?: -1L

    fun truncateTo(offset: Long) {
        val c = channel ?: throw IllegalStateException("Sink is not seekable")
        c.truncate(offset)
        c.position(offset)
    }

    /** Flushes the buffer and forces the bytes to storage. */
    fun sync() {
        stream.flush()
        channel?.force(true)
    }

    override fun close() = stream.close()
}

data class Finalized(val location: String, val renamed: Boolean)

/**
 * The few document operations a job needs, so the runners stay pure JVM:
 * the Android implementation talks to `ContentResolver`, [FileJobIo] to the
 * filesystem for unit tests.
 */
interface JobIo {
    /** Creates a fresh `.partial` document (replacing any) and records its URI. */
    fun createPartial(spec: JobSpec): JobSpec

    /** Opens the partial for writing, or null when it no longer exists. */
    fun openSink(spec: JobSpec): Sink?

    fun deletePartial(spec: JobSpec)

    /** Gives the partial its final name; idempotent across a crash. */
    fun finalizePartial(spec: JobSpec): Finalized

    /**
     * Opens a source for reading: a planned entry ([PlanEntry.path]) or the
     * restore archive ([JobSpec.sourceUri]). Null when it is gone.
     */
    fun openEntry(path: String): InputStream?
}

/** A plain path or a `file:` URI as a stream, or null when it is not a file. */
fun openFileEntry(path: String): InputStream? {
    val file = if (path.startsWith("file:")) File(URI(path)) else File(path)
    return if (file.isFile) FileInputStream(file) else null
}

/** Creates (replacing any) the `.partial` file beside [target]. */
fun createPartialFile(target: File): File {
    val partial = File(target.path + FileJobIo.PARTIAL_SUFFIX)
    partial.parentFile?.mkdirs()
    partial.delete()
    partial.createNewFile()
    return partial
}

/**
 * Gives a finished [partial] file the name [target]; idempotent across a
 * crash: a partial already renamed is success, neither file is failure.
 */
fun finalizePartialFile(partial: File, target: File): Finalized {
    if (partial.isFile) {
        target.delete()
        if (!partial.renameTo(target)) return Finalized(partial.path, renamed = false)
    } else if (!target.isFile) {
        throw JobFailedException("partial_missing")
    }
    return Finalized(target.path, renamed = true)
}

/** Plain-file [JobIo]; [seekable] false imitates a pipe-only provider. */
class FileJobIo(private val seekable: Boolean = true) : JobIo {
    private fun partialOf(spec: JobSpec): File = File(URI(requireNotNull(spec.docUri) { "docUri" }))

    override fun createPartial(spec: JobSpec): JobSpec {
        val partial = createPartialFile(File(requireNotNull(spec.targetPath) { "targetPath" }))
        return spec.copy(docUri = partial.toURI().toString())
    }

    override fun openSink(spec: JobSpec): Sink? {
        val partial = partialOf(spec)
        if (!partial.isFile) return null
        if (!seekable) return Sink(BufferedOutputStream(FileOutputStream(partial), BUFFER), null)
        val raf = RandomAccessFile(partial, "rw")
        return Sink(BufferedOutputStream(Channels.newOutputStream(raf.channel), BUFFER), raf.channel)
    }

    override fun deletePartial(spec: JobSpec) {
        spec.docUri?.let { partialOf(spec).delete() }
    }

    override fun finalizePartial(spec: JobSpec): Finalized =
        finalizePartialFile(partialOf(spec), File(requireNotNull(spec.targetPath) { "targetPath" }))

    override fun openEntry(path: String): InputStream? = openFileEntry(path)

    companion object {
        const val PARTIAL_SUFFIX = ".partial"
        private const val BUFFER = 1 shl 16
    }
}
