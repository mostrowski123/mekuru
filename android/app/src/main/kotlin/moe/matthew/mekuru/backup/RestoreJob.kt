package moe.matthew.mekuru.backup

import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

/**
 * Unpacks the archive into the staging directory in the on-device layout
 * and writes the EXTRACTED marker last; the Dart boot hook does the rest.
 *
 * The archive is read sequentially, so a resume re-reads the entries the
 * journal already lists (`checking` phase: they inflate at memcpy speed and
 * are not written again) before extracting the rest. Files written since
 * the last checkpoint are simply overwritten. Every entry's CRC is verified
 * by `ZipInputStream`; a mismatch fails the job before anything live moves.
 *
 * ponytail: sequential resume costs O(archive) reads, not O(remaining);
 * upgrade path is a central-directory reader over the seekable "r" channel.
 */
class RestoreJob(
    private val store: JobStore,
    private val spec: JobSpec,
    private val io: JobIo,
    private val control: JobControl,
    private val checkpointBytes: Long = ExportJob.CHECKPOINT_BYTES,
    private val checkpointEntries: Int = ExportJob.CHECKPOINT_ENTRIES,
) {
    fun run() {
        val staging = File(requireNotNull(spec.stagingPath) { "stagingPath" })
        staging.mkdirs()
        if (store.extractedMarker.exists()) return

        val journal = ZipJournal(store.journalFile)
        val state = journal.parseRestore()
        control.total = spec.totalBytes
        control.done = 0L
        control.phase = if (state.names.isEmpty()) JobControl.PHASE_EXTRACTING else JobControl.PHASE_CHECKING

        val input = io.openEntry(requireNotNull(spec.sourceUri) { "sourceUri" })
            ?: throw JobFailedException("source_missing")
        val mapper = ZipNameMapper(spec.folders)
        val stagingCanonical = staging.canonicalFile
        val pending = ArrayList<String>()
        var sinceCheckpoint = 0L
        val buffer = ByteArray(BUFFER)

        fun checkpoint() {
            pending.add(ZipJournal.restoreCkptLine(control.done))
            journal.append(pending)
            pending.clear()
            sinceCheckpoint = 0L
        }

        fun drain(zis: ZipInputStream) {
            while (true) {
                control.gate()
                val n = zis.read(buffer)
                if (n < 0) break
                control.done += n
            }
        }

        ZipInputStream(BufferedInputStream(input, 1 shl 20)).use { zis ->
            while (true) {
                control.gate()
                val entry = zis.nextEntry ?: break
                val rel = mapper.map(entry.name)
                if (rel == null || rel in state.names) {
                    drain(zis)
                    continue
                }
                val target = ZipNameMapper.resolveInside(stagingCanonical, rel)
                control.phase = JobControl.PHASE_EXTRACTING
                target.parentFile?.mkdirs()
                var entryBytes = 0L
                FileOutputStream(target).use { fos ->
                    while (true) {
                        control.gate()
                        val n = zis.read(buffer)
                        if (n < 0) break
                        fos.write(buffer, 0, n)
                        entryBytes += n
                        control.done += n
                    }
                    // Durable before the journal may list it.
                    fos.fd.sync()
                }
                pending.add(ZipJournal.nameLine(rel))
                sinceCheckpoint += entryBytes
                if (sinceCheckpoint >= checkpointBytes || pending.size >= checkpointEntries) checkpoint()
            }
        }
        checkpoint()
        control.phase = JobControl.PHASE_FINISHING
        synchronized(control.commitLock) {
            control.gate()
            FileOutputStream(store.extractedMarker).use { fos ->
                fos.write((spec.manifestJson ?: "{}").toByteArray(Charsets.UTF_8))
                fos.flush()
                fos.fd.sync()
            }
        }
        store.clearJobFiles()
    }

    companion object {
        private const val BUFFER = 1 shl 16
    }
}
