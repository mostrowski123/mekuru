package moe.matthew.mekuru.backup

import java.io.File
import java.io.FileInputStream
import java.io.IOException

/**
 * Streams the planned files into the partial document, checkpointing the
 * journal every [CHECKPOINT_BYTES] or [CHECKPOINT_ENTRIES], and finishes by
 * renaming the document. Re-running after any interruption converges:
 *
 * - no checkpoint yet: the partial is truncated to 0 and written from entry 0;
 * - a checkpoint: the partial is truncated to it and entries continue from
 *   `next` (a torn journal batch is dropped by [ZipJournal]);
 * - `finished` recorded: only the rename is left;
 * - partial gone (deleted by the user) or a target that cannot seek: a fresh
 *   partial is created and the archive starts over;
 * - a source file that vanished: counted as skipped, never fatal.
 *
 * Throws [CancelledException] / [PausedException] / [AbortedForTestException]
 * through from [JobControl.gate]; the service decides what to do with the
 * files in each case.
 */
class ExportJob(
    private val store: JobStore,
    initialSpec: JobSpec,
    private val io: JobIo,
    private val control: JobControl,
    private val checkpointBytes: Long = CHECKPOINT_BYTES,
    private val checkpointEntries: Int = CHECKPOINT_ENTRIES,
) {
    var spec: JobSpec = initialSpec
        private set

    fun run(): Map<String, Any?> {
        val plan = store.readPlan()
        val journal = ZipJournal(store.journalFile)
        var state = journal.parseExport()
        control.total = plan.sumOf { it.size }
        control.done = state.done
        control.phase = JobControl.PHASE_WRITING

        var entries = state.records.size
        var skipped = state.skipped
        var outputBytes = state.finishedBytes

        if (!state.finished) {
            var sink = io.openSink(spec)
            val canResume = sink != null && sink.seekable && sink.size() >= state.ckptOffset
            if (sink == null || (state.ckptOffset > 0 && !canResume)) {
                sink?.close()
                spec = io.createPartial(spec)
                store.writeSpec(spec)
                journal.reset()
                state = ZipJournal.ExportState.EMPTY
                entries = 0
                skipped = 0
                control.done = 0
                sink = io.openSink(spec) ?: throw JobFailedException("target_unavailable")
            }
            sink.use { s ->
                if (s.seekable) s.truncateTo(state.ckptOffset)
                val writer = ResumableZipWriter(s.stream, state.ckptOffset)
                val records = ArrayList(state.records)
                val pending = ArrayList<String>()
                var sinceCheckpoint = 0L
                var index = state.next

                fun checkpoint() {
                    s.sync()
                    pending.add(ZipJournal.ckptLine(writer.offset, index, control.done))
                    journal.append(pending)
                    pending.clear()
                    sinceCheckpoint = 0L
                }

                while (index < plan.size) {
                    control.gate()
                    val entry = plan[index]
                    val file = File(entry.path)
                    val input = try {
                        FileInputStream(file)
                    } catch (_: IOException) {
                        null
                    }
                    if (input == null) {
                        skipped++
                        pending.add(ZipJournal.skipLine(index))
                    } else {
                        input.use { stream ->
                            val base = control.done
                            val record = writer.add(
                                entry.name,
                                file.lastModified(),
                                entry.level,
                                stream,
                                onBytes = { control.done = base + it },
                                gate = control::gate,
                            )
                            records.add(record)
                            entries++
                            pending.add(ZipJournal.entryLine(index, record))
                            sinceCheckpoint += record.size
                        }
                    }
                    index++
                    if (sinceCheckpoint >= checkpointBytes || pending.size >= checkpointEntries) checkpoint()
                }
                checkpoint()
                control.phase = JobControl.PHASE_FINISHING
                writer.finish(records)
                s.sync()
                outputBytes = writer.offset
                journal.append(listOf(ZipJournal.finishedLine(outputBytes)))
            }
        }

        val finalized = io.finalizePartial(spec)
        val result = JobStore.resultDone(
            JobSpec.KIND_EXPORT,
            mapOf(
                "location" to finalized.location,
                "bytes" to outputBytes,
                "entries" to entries,
                "skippedFiles" to skipped,
                "renamed" to finalized.renamed,
            ),
        )
        store.writeResult(result)
        store.clearJobFiles()
        return result
    }

    companion object {
        const val CHECKPOINT_BYTES = 64L shl 20
        const val CHECKPOINT_ENTRIES = 500
    }
}
