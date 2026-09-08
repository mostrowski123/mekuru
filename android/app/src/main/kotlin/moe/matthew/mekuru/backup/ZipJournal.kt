package moe.matthew.mekuru.backup

import java.io.File
import java.io.FileOutputStream
import org.json.JSONException
import org.json.JSONObject

/**
 * Append-only, fsynced log of what a job has durably produced, one JSON
 * object per line. Lines are only appended right after the output they
 * describe was synced, and each batch ends with a `ckpt` line; on parse,
 * anything after the last complete `ckpt` line (a torn batch) is discarded,
 * so the journal can only ever under-report progress, never invent it.
 *
 * Export lines: `{"e":i,"n":name,"mt":ms,"crc":..,"cs":..,"s":..,"off":..}`
 * for a written entry, `{"e":i,"skip":1}` for a source file that vanished,
 * `{"ckpt":endOffset,"next":i,"done":bytes}`, `{"resume":1}` at every
 * resume, `{"finished":1,"bytes":n}` once the central directory is on disk.
 * Restore lines: `{"n":relPath}` per extracted file, `{"ckpt":1,"done":bytes}`,
 * `{"resume":1}`.
 */
class ZipJournal(val file: File) {
    data class ExportState(
        val records: List<ResumableZipWriter.EntryRecord>,
        val skipped: Int,
        val ckptOffset: Long,
        val next: Int,
        val done: Long,
        val finished: Boolean,
        val finishedBytes: Long,
    ) {
        companion object {
            val EMPTY = ExportState(emptyList(), 0, 0L, 0, 0L, false, 0L)
        }
    }

    data class RestoreState(val names: Set<String>, val done: Long)

    fun append(lines: List<String>) {
        if (lines.isEmpty()) return
        file.parentFile?.mkdirs()
        FileOutputStream(file, true).use { fos ->
            val text = StringBuilder()
            for (line in lines) text.append(line).append('\n')
            fos.write(text.toString().toByteArray(Charsets.UTF_8))
            fos.flush()
            fos.fd.sync()
        }
    }

    fun reset() {
        file.delete()
    }

    /**
     * Resumes recorded since the last checkpoint, for the crash-loop guard.
     * A plain text scan: this runs at every launch, before any JSON is needed.
     */
    fun resumesSinceCheckpoint(): Int {
        if (!file.exists()) return 0
        var resumes = 0
        file.forEachLine(Charsets.UTF_8) { line ->
            if (line.contains(CKPT_TOKEN)) resumes = 0 else if (line.contains(RESUME_TOKEN)) resumes++
        }
        return resumes
    }

    fun parseExport(): ExportState {
        val records = ArrayList<ResumableZipWriter.EntryRecord>()
        val pendingRecords = ArrayList<ResumableZipWriter.EntryRecord>()
        var skipped = 0
        var pendingSkips = 0
        var ckptOffset = 0L
        var next = 0
        var done = 0L
        var finished = false
        var finishedBytes = 0L
        for (line in lines()) {
            when {
                line.has(KEY_CKPT) -> {
                    records.addAll(pendingRecords)
                    pendingRecords.clear()
                    skipped += pendingSkips
                    pendingSkips = 0
                    ckptOffset = line.getLong(KEY_CKPT)
                    next = line.getInt("next")
                    done = line.getLong("done")
                }
                line.has(KEY_FINISHED) -> {
                    finished = true
                    finishedBytes = line.optLong("bytes", 0L)
                }
                line.has("skip") -> pendingSkips++
                line.has("e") -> pendingRecords.add(
                    ResumableZipWriter.EntryRecord(
                        name = line.getString("n"),
                        mtimeMs = line.getLong("mt"),
                        crc = line.getLong("crc"),
                        csize = line.getLong("cs"),
                        size = line.getLong("s"),
                        offset = line.getLong("off"),
                    ),
                )
            }
        }
        return ExportState(records, skipped, ckptOffset, next, done, finished, finishedBytes)
    }

    fun parseRestore(): RestoreState {
        val names = LinkedHashSet<String>()
        val pending = ArrayList<String>()
        var done = 0L
        for (line in lines()) {
            when {
                line.has(KEY_CKPT) -> {
                    names.addAll(pending)
                    pending.clear()
                    done = line.getLong("done")
                }
                line.has("n") -> pending.add(line.getString("n"))
            }
        }
        return RestoreState(names, done)
    }

    /** Complete, parseable lines in order; stops at the first torn or bad line. */
    private fun lines(): List<JSONObject> {
        if (!file.exists()) return emptyList()
        val text = file.readText(Charsets.UTF_8)
        val result = ArrayList<JSONObject>()
        var start = 0
        while (true) {
            val end = text.indexOf('\n', start)
            if (end < 0) break // no trailing newline: a torn write, dropped
            val raw = text.substring(start, end)
            start = end + 1
            if (raw.isBlank()) continue
            try {
                result.add(JSONObject(raw))
            } catch (_: JSONException) {
                break
            }
        }
        return result
    }

    companion object {
        private const val KEY_CKPT = "ckpt"
        private const val KEY_RESUME = "resume"
        private const val KEY_FINISHED = "finished"
        private const val CKPT_TOKEN = "\"$KEY_CKPT\":"
        private const val RESUME_TOKEN = "\"$KEY_RESUME\":"

        fun entryLine(index: Int, r: ResumableZipWriter.EntryRecord): String = JSONObject()
            .put("e", index)
            .put("n", r.name)
            .put("mt", r.mtimeMs)
            .put("crc", r.crc)
            .put("cs", r.csize)
            .put("s", r.size)
            .put("off", r.offset)
            .toString()

        fun skipLine(index: Int): String = JSONObject().put("e", index).put("skip", 1).toString()

        fun ckptLine(endOffset: Long, next: Int, done: Long): String =
            JSONObject().put(KEY_CKPT, endOffset).put("next", next).put("done", done).toString()

        fun finishedLine(bytes: Long): String =
            JSONObject().put(KEY_FINISHED, 1).put("bytes", bytes).toString()

        fun resumeLine(): String = JSONObject().put(KEY_RESUME, 1).toString()

        fun nameLine(relPath: String): String = JSONObject().put("n", relPath).toString()

        fun restoreCkptLine(done: Long): String =
            JSONObject().put(KEY_CKPT, 1).put("done", done).toString()
    }
}
