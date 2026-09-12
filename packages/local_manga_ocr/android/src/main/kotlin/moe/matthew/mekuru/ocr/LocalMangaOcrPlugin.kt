package moe.matthew.mekuru.ocr

import android.os.Handler
import android.os.Looper
import androidx.work.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.concurrent.withLock

/** Not ActivityAware on purpose: the notification permission is requested
 * through the app's own bridge, whose request code MainActivity answers before
 * Flutter fans the result out to every plugin's listener. */
class LocalMangaOcrPlugin : FlutterPlugin,MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val executor=Executors.newSingleThreadExecutor()
    private val main=Handler(Looper.getMainLooper())
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OcrRuntime.initialize(binding.applicationContext)
        channel=MethodChannel(binding.binaryMessenger,"mekuru/local_manga_ocr")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
    @Volatile private var benchmarkEngine: PageOcrEngine?=null
    @Volatile private var benchmarkCancelled=false
    override fun onMethodCall(call: MethodCall,result: MethodChannel.Result) {
        val task=Runnable {
            try {
                val args=JSONObject(call.arguments as? Map<*,*> ?: emptyMap<String,Any>())
                val value=handle(call.method,args)
                main.post { if(value===NotImplemented) result.notImplemented() else result.success(plain(value)) }
            } catch(error: Throwable) {
                main.post { result.error(error.message ?: "ocr_error",
                    error.message ?: error.javaClass.simpleName,null) }
            }
        }
        try {
            // A speed test runs for many seconds; the serial executor must stay
            // free for the 1 Hz jobs/modelState polls and for benchmarkCancel.
            if(call.method=="benchmark") Thread(task,"mekuru-ocr-benchmark").start()
            else executor.execute(task)
        } catch(_: java.util.concurrent.RejectedExecutionException) {
            result.error("detached","plugin detached",null)
        }
    }
    /** Times the real pipeline on the bundled synthetic sample page. Holds the
     * model lease so downloads, removal and jobs wait as for a running job. */
    private fun benchmark(args: JSONObject): JSONObject {
        val isTest=DebugOcrHooks.accept(args)
        check(isTest || OcrRuntime.models.installed()) { "model_missing" }
        synchronized(OcrRuntime) {
            check(!OcrRuntime.hasModelLease()) { "model_busy" }
            OcrRuntime.benchmarking=true
        }
        benchmarkCancelled=false
        try {
            val context=OcrRuntime.context
            val activity=context.getSystemService(android.app.ActivityManager::class.java)
            if(!isTest) {
                val memory=android.app.ActivityManager.MemoryInfo().also { activity.getMemoryInfo(it) }
                check(memory.availMem>=1024L*1024*1024) { "low_memory" }
            }
            val threads=if(activity.isLowRamDevice) 1 else 2
            val sample=java.io.File(context.cacheDir,"local_manga_ocr_sample.jpg")
            if(!sample.isFile) {
                val partial=java.io.File(sample.path+".partial")
                context.assets.open("local_manga_ocr/sample.jpg").use { input ->
                    partial.outputStream().use { input.copyTo(it) }
                }
                check(partial.renameTo(sample)) { "storage_error" }
            }
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            val started=System.nanoTime()
            val engine=DebugOcrHooks.benchmarkEngine(args)
                ?: MangaOcrEngine(OcrRuntime.models.installedDirectory,threads)
            val loadMs=(System.nanoTime()-started)/1_000_000
            benchmarkEngine=engine
            return engine.use {
                val book=JSONObject().put("imageDirPath",sample.parent)
                val page=JSONObject().put("imageFileName",sample.name)
                MangaImageSource(context,book,page).use { source ->
                    val at=System.nanoTime()
                    val blocks=engine.process(source,{},{}).length()
                    JSONObject().put("loadMs",loadMs).put("pageMs",(System.nanoTime()-at)/1_000_000)
                        .put("blocks",blocks).put("threads",threads)
                }
            }
        } catch(error: Throwable) {
            // A cancelled ORT run surfaces as ORT_FAIL "terminate flag"; report
            // it as the interruption the user asked for, like a cancelled job.
            if(benchmarkCancelled) error("stopped") else throw error
        } finally {
            benchmarkEngine=null
            OcrRuntime.benchmarking=false
        }
    }
    private fun handle(method: String,args: JSONObject): Any? {
        val store=OcrRuntime.store
        return when(method) {
            "diagnostics" -> OcrDiagnostics.read()
            "modelState" -> OcrRuntime.models.state()
            "isWifiConnected" -> ModelDownloadNetwork(OcrRuntime.context, false).isWifiConnected()
            "download" -> {
                check(OcrRuntime.models.supported) { "unsupported_device" }
                check(!OcrRuntime.hasModelLease()) { "model_busy" }
                val work=OneTimeWorkRequestBuilder<ModelDownloadWorker>()
                    .setInputData(workDataOf("allowMobileData" to args.optBoolean("allowMetered")))
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build()
                OcrRuntime.models.status("queued",downloadId=work.id.toString())
                WorkManager.getInstance(OcrRuntime.context).enqueueUniqueWork(DOWNLOAD,
                    ExistingWorkPolicy.REPLACE,work).result.get()
                null
            }
            "cancelDownload" -> {
                OcrRuntime.models.status("cancelled")
                WorkManager.getInstance(OcrRuntime.context).cancelUniqueWork(DOWNLOAD).result.get()
                null
            }
            "removeModels" -> { OcrRuntime.models.remove(); null }
            "benchmark" -> benchmark(args)
            "benchmarkCancel" -> { benchmarkCancelled=true; benchmarkEngine?.cancel(); null }
            "jobs" -> JSONArray(store.all().filter { it.optString("backend")=="onDevice" })
            "start" -> {
                OcrRuntime.checkedCache(args.getString("cachePath"))
                val isTest=DebugOcrHooks.accept(args)
                check(isTest || OcrRuntime.models.supported) { "unsupported_device" }
                check(isTest || OcrRuntime.models.installed()) { "model_missing" }
                // ponytail: a job queued before a speed test began can still race
                // the service for a second engine; accept that narrow window.
                check(!OcrRuntime.benchmarking) { "model_busy" }
                val job=store.create(args,OcrRuntime.models.version)
                OcrRuntime.startService(); job
            }
            "pause" -> { OcrRuntime.requestStop(args.getString("id"),false); null }
            "cancel" -> { OcrRuntime.requestStop(args.getString("id"),true); null }
            "resume" -> {
                val job=store.read(args.getString("id"))
                check(DebugOcrHooks.accept(job) || OcrRuntime.models.installed()) { "model_missing" }
                check(job.getString("modelVersion")==OcrRuntime.models.version) { "model_version_missing" }
                check(!OcrRuntime.benchmarking) { "model_busy" }
                store.resume(job.getString("id"),args.optBoolean("retryFailed"))
                OcrRuntime.startService(); null
            }
            "dismiss" -> { store.delete(args.getString("id")); null }
            "quiesce" -> { OcrRuntime.quiesce(); null }
            "cancelBook" -> {
                val bookId=args.getInt("bookId")
                val backend=args.stringOrNull("backend")
                store.all().filter { it.getInt("bookId")==bookId &&
                    (backend==null || it.optString("backend")==backend) }.forEach {
                    OcrRuntime.requestStop(it.getString("id"),true)
                }
                store.cancelBook(bookId,backend); null
            }
            "claimRemote" -> {
                OcrRuntime.checkedCache(args.getString("cachePath"))
                val job=store.create(args,"remote","remote")
                store.transition(job.getString("id"),"preparing")
                store.transition(job.getString("id"),"running")
            }
            "commitRemote" -> {
                store.commit(args.getString("id"),args.getInt("index"),args.getJSONArray("blocks"),
                    args.optString("inputHash"))
                null
            }
            "ensureRemoteLease" -> OcrWrites.lock.withLock {
                val job=store.read(args.getString("id"))
                check(job.optString("backend")=="remote") { "invalid_backend" }
                if(job.getString("status")=="paused" && job.optString("reason")=="interrupted") {
                    store.resume(job.getString("id"),false)
                    store.transition(job.getString("id"),"preparing")
                    store.transition(job.getString("id"),"running")
                } else {
                    check(job.getString("status")=="running") { "job_stopped" }
                    job
                }
            }
            "releaseRemote" -> {
                val job=store.read(args.getString("id"))
                if(job.getString("status") in OcrStore.active) store.transition(job.getString("id"),"completed")
                null
            }
            "mergeCache" -> OcrWrites.lock.withLock {
                val file=OcrRuntime.checkedCache(args.getString("path"))
                check(file.isFile) { "cache_missing" }
                val merged=MangaCacheMerge.merge(JSONObject(file.readText()),
                    JSONObject(args.getString("before")),JSONObject(args.getString("after")))
                OcrWrites.atomic(file,merged.toString()); merged.toString()
            }
            "resetCache" -> OcrWrites.lock.withLock {
                val file=OcrRuntime.checkedCache(args.getString("path"))
                check(file.isFile) { "cache_missing" }
                check(store.activeFor(args.getInt("bookId"))==null) { "book_busy" }
                val next=JSONObject(args.getString("after"))
                next.put("ocrGeneration",UUID.randomUUID().toString())
                OcrWrites.atomic(file,next.toString()); next.toString()
            }
            "test.recover" -> {
                if(!DebugOcrHooks.enabled) NotImplemented else {
                    check(!OcrRuntime.serviceRunning.get()) { "job_busy" }
                    store.recover(); null
                }
            }
            "test.detectorFixture" -> if(DebugOcrHooks.enabled) DebugOcrHooks.detectorFixture(OcrRuntime.context,args)
                else NotImplemented
            "test.evaluate" -> if(DebugOcrHooks.enabled) DebugOcrHooks.evaluate(OcrRuntime.context,args)
                else NotImplemented
            else -> NotImplemented
        }
    }
    private object NotImplemented
    private fun plain(value: Any?): Any? = when(value) {
        null,JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { plain(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { plain(value.get(it)) }
        else -> value
    }
    companion object {
        const val DOWNLOAD="mekuru_local_ocr_models"
    }
}
