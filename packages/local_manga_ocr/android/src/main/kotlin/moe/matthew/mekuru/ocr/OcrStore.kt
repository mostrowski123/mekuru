package moe.matthew.mekuru.ocr

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** One lock for every Flutter engine and service in this application process.
 * File locks alone are insufficient: POSIX locks are process-scoped. */
object OcrWrites {
    val lock = ReentrantLock()
    @android.annotation.SuppressLint("NewApi")
    fun atomic(file: File, text: String) {
        requireNotNull(file.parentFile).mkdirs()
        val tmp = File(file.parentFile, file.name + "." + UUID.randomUUID() + ".tmp")
        try {
            FileOutputStream(tmp).use {
                it.write(text.toByteArray(Charsets.UTF_8))
                it.fd.sync()
            }
            // Android/POSIX rename replaces atomically. Windows JVM test hosts
            // require NIO's explicit replacement option instead.
            if ((System.getProperty("os.name") ?: "").startsWith("Windows")) {
                java.nio.file.Files.move(tmp.toPath(), file.toPath(),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                    java.nio.file.StandardCopyOption.ATOMIC_MOVE)
            } else if (!tmp.renameTo(file)) throw java.io.IOException("atomic_rename_failed")
        } finally { tmp.delete() }
    }
}

fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }
fun JSONArray.ints(): List<Int> = (0 until length()).map { getInt(it) }
fun JSONObject.cloneJson() = JSONObject(toString())
fun JSONObject.stringOrNull(key: String): String? =
    if (has(key) && !isNull(key)) getString(key) else null

fun jsonEquivalent(a: Any?, b: Any?): Boolean {
    if(a==null || a===JSONObject.NULL) return b==null || b===JSONObject.NULL
    if(a is Number && b is Number) return a.toDouble()==b.toDouble()
    if(a is JSONObject && b is JSONObject) {
        val keys=a.keys().asSequence().toSet()
        return keys==b.keys().asSequence().toSet() && keys.all { jsonEquivalent(a.opt(it),b.opt(it)) }
    }
    if(a is JSONArray && b is JSONArray) return a.length()==b.length() &&
        (0 until a.length()).all { jsonEquivalent(a.opt(it),b.opt(it)) }
    return a==b
}
fun sameRecognition(a: JSONArray,b: JSONArray): Boolean {
    if(a.length()!=b.length()) return false
    return (0 until a.length()).all { i ->
        val left=a.getJSONObject(i).cloneJson().also { it.remove("words") }
        val right=b.getJSONObject(i).cloneJson().also { it.remove("words") }
        jsonEquivalent(left,right)
    }
}

class OcrStore(private val directory: File,
               private val writeJournal: (File,String)->Unit = OcrWrites::atomic) {
    // If storage fills up, keep the app operable and show a resumable failure.
    // The disk checkpoint remains authoritative after a process restart.
    private val unsavedPauses=mutableMapOf<String,JSONObject>()
    companion object {
        val active = setOf("queued", "preparing", "running", "pausing", "cancelling")
        val resumable = setOf("paused", "failed", "completedWithErrors")
        fun pageComplete(book: JSONObject, page: JSONObject): Boolean =
            page.optJSONObject("ocr")?.optBoolean("completed") == true ||
            page.optJSONArray("blocks")?.length()?.let { it > 0 } == true ||
            book.optBoolean("ocrCompleted",
                book.stringOrNull("ocrSource") != null)
    }
    init { directory.mkdirs() }
    private fun file(id: String): File {
        require(id.matches(Regex("[a-f0-9-]{36}"))) { "invalid_job_id" }
        return File(directory, id + ".json")
    }
    fun read(id: String): JSONObject = OcrWrites.lock.withLock {
        unsavedPauses[id]?.cloneJson() ?: JSONObject(file(id).readText())
    }
    fun all(): List<JSONObject> = OcrWrites.lock.withLock {
        directory.listFiles()?.filter { it.extension == "json" }?.mapNotNull {
            try { unsavedPauses[it.nameWithoutExtension]?.cloneJson() ?: JSONObject(it.readText()) }
            catch (_: Exception) { null }
        }?.sortedBy { it.optLong("createdAt") } ?: emptyList()
    }
    fun save(job: JSONObject) {
        job.put("revision", job.optLong("revision") + 1)
        writeJournal(file(job.getString("id")), job.toString())
        unsavedPauses.remove(job.getString("id"))
    }
    fun activeFor(bookId: Int) = all().firstOrNull {
        it.getInt("bookId") == bookId && it.getString("status") in active
    }
    fun create(spec: JSONObject, modelVersion: String, backend: String = "onDevice"): JSONObject =
        OcrWrites.lock.withLock {
            val bookId = spec.getInt("bookId")
            // One listing serves both the busy check and the history sweep below. The
            // journal lock is held across all of it, and the 1 Hz notification ticker
            // and jobs poll block on that same lock.
            val existing = all().filter { it.getInt("bookId") == bookId }
            require(existing.none { it.getString("status") in active }) { "book_busy" }
            val cache = File(spec.getString("cachePath"))
            require(cache.isFile) { "cache_missing" }
            val book = JSONObject(cache.readText())
            val pages = book.getJSONArray("pages")
            val targets = spec.getJSONArray("pages").ints().distinct()
            require(targets.isNotEmpty() && targets.all { it in 0 until pages.length() }) {
                "invalid_pages"
            }
            if (!book.has("ocrGeneration")) book.put("ocrGeneration", UUID.randomUUID().toString())
            // Freeze historical completion before book-wide metadata changes.
            for (page in pages.objects()) if (!page.has("ocr") && pageComplete(book, page)) {
                page.put("ocr", JSONObject().put("completed", true)
                    .put("source", book.optString("ocrSource", "legacy")).put("revision", 0))
            }
            OcrWrites.atomic(cache, book.toString())
            val job = spec.cloneJson()
                .put("id", UUID.randomUUID().toString())
                .put("generation", book.getString("ocrGeneration"))
                .put("backend", backend).put("modelVersion", modelVersion)
                .put("pages", JSONArray(targets)).put("status", "queued")
                .put("createdAt", System.currentTimeMillis())
                .put("outcomes", JSONObject()).put("errors", JSONObject())
                .put("pageNames", JSONArray(targets.map { pages.getJSONObject(it).getString("imageFileName") }))
            // Keep one entry per book so the sheet always shows the last run. Older
            // finished jobs would otherwise surface one by one as each is dismissed.
            // A resumable job on the other backend is left alone: claiming a remote
            // job must not discard a paused on-device one.
            for (old in existing) {
                if (old.optString("backend") == backend ||
                    old.getString("status") !in resumable) discard(old.getString("id"))
            }
            save(job); job
        }

    fun transition(id: String, status: String, reason: String? = null): JSONObject =
        OcrWrites.lock.withLock {
            val job = read(id)
            val before = job.getString("status")
            val allowed = when (status) {
                "preparing" -> before == "queued"
                "running" -> before == "preparing" || before == "running"
                "pausing", "cancelling" -> before in active
                "paused" -> before in active
                "cancelled" -> before in active || before in resumable
                "completed", "completedWithErrors", "failed" -> before in active
                else -> false
            }
            check(allowed) { "invalid_transition:" + before + ":" + status }
            job.put("status", status).put("phase", status)
            if (reason == null) job.remove("reason") else job.put("reason", reason)
            save(job); job
        }

    fun resume(id: String, retryFailed: Boolean): JSONObject = OcrWrites.lock.withLock {
        val job = read(id)
        require(job.getString("status") in resumable) { "not_resumable" }
        require(activeFor(job.getInt("bookId")) == null) { "book_busy" }
        val cache=File(job.getString("cachePath"))
        require(cache.isFile) { "cache_missing" }
        require(JSONObject(cache.readText()).optString("ocrGeneration")==job.getString("generation")) { "book_changed" }
        val outcomes = job.getJSONObject("outcomes")
        // Failed pages are retryable on Resume as well as Retry failed.
        for (key in outcomes.keys().asSequence().toList()) {
            if (outcomes.getString(key) == "failed") outcomes.remove(key)
        }
        job.put("errors", JSONObject()).put("status", "queued").put("phase", "queued")
        job.remove("reason")
        save(job); job
    }

    fun pauseQueued(backend: String, reason: String) = OcrWrites.lock.withLock {
        for (job in all()) {
            if (job.optString("backend") == backend && job.getString("status") == "queued") {
                transition(job.getString("id"), "paused", reason)
            }
        }
    }
    fun delete(id: String) = OcrWrites.lock.withLock {
        require(read(id).getString("status") !in active) { "job_busy" }
        discard(id)
    }

    /** Journal removal for callers that already hold the job and its status, so the
     * file is not parsed a second time only to re-derive what they already know. */
    private fun discard(id: String) {
        unsavedPauses.remove(id)
        file(id).delete()
    }

    /** Called once on native process initialization, never on each UI attach. */
    fun recover() = OcrWrites.lock.withLock {
        val stale = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        val jobs = all()
        // Installs predating the one-entry-per-book rule carry a stack of finished
        // runs, and the sheet reveals the next one down as each is dismissed. Keep
        // the newest per book plus anything still resumable, and drop the rest.
        val newest = jobs.groupBy { it.getInt("bookId") }
            .mapValues { (_, group) -> group.last().getString("id") }
        for (job in jobs) {
            if (job.getString("status") !in active) {
                val superseded = newest[job.getInt("bookId")] != job.getString("id") &&
                    job.getString("status") !in resumable
                if (superseded || job.optLong("createdAt", Long.MAX_VALUE) < stale) {
                    discard(job.getString("id"))
                }
                continue
            }
            try { reconcile(job) } catch (_: Exception) { job.put("reason","cache_invalid") }
            job.put("status", if (job.getString("status") == "cancelling") "cancelled" else "paused")
                .put("phase", "paused").put("reason", "interrupted")
            try { save(job) } catch (_: java.io.IOException) {
                unsavedPauses[job.getString("id")]=job.put("reason","storage_error")
            }
        }
    }
    fun pauseAfterFailure(id: String,reason: String) = OcrWrites.lock.withLock {
        val job=read(id)
        if(job.getString("status") !in active && job.getString("status")!="paused") return@withLock
        try { reconcile(job) } catch (_: Exception) {}
        job.put("status",if(job.getString("status")=="cancelling") "cancelled" else "paused")
            .put("phase","paused").put("reason",reason)
        try { save(job) } catch (_: java.io.IOException) {
            unsavedPauses[id]=job.put("reason","storage_error")
        }
    }
    private fun reconcile(job: JSONObject) {
        val cache = File(job.getString("cachePath"))
        if (!cache.isFile) return
        val book = JSONObject(cache.readText())
        if (book.optString("ocrGeneration") != job.getString("generation")) return
        val pages = book.getJSONArray("pages")
        for (index in job.getJSONArray("pages").ints()) {
            if (index >= pages.length()) continue
            if (pages.getJSONObject(index).optJSONObject("ocr")?.optString("jobId") == job.getString("id")) {
                job.getJSONObject("outcomes").put(index.toString(), "done")
            }
        }
    }
    fun snapshot(id: String): Pair<JSONObject, JSONObject> = OcrWrites.lock.withLock {
        val job = read(id)
        reconcile(job); save(job)
        job to JSONObject(File(job.getString("cachePath")).readText())
    }
    fun phase(id: String, phase: String, page: Int) = OcrWrites.lock.withLock {
        val job = read(id)
        if (job.getString("status") == "running") {
            job.put("phase", phase).put("currentPage", page)
            if(phase=="detecting") {
                job.remove("regionsDone"); job.remove("regionsTotal")
                job.remove("regionStartedAt"); job.remove("regionElapsedMs")
            }
            save(job)
        }
    }
    fun regions(id: String,done: Int,total: Int) = OcrWrites.lock.withLock {
        val job=read(id)
        if(job.getString("status")!="running") return@withLock
        require(done in 0..total)
        val now=System.currentTimeMillis()
        if(done==0) job.put("regionStartedAt",now)
        job.put("regionsDone",done).put("regionsTotal",total)
            .put("regionElapsedMs",(now-job.optLong("regionStartedAt",now)).coerceAtLeast(0))
        save(job)
    }
    fun outcome(id: String, index: Int, outcome: String, error: String? = null) =
        OcrWrites.lock.withLock {
            val job = read(id)
            check(job.getString("status") == "running") { "stopped" }
            job.getJSONObject("outcomes").put(index.toString(), outcome)
            if (error != null) job.getJSONObject("errors").put(index.toString(), error)
            save(job)
        }

    /** Page commit and cancellation share the same lock. A cancel acknowledged
     * before this method starts makes the result ineligible for publication. */
    fun commit(id: String, index: Int, blocks: JSONArray, inputHash: String,elapsedMs: Double? = null,
               afterPageCommit: (() -> Unit)? = null) = OcrWrites.lock.withLock {
        val job = read(id)
        check(job.getString("status") == "running") { "stopped" }
        val cache = File(job.getString("cachePath"))
        check(cache.isFile) { "cache_missing" }
        val book = JSONObject(cache.readText())
        check(book.optString("ocrGeneration") == job.getString("generation")) { "book_changed" }
        val targets = job.getJSONArray("pages").ints()
        val target = targets.indexOf(index)
        check(target >= 0) { "invalid_page" }
        val pages = book.getJSONArray("pages")
        val page = pages.getJSONObject(index)
        check(page.getString("imageFileName") == job.getJSONArray("pageNames").getString(target)) {
            "book_changed"
        }
        if (page.optJSONObject("ocr")?.optString("jobId") != id) {
            page.put("blocks", blocks).remove("segmentationDictionary")
            val revision = (page.optJSONObject("ocr")?.optLong("revision") ?: 0) + 1
            page.put("ocr", JSONObject().put("completed", true).put("source", job.getString("backend"))
                .put("modelVersion", job.getString("modelVersion")).put("inputHash", inputHash)
                .put("jobId", id).put("revision", revision).put("completedAt", System.currentTimeMillis()))
            if(job.getString("backend")=="onDevice") {
                page.getJSONObject("ocr").put("engineVersion","manga-ocr-1")
            }
            book.put("ocrCompleted", pages.objects().all {
                it.optJSONObject("ocr")?.optBoolean("completed") == true ||
                    (it.optJSONArray("blocks")?.length() ?: 0) > 0
            })
            book.put("ocrSource", "mixed")
            OcrWrites.atomic(cache, book.toString())
        }
        afterPageCommit?.invoke()
        job.getJSONObject("outcomes").put(index.toString(), "done")
        if(elapsedMs!=null && elapsedMs>=0) {
            val previous=job.optDouble("avgPageMs",elapsedMs)
            job.put("avgPageMs",previous*.75+elapsedMs*.25)
            job.put("timedPages",job.optInt("timedPages")+1)
        }
        save(job)
    }

    fun cancelBook(bookId: Int,backend: String? = null) = OcrWrites.lock.withLock {
        for (job in all().filter { it.getInt("bookId") == bookId &&
            (backend==null || it.optString("backend")==backend) }) {
            if (job.getString("status") in active ||
                job.getString("status") in resumable) {
                job.put("status", "cancelled").put("phase", "cancelled"); save(job)
            }
        }
    }
}

/** Field-level compare-and-merge for caches read before an async calculation.
 * A newer OCR revision rejects stale word segmentation, but independent crop
 * changes are retained. Never replaces a cache that has since been deleted. */
object MangaCacheMerge {
    fun merge(current: JSONObject, before: JSONObject, after: JSONObject): JSONObject {
        check(before.optString("ocrGeneration").isEmpty() ||
            current.optString("ocrGeneration") == before.optString("ocrGeneration")) { "book_changed" }
        val result = current.cloneJson()
        val oldPages = before.getJSONArray("pages")
        val newPages = after.getJSONArray("pages")
        val pages = result.getJSONArray("pages")
        check(pages.length() == oldPages.length() && pages.length() == newPages.length()) { "book_changed" }
        for (i in 0 until pages.length()) {
            val old = oldPages.getJSONObject(i); val next = newPages.getJSONObject(i)
            val page = pages.getJSONObject(i)
            check(page.getString("imageFileName") == old.getString("imageFileName")) { "book_changed" }
            val sameOcr = jsonEquivalent(page.optJSONObject("ocr"),old.optJSONObject("ocr"))
            val derivedOnly = sameRecognition(old.optJSONArray("blocks") ?: JSONArray(),
                next.optJSONArray("blocks") ?: JSONArray())
            for (key in (old.keys().asSequence() + next.keys().asSequence()).toSet()) {
                if (key in setOf("pageIndex", "imageFileName", "imgWidth", "imgHeight", "ocr")) continue
                if (jsonEquivalent(old.opt(key),next.opt(key))) continue
                if (key in setOf("blocks", "segmentationDictionary") && (!sameOcr || !derivedOnly)) continue
                if (!jsonEquivalent(page.opt(key),old.opt(key))) continue
                if (next.has(key)) page.put(key, next.get(key)) else page.remove(key)
            }
        }
        if (before.opt("autoCropVersion") != after.opt("autoCropVersion")) {
            result.put("autoCropVersion", after.optInt("autoCropVersion"))
        }
        return result
    }
}
