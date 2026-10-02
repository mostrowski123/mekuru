package moe.matthew.mekuru.ocr

import android.app.*
import android.content.*
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject

/** Runs queued on-device jobs as plain WorkManager work. Not a foreground service:
 * Play rejected the mediaProcessing one (1.43.8) because a scan can wait. When
 * Android stops the work (execution window, quota) the current job goes back to
 * queued and WorkManager runs it again later; the journal carries the progress. */
class OcrJobWorker(context: Context,parameters: WorkerParameters) : Worker(context,parameters) {
    private val notifications get()=applicationContext.getSystemService(NotificationManager::class.java)
    override fun doWork(): Result {
        OcrRuntime.initialize(applicationContext)
        // A rescheduled run can start while the stopped one is still winding down.
        if(!OcrRuntime.workerRunning.compareAndSet(false,true)) return Result.retry()
        // Journal reads take the process-wide cache lock, which this thread holds across
        // full pages_cache.json fsyncs. The 1 Hz notification ticker gets its own thread.
        val tickerThread=HandlerThread("mekuru-ocr-ticker").also { it.start() }
        try {
            if(Build.VERSION.SDK_INT>=26) notifications.createNotificationChannel(NotificationChannel(CHANNEL,
                applicationContext.getString(R.string.ocr_notification_channel),NotificationManager.IMPORTANCE_LOW))
            val ticker=Handler(tickerThread.looper)
            ticker.post(object: Runnable {
                override fun run() {
                    try {
                        val job=OcrRuntime.currentId?.let { OcrRuntime.store.read(it) }
                        notifications.notify(NOTIFICATION,notification(job))
                    } catch(error: Exception) {
                        android.util.Log.w("MekuruLocalOcr","Notification update failed",error)
                    }
                    ticker.postDelayed(this,1000)
                }
            })
            work()
        } finally {
            // Drop pending ticks and wait out one in flight, so none re-posts the
            // notification after it is cancelled.
            tickerThread.quit(); tickerThread.join()
            notifications.cancel(NOTIFICATION)
            OcrRuntime.workerRunning.set(false)
        }
        return Result.success()
    }
    override fun onStopped() {
        OcrRuntime.engine?.cancel()
        super.onStopped()
    }
    private fun resourceCheck(job: JSONObject) {
        if(isStopped) throw OcrPause("deferred")
        val activity=applicationContext.getSystemService(ActivityManager::class.java)
        val memory=ActivityManager.MemoryInfo().also { activity.getMemoryInfo(it) }
        if(memory.lowMemory) throw OcrPause("low_memory")
        val power=applicationContext.getSystemService(PowerManager::class.java)
        if(Build.VERSION.SDK_INT>=29 && power.currentThermalStatus>=PowerManager.THERMAL_STATUS_SEVERE)
            throw OcrPause("too_hot")
        val battery=applicationContext.registerReceiver(null,IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if(battery!=null) {
            val charging=battery.getIntExtra(BatteryManager.EXTRA_PLUGGED,0)!=0
            val level=battery.getIntExtra(BatteryManager.EXTRA_LEVEL,100)
            val scale=battery.getIntExtra(BatteryManager.EXTRA_SCALE,100).coerceAtLeast(1)
            if(!charging && level*100/scale<15) throw OcrPause("low_battery")
            if(!charging && job.optBoolean("onlyWhileCharging")) throw OcrPause("charging_required")
        }
    }
    private fun work() {
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
        while(!isStopped) {
            val job=OcrRuntime.store.nextQueued() ?: break
            val id=job.getString("id")
            OcrRuntime.currentId=id
            try {
                OcrRuntime.store.transition(id,"preparing")
                resourceCheck(job)
                val debug=DebugOcrHooks.processor(job)
                if(debug!=null) {
                    OcrRunner(OcrRuntime.store,id).run({ resourceCheck(job) },debug)
                    continue
                }
                check(OcrRuntime.models.supported) { "unsupported_device" }
                check(job.getString("modelVersion")==OcrRuntime.models.version) { "model_version_missing" }
                val activity=applicationContext.getSystemService(ActivityManager::class.java)
                val memory=ActivityManager.MemoryInfo().also { activity.getMemoryInfo(it) }
                // Conservative headroom for session initialization. An OS
                // low-memory kill cannot be caught as a Java exception.
                if(memory.availMem<1024L*1024*1024) throw OcrPause("low_memory")
                OcrRuntime.models.verify()
                resourceCheck(job)
                val engine=MangaOcrEngine(OcrRuntime.models.installedDirectory,if(activity.isLowRamDevice) 1 else 2) {
                    resourceCheck(job)
                    if(OcrRuntime.store.read(id).getString("status")!="preparing") throw OcrPause("stopped")
                }
                var regionsAt=0L
                engine.regionProgress = { done,total ->
                    // The journal is polled at 1 Hz; one fsync per region is wasted work.
                    val now=System.currentTimeMillis()
                    if(done==0 || done==total || now-regionsAt>=1000) {
                        regionsAt=now; OcrRuntime.store.regions(id,done,total)
                    }
                }
                OcrRuntime.engine=engine
                OcrRunner(OcrRuntime.store,id).run({ resourceCheck(job) }) { book,page,checkpoint,phase ->
                    try {
                        MangaImageSource(applicationContext,book,page).use { source ->
                            val hash=source.signature()
                            OcrPageOutput(engine.process(source,checkpoint,phase),hash)
                        }
                    } catch(error: ai.onnxruntime.OrtException) {
                        throw OcrPause(when {
                            isStopped -> "deferred"
                            OcrRuntime.store.read(id).getString("status")=="running" -> "runtime_error"
                            else -> "stopped"
                        })
                    }
                }
            } catch(error: Throwable) {
                // Stopped before the runner took over (model load): deferred like the runner does.
                if(!(isStopped && OcrRuntime.store.requeue(id))) OcrRuntime.store.pauseAfterFailure(id,
                    if(error is OutOfMemoryError) "low_memory" else error.message ?: "runtime_error")
            } finally {
                val retiring=OcrRuntime.engine
                OcrRuntime.engine=null
                retiring?.close()
                OcrRuntime.currentId=null
            }
        }
    }
    private fun notification(job: JSONObject?): Notification {
        val context=applicationContext
        val launch=context.packageManager.getLaunchIntentForPackage(context.packageName)
        val builder=NotificationCompat.Builder(context,CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .setContentTitle(job?.optString("title") ?: context.getString(R.string.ocr_notification_channel))
            .setOnlyAlertOnce(true).setOngoing(true)
        if(launch!=null) builder.setContentIntent(PendingIntent.getActivity(context,0,launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        if(job==null) builder.setContentText(context.getString(R.string.ocr_preparing)).setProgress(0,0,true)
        else {
            val status=job.getString("status")
            // A requested stop can take seconds to land: the detector pass is a single
            // uninterruptible native call. Say so and drop the buttons as soon as the tap
            // is recorded, so the unchanged progress text does not read as "nothing happened".
            val stopping=when(status) {
                "pausing" -> R.string.ocr_pausing
                "cancelling" -> R.string.ocr_cancelling
                else -> null
            }
            if(stopping!=null) builder.setContentText(context.getString(stopping)).setProgress(0,0,true)
            else {
                val count=job.getJSONObject("outcomes").length()
                val total=job.getJSONArray("pages").length()
                builder.setContentText(context.getString(R.string.ocr_notification_progress,count,total))
                    .setProgress(total,count,status=="preparing")
                for((action,label) in listOf("pause" to R.string.ocr_pause,"cancel" to R.string.ocr_cancel)) {
                    val intent=Intent(context,OcrActionReceiver::class.java).setAction(action)
                        .putExtra("id",job.getString("id"))
                    val pending=PendingIntent.getBroadcast(context,action.hashCode(),intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    builder.addAction(0,context.getString(label),pending)
                }
            }
        }
        return builder.build()
    }
    companion object { const val CHANNEL="local_manga_ocr"; const val NOTIFICATION=3917 }
}

/** The notification's Pause and Cancel buttons. */
class OcrActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context,intent: Intent) {
        val id=intent.getStringExtra("id") ?: return
        val cancel=when(intent.action) { "pause" -> false; "cancel" -> true; else -> return }
        val pending=goAsync()
        // Journal writes take OcrWrites.lock; never on the main looper.
        Thread({
            try { OcrRuntime.initialize(context); OcrRuntime.requestStop(id,cancel) }
            catch(error: Exception) { android.util.Log.w("MekuruLocalOcr","Notification action failed",error) }
            finally { pending.finish() }
        },"mekuru-ocr-action").start()
    }
}
