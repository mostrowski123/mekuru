package moe.matthew.mekuru.backup

import java.io.File
import java.io.FileOutputStream
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** One line of `plan.jsonl`: a source file and its name in the archive. */
data class PlanEntry(val path: String, val name: String, val size: Long, val level: Int)

/**
 * The on-disk state of the one full-backup job that can exist at a time,
 * under `<appSupport>/full_backup_job/`, plus the two markers a restore
 * leaves in the staging directory. Everything here is exists-driven so any
 * launch can tell what happened from the files alone.
 *
 * - `job.json`: the [JobSpec]; present from commit until the job ends.
 * - `plan.jsonl`: export entries, written by the Dart side before commit.
 * - `journal.jsonl`: see [ZipJournal].
 * - `CANCELLED`: the user cancelled; cleanup may still be pending.
 * - `result.json`: the terminal outcome, kept until the UI consumes it.
 * - staging `EXTRACTED`: a restore's success marker; the boot hook takes over.
 */
class JobStore(val dir: File, val stagingDir: File) {
    val specFile = File(dir, "job.json")
    val planFile = File(dir, "plan.jsonl")
    val journalFile = File(dir, "journal.jsonl")
    val cancelledFile = File(dir, "CANCELLED")
    val resultFile = File(dir, "result.json")

    /** Why the last run stopped without finishing; shown while paused. */
    val lastErrorFile = File(dir, "last_error")
    val extractedMarker = File(stagingDir, EXTRACTED_MARKER)
    val readyMarker = File(stagingDir, READY_MARKER)
    val rollbackDir = File(stagingDir.parentFile, ROLLBACK_DIR_NAME)

    /** Progress of a paused job, re-read only when the journal changes. */
    private var pausedDone: Triple<Long, Long, Long>? = null

    data class Live(val kind: String, val phase: String, val done: Long, val total: Long)

    sealed interface Recovery {
        object Nothing : Recovery
        object Resume : Recovery
        data class Cleanup(val reason: String) : Recovery
        object Wipe : Recovery
    }

    fun readSpec(): JobSpec? {
        if (!specFile.exists()) return null
        return try {
            JobSpec.fromJson(JSONObject(specFile.readText(Charsets.UTF_8)))
        } catch (_: JSONException) {
            null
        }
    }

    fun writeSpec(spec: JobSpec) = writeAtomic(specFile, spec.toJson().toString())

    fun readPlan(): List<PlanEntry> {
        if (!planFile.exists()) return emptyList()
        return planFile.readLines(Charsets.UTF_8).filter { it.isNotBlank() }.map { raw ->
            val json = JSONObject(raw)
            PlanEntry(
                path = json.getString("p"),
                name = json.getString("n"),
                size = json.getLong("s"),
                level = json.getInt("l"),
            )
        }
    }

    fun isCancelled(): Boolean = cancelledFile.exists()

    fun markCancelled() = writeAtomic(cancelledFile, "")

    fun writeResult(fields: Map<String, Any?>) = writeAtomic(resultFile, JSONObject(fields).toString())

    fun readResult(): Map<String, Any?>? {
        if (!resultFile.exists()) return null
        return try {
            JSONObject(resultFile.readText(Charsets.UTF_8)).toPlainMap()
        } catch (_: JSONException) {
            null
        }
    }

    fun consumeResult(): Map<String, Any?>? {
        val result = readResult()
        resultFile.delete()
        return result
    }

    fun writeLastError(code: String) = writeAtomic(lastErrorFile, code)

    fun readLastError(): String? =
        if (lastErrorFile.exists()) lastErrorFile.readText(Charsets.UTF_8).ifBlank { null } else null

    /** Removes every job file except a pending result. */
    fun clearJobFiles() {
        dir.listFiles()?.forEach { if (it != resultFile) it.deleteRecursively() }
    }

    /** What the method channel reports; [live] is the running job, if any. */
    fun status(live: Live?): Map<String, Any?> {
        if (live != null) {
            return mapOf(
                "status" to STATUS_RUNNING,
                "kind" to live.kind,
                "phase" to live.phase,
                "done" to live.done,
                "total" to live.total,
            )
        }
        readResult()?.let { return it }
        val spec = readSpec()
        if (spec != null) {
            if (isCancelled()) return mapOf("status" to STATUS_CANCELLED, "kind" to spec.kind)
            return mapOf(
                "status" to STATUS_PAUSED,
                "kind" to spec.kind,
                "done" to pausedDone(spec),
                "total" to spec.totalBytes,
                "error" to readLastError(),
            )
        }
        if (extractedMarker.exists()) {
            return mapOf("status" to STATUS_DONE, "kind" to JobSpec.KIND_RESTORE)
        }
        return mapOf("status" to STATUS_NONE)
    }

    /** Bytes the last checkpoint promised; the poll asks twice a second. */
    private fun pausedDone(spec: JobSpec): Long {
        val key = Pair(journalFile.length(), journalFile.lastModified())
        pausedDone?.let { (length, modified, done) ->
            if (length == key.first && modified == key.second) return done
        }
        val journal = ZipJournal(journalFile)
        val done = if (spec.isExport) journal.parseExport().done else journal.parseRestore().done
        pausedDone = Triple(key.first, key.second, done)
        return done
    }

    /** The pure decision behind launch-time recovery. */
    fun recoveryAction(running: Boolean): Recovery = when {
        running -> Recovery.Nothing
        !specFile.exists() -> Recovery.Wipe
        isCancelled() -> Recovery.Cleanup(REASON_CANCELLED)
        ZipJournal(journalFile).resumesSinceCheckpoint() >= MAX_RESUMES_WITHOUT_PROGRESS ->
            Recovery.Cleanup(REASON_CRASH_LOOP)
        else -> Recovery.Resume
    }

    /** True when the staging directory belongs to nobody and can be retired. */
    fun stagingIsStale(): Boolean =
        stagingDir.exists() && !extractedMarker.exists() && !readyMarker.exists() && !specFile.exists()

    private fun writeAtomic(target: File, text: String) {
        target.parentFile?.mkdirs()
        val tmp = File(target.path + ".tmp")
        FileOutputStream(tmp).use { fos ->
            fos.write(text.toByteArray(Charsets.UTF_8))
            fos.flush()
            fos.fd.sync()
        }
        if (!tmp.renameTo(target)) {
            target.delete()
            if (!tmp.renameTo(target)) throw JobFailedException("write_failed")
        }
    }

    companion object {
        const val DIR_NAME = "full_backup_job"
        const val STAGING_DIR_NAME = "restore_staging"
        const val ROLLBACK_DIR_NAME = "restore_rollback"
        const val EXTRACTED_MARKER = "EXTRACTED"
        const val READY_MARKER = "READY"
        const val TOMBSTONE_SUFFIX = ".trash"

        const val STATUS_NONE = "none"
        const val STATUS_RUNNING = "running"
        const val STATUS_PAUSED = "paused"
        const val STATUS_DONE = "done"
        const val STATUS_CANCELLED = "cancelled"
        const val STATUS_FAILED = "failed"

        const val REASON_CANCELLED = "cancelled"
        const val REASON_CRASH_LOOP = "crash_loop"

        /** Resumes without a single new checkpoint before the job is failed. */
        const val MAX_RESUMES_WITHOUT_PROGRESS = 3

        /** The store under an app-support root (`filesDir` on Android). */
        fun forRoot(root: File): JobStore = JobStore(File(root, DIR_NAME), File(root, STAGING_DIR_NAME))

        /**
         * Renames [dir] to a unique sibling tombstone so the path is free at
         * once; the gigabytes behind it are deleted later by [sweepTombstones].
         * Returns false when there was nothing to retire.
         */
        fun retire(dir: File): Boolean {
            if (!dir.exists()) return false
            val tombstone = File(dir.parentFile, "${dir.name}.${System.nanoTime()}$TOMBSTONE_SUFFIX")
            if (dir.renameTo(tombstone)) return true
            // Rename refused (cross-device, locked): fall back to deleting in place.
            dir.deleteRecursively()
            return true
        }

        /** Deletes every tombstone directly under [root]; best effort. */
        fun sweepTombstones(root: File) {
            root.listFiles()?.forEach { entry ->
                if (entry.name.endsWith(TOMBSTONE_SUFFIX)) {
                    try {
                        entry.deleteRecursively()
                    } catch (_: Exception) {
                        // Another sweeper may be deleting the same tree.
                    }
                }
            }
        }

        fun resultDone(kind: String, extra: Map<String, Any?> = emptyMap()): Map<String, Any?> =
            mapOf("status" to STATUS_DONE, "kind" to kind) + extra

        fun resultFailed(kind: String, code: String): Map<String, Any?> =
            mapOf("status" to STATUS_FAILED, "kind" to kind, "error" to code)

        fun resultCancelled(kind: String): Map<String, Any?> =
            mapOf("status" to STATUS_CANCELLED, "kind" to kind)

        /** Android's org.json has no toMap(); this covers what we store. */
        fun JSONObject.toPlainMap(): Map<String, Any?> {
            val map = LinkedHashMap<String, Any?>()
            for (key in keys()) map[key] = plain(get(key))
            return map
        }

        private fun plain(value: Any?): Any? = when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> value.toPlainMap()
            is JSONArray -> (0 until value.length()).map { plain(value.get(it)) }
            else -> value
        }
    }
}
