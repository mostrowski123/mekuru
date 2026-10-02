package moe.matthew.mekuru.ocr

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.withLock

object OcrRuntime {
    lateinit var store: OcrStore
        private set
    lateinit var models: ModelPack
        private set
    lateinit var context: Context
        private set
    private var initialized=false
    val workerRunning=AtomicBoolean(false)
    @Volatile var currentId: String?=null
    @Volatile var engine: PageOcrEngine?=null
    @Synchronized fun initialize(ctx: Context) {
        if(initialized) return
        context=ctx.applicationContext
        store=OcrStore(File(context.filesDir,"local_manga_ocr/jobs"))
        models=ModelPack(context)
        val waiting=store.recover()
        initialized=true
        // KEEP: only when no run is pending, i.e. the work was cancelled or never enqueued.
        if(waiting) enqueue(ExistingWorkPolicy.KEEP)
    }
    /** Set while the device speed test holds an engine: downloads, removal and
     * jobs then wait for it exactly as they wait for a running job. */
    @Volatile var benchmarking=false
    fun hasModelLease()=workerRunning.get() || currentId!=null || benchmarking
    /** APPEND: a start that lands while a worker is finishing runs after it. No
     * expedited work: below API 31 that would bring back a foreground service. */
    fun startWorker() { enqueue(ExistingWorkPolicy.APPEND_OR_REPLACE).result.get() }
    private fun enqueue(policy: ExistingWorkPolicy) = WorkManager.getInstance(context)
        .enqueueUniqueWork(JOBS,policy,OneTimeWorkRequestBuilder<OcrJobWorker>().build())
    private const val JOBS="mekuru_local_ocr_jobs"
    fun requestStop(id: String,cancel: Boolean) = OcrWrites.lock.withLock {
        val job=store.read(id)
        val status=job.getString("status")
        if(status !in OcrStore.active) {
            if(cancel && status in setOf("paused","failed","completedWithErrors")) store.transition(id,"cancelled")
            return@withLock
        }
        if(id==currentId) {
            store.transition(id,if(cancel) "cancelling" else "pausing")
            engine?.cancel()
        } else store.transition(id,if(cancel) "cancelled" else "paused")
    }
    fun quiesce() {
        for(job in store.all().filter { it.optString("backend")=="remote" && it.getString("status") in OcrStore.active }) {
            store.transition(job.getString("id"),"paused","interrupted")
        }
        for(job in store.all().filter { it.optString("backend")=="onDevice" && it.getString("status") in OcrStore.active }) {
            requestStop(job.getString("id"),false)
        }
        // Never hold the cache lock while awaiting resource release.
        val deadline=System.nanoTime()+30_000_000_000L
        while(workerRunning.get() && System.nanoTime()<deadline) Thread.sleep(25)
        check(!workerRunning.get()) { "ocr_still_stopping" }
    }
    fun checkedCache(path: String): File {
        val file=File(path).canonicalFile
        val root=File(context.applicationInfo.dataDir).canonicalPath+File.separator
        require(file.path.startsWith(root)) { "invalid_cache_path" }
        require(file.name=="pages_cache.json") { "invalid_cache_path" }
        return file
    }
}
