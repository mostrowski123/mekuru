package moe.matthew.mekuru.ocr

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.work.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.concurrent.withLock

class LocalMangaOcrPlugin : FlutterPlugin,MethodChannel.MethodCallHandler,ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private val executor=Executors.newSingleThreadExecutor()
    private val main=Handler(Looper.getMainLooper())
    private var activity: Activity?=null
    private var binding: ActivityPluginBinding?=null
    private var notificationResult: MethodChannel.Result?=null
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OcrRuntime.initialize(binding.applicationContext)
        channel=MethodChannel(binding.binaryMessenger,"mekuru/local_manga_ocr")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding=binding; activity=binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() {
        binding?.removeRequestPermissionsResultListener(this)
        binding=null; activity=null
        notificationResult?.success(false); notificationResult=null
    }
    override fun onRequestPermissionsResult(code: Int,permissions: Array<out String>,results: IntArray): Boolean {
        if(code!=REQUEST_NOTIFICATIONS) return false
        notificationResult?.success(results.isNotEmpty() && results[0]==PackageManager.PERMISSION_GRANTED)
        notificationResult=null; return true
    }
    override fun onMethodCall(call: MethodCall,result: MethodChannel.Result) {
        if(call.method=="requestNotifications") {
            val host=activity
            if(Build.VERSION.SDK_INT<33 || ContextCompat.checkSelfPermission(OcrRuntime.context,
                Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED) result.success(true)
            else if(host==null || notificationResult!=null) result.success(false)
            else {
                notificationResult=result
                ActivityCompat.requestPermissions(host,arrayOf(Manifest.permission.POST_NOTIFICATIONS),REQUEST_NOTIFICATIONS)
            }
            return
        }
        try {
            executor.execute {
                try {
                    val args=JSONObject(call.arguments as? Map<*,*> ?: emptyMap<String,Any>())
                    val value=handle(call.method,args)
                    main.post { if(value===NotImplemented) result.notImplemented() else result.success(plain(value)) }
                } catch(error: Throwable) {
                    main.post { result.error(error.message ?: "ocr_error",
                        error.message ?: error.javaClass.simpleName,null) }
                }
            }
        } catch(_: java.util.concurrent.RejectedExecutionException) {
            result.error("detached","plugin detached",null)
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
            "jobs" -> JSONArray(store.all().filter { it.optString("backend")=="onDevice" })
            "start" -> {
                OcrRuntime.checkedCache(args.getString("cachePath"))
                val isTest=DebugOcrHooks.accept(args)
                check(isTest || OcrRuntime.models.supported) { "unsupported_device" }
                check(isTest || OcrRuntime.models.installed()) { "model_missing" }
                val job=store.create(args,OcrRuntime.models.version)
                OcrRuntime.startService(); job
            }
            "pause" -> { OcrRuntime.requestStop(args.getString("id"),false); null }
            "cancel" -> { OcrRuntime.requestStop(args.getString("id"),true); null }
            "resume" -> {
                val job=store.read(args.getString("id"))
                check(DebugOcrHooks.accept(job) || OcrRuntime.models.installed()) { "model_missing" }
                check(job.getString("modelVersion")==OcrRuntime.models.version) { "model_version_missing" }
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
        const val REQUEST_NOTIFICATIONS=3918
    }
}
