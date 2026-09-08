package moe.matthew.mekuru.backup

import java.io.File
import java.util.zip.ZipException

/**
 * Runs one job to an [Outcome] and owns what happens to the files
 * afterwards, so the Android service is a thin wrapper and this stays
 * testable on the JVM:
 *
 * - done: the job wrote its result (export) or its EXTRACTED marker (restore);
 * - cancelled: partial output or staging removed, job dir cleared, result
 *   `cancelled`;
 * - failed for good ([JobFailedException], a corrupt archive, an escaping
 *   entry): same cleanup, result `failed:<code>`;
 * - anything else (an I/O error, a pause, a test abort): every file stays
 *   and the job resumes on the next launch. [recover] fails it after
 *   [JobStore.MAX_RESUMES_WITHOUT_PROGRESS] resumes that made no checkpoint.
 */
class FullBackupJobRunner(
    val store: JobStore,
    private val io: JobIo,
    val control: JobControl = JobControl(),
) {
    sealed interface Outcome {
        object Done : Outcome
        object Paused : Outcome
        object Cancelled : Outcome
        data class Failed(val code: String) : Outcome
    }

    /** The kind of the job in flight, for status without another file read. */
    @Volatile var kind: String? = null
        private set

    fun run(spec: JobSpec): Outcome {
        kind = spec.kind
        store.lastErrorFile.delete()
        return try {
            if (spec.isExport) ExportJob(store, spec, io, control).run() else RestoreJob(store, spec, io, control).run()
            Outcome.Done
        } catch (_: CancelledException) {
            cleanup(spec)
            store.writeResult(JobStore.resultCancelled(spec.kind))
            Outcome.Cancelled
        } catch (_: PausedException) {
            Outcome.Paused
        } catch (_: AbortedForTestException) {
            Outcome.Paused
        } catch (e: Throwable) {
            val code = definitiveFailureCode(e)
            if (code != null) {
                cleanup(spec)
                store.writeResult(JobStore.resultFailed(spec.kind, code))
                Outcome.Failed(code)
            } else {
                store.writeLastError(e.javaClass.simpleName)
                Outcome.Paused
            }
        }
    }

    /**
     * Cancels the running job unless a restore has already committed its
     * EXTRACTED marker, in which case the boot hook owns the files and the
     * answer is false.
     */
    fun requestCancel(): Boolean = synchronized(control.commitLock) {
        if (store.extractedMarker.exists()) return false
        store.markCancelled()
        control.cancelled = true
        true
    }

    /** Removes what a cancelled or failed job produced, keeping only the result. */
    fun cleanup(spec: JobSpec) {
        try {
            if (spec.isExport) io.deletePartial(spec) else spec.stagingPath?.let { JobStore.retire(File(it)) }
        } catch (_: Exception) {
            // Best effort: the next commit replaces a stale partial or staging dir.
        }
        store.clearJobFiles()
    }

    /**
     * Launch-time recovery for a job that is not running. Returns the
     * decision so the caller can start the service for [JobStore.Recovery.Resume].
     */
    fun recover(): JobStore.Recovery {
        val action = store.recoveryAction(running = false)
        when (action) {
            is JobStore.Recovery.Cleanup -> {
                val spec = store.readSpec()
                val kind = spec?.kind ?: JobSpec.KIND_EXPORT
                if (spec != null) cleanup(spec) else store.clearJobFiles()
                store.writeResult(
                    if (action.reason == JobStore.REASON_CANCELLED) {
                        JobStore.resultCancelled(kind)
                    } else {
                        JobStore.resultFailed(kind, action.reason)
                    },
                )
            }
            JobStore.Recovery.Wipe -> {
                store.clearJobFiles()
                if (store.stagingIsStale()) JobStore.retire(store.stagingDir)
            }
            JobStore.Recovery.Resume -> ZipJournal(store.journalFile).append(listOf(ZipJournal.resumeLine()))
            JobStore.Recovery.Nothing -> Unit
        }
        return action
    }

    companion object {
        /** A code when the failure cannot be fixed by trying again, else null. */
        fun definitiveFailureCode(e: Throwable): String? = when (e) {
            is JobFailedException -> e.code
            is ZipException -> "corrupt_archive"
            is SecurityException -> "unsafe_archive"
            is IllegalArgumentException, is IllegalStateException -> "bad_job"
            else -> null
        }
    }
}
