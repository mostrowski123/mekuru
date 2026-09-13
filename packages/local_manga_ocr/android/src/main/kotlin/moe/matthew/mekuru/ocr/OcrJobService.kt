package moe.matthew.mekuru.ocr

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.os.*
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.util.concurrent.CancellationException

class OcrJobService : Service() {
    private var wakeLock: PowerManager.WakeLock?=null
    private val handler=Handler(Looper.getMainLooper())
    // Journal reads take the process-wide cache lock, which the worker holds across
    // full pages_cache.json fsyncs. Never take it from the main looper.
    private val tickerThread=HandlerThread("mekuru-ocr-ticker").also { it.start() }
    private val ticker=Handler(tickerThread.looper)
    @Volatile private var tick: Runnable?=null
    // Serializes a tick's notify + re-post against removeNotification(), so a tick that
    // lost the race neither re-creates the notification nor re-arms itself.
    private val tickLock=Any()
    private var foregroundReady=false
    @Volatile private var starts=0
    @Volatile private var stoppedReason: String?=null
    override fun onBind(intent: Intent?) = null
    override fun onCreate() {
        super.onCreate()
        val manager=getSystemService(NotificationManager::class.java)
        if(Build.VERSION.SDK_INT>=26) manager.createNotificationChannel(NotificationChannel(
            CHANNEL,getString(R.string.ocr_notification_channel),NotificationManager.IMPORTANCE_LOW))
        // startForegroundService gives us five seconds; foreground first, journal work after.
        try {
            val type=if(Build.VERSION.SDK_INT>=35) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
                else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            if (Build.VERSION.SDK_INT>=29) startForeground(NOTIFICATION,notification(null),type)
            else startForeground(NOTIFICATION,notification(null))
            foregroundReady=true
        } catch(error: Exception) {
            android.util.Log.w("MekuruLocalOcr","Foreground service could not start",error)
        }
        try { OcrRuntime.initialize(this) } catch(error: Exception) {
            android.util.Log.w("MekuruLocalOcr","OCR runtime could not initialize",error)
            foregroundReady=false
        }
        if(!foregroundReady) {
            Thread({
                try { OcrRuntime.store.pauseQueued("onDevice","background_start_denied") }
                catch(error: Exception) { android.util.Log.w("MekuruLocalOcr","Could not pause queued jobs",error) }
            },"mekuru-ocr-denied").start()
            stopSelf()
        }
    }
    override fun onStartCommand(intent: Intent?,flags: Int,startId: Int): Int {
        starts++
        val id=intent?.getStringExtra("id")
        val cancel=when(intent?.action) { "pause" -> false; "cancel" -> true; else -> null }
        if(id!=null && cancel!=null) Thread({
            try { OcrRuntime.requestStop(id,cancel) }
            catch(error: Exception) { android.util.Log.w("MekuruLocalOcr","Notification action failed",error) }
        },"mekuru-ocr-action").start()
        if (!foregroundReady) return START_NOT_STICKY
        if(OcrRuntime.serviceRunning.compareAndSet(false,true)) {
            val power=getSystemService(PowerManager::class.java)
            wakeLock=power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"mekuru:local-ocr")
                .apply { acquire(6*60*60*1000L) }
            tick=object: Runnable {
                override fun run() {
                    // The journal read waits on OcrWrites.lock; it stays outside the guard so
                    // the main-thread teardown never waits on that lock transitively.
                    val job=runCatching { OcrRuntime.currentId?.let { OcrRuntime.store.read(it) } }
                    synchronized(tickLock) {
                        if(tick!==this) return
                        try {
                            getSystemService(NotificationManager::class.java).notify(NOTIFICATION,notification(job.getOrThrow()))
                        } catch(error: Exception) {
                            android.util.Log.w("MekuruLocalOcr","Notification update failed",error)
                        }
                        ticker.postDelayed(this,1000)
                    }
                }
            }.also { ticker.post(it) }
            Thread({ work() },"mekuru-local-ocr").start()
        }
        return START_NOT_STICKY
    }
    private fun resourceCheck(job: JSONObject) {
        val activity=getSystemService(ActivityManager::class.java)
        val memory=ActivityManager.MemoryInfo().also { activity.getMemoryInfo(it) }
        if(memory.lowMemory) throw OcrPause("low_memory")
        val power=getSystemService(PowerManager::class.java)
        if(Build.VERSION.SDK_INT>=29 && power.currentThermalStatus>=PowerManager.THERMAL_STATUS_SEVERE)
            throw OcrPause("too_hot")
        val battery=registerReceiver(null,IntentFilter(Intent.ACTION_BATTERY_CHANGED))
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
        try {
            while(true) {
                if(stoppedReason!=null) {
                    pauseRemaining(stoppedReason!!)
                    break
                }
                val job=OcrRuntime.store.all().firstOrNull {
                    it.optString("backend")=="onDevice" && it.getString("status")=="queued"
                } ?: break
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
                    val memory=ActivityManager.MemoryInfo().also {
                        getSystemService(ActivityManager::class.java).getMemoryInfo(it)
                    }
                    // Conservative headroom for session initialization. An OS
                    // low-memory kill cannot be caught as a Java exception.
                    if(memory.availMem<1024L*1024*1024) throw OcrPause("low_memory")
                    OcrRuntime.models.verify()
                    resourceCheck(job)
                    val lowRam=getSystemService(ActivityManager::class.java).isLowRamDevice
                    val engine=MangaOcrEngine(OcrRuntime.models.installedDirectory,if(lowRam) 1 else 2) {
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
                            MangaImageSource(this,book,page).use { source ->
                                val hash=source.signature()
                                OcrPageOutput(engine.process(source,checkpoint,phase),hash)
                            }
                        } catch(error: ai.onnxruntime.OrtException) {
                            throw OcrPause(if(OcrRuntime.store.read(id).getString("status")=="running")
                                "runtime_error" else "stopped")
                        }
                    }
                } catch(error: Throwable) {
                    OcrRuntime.store.pauseAfterFailure(id,
                        if(error is OutOfMemoryError) "low_memory" else error.message ?: "runtime_error")
                } finally {
                    val retiring=OcrRuntime.engine
                    OcrRuntime.engine=null
                    retiring?.close()
                    OcrRuntime.currentId=null
                }
            }
        } finally {
            // Journal scan stays on this thread. `starts` catches a Start that lands
            // between the scan and the main-thread teardown below.
            val seenStarts=starts
            val moreQueued=stoppedReason==null && try {
                OcrRuntime.store.all().any {
                    it.optString("backend")=="onDevice" && it.getString("status")=="queued"
                }
            } catch(_: Exception) { false }
            handler.post {
                if(moreQueued || starts!=seenStarts) {
                    Thread({ work() },"mekuru-local-ocr").start()
                    return@post
                }
                removeNotification()
                wakeLock?.let { if(it.isHeld) it.release() }; wakeLock=null
                OcrRuntime.serviceRunning.set(false)
                stopSelf()
            }
        }
    }
    // API 34 delivers the one-argument form; API 35+ the two-argument one.
    override fun onTimeout(startId: Int) = onTimeout(startId,0)
    override fun onTimeout(startId: Int,fgsType: Int) {
        stoppedReason="background_timeout"
        OcrRuntime.engine?.cancel()
        // Android only allows a few seconds here. Disk work belongs off main.
        removeNotification(); stopSelf()
        Thread({
            try { pauseRemaining("background_timeout") }
            catch(error: Exception) { android.util.Log.w("MekuruLocalOcr","Could not persist timeout",error) }
        },"mekuru-ocr-timeout").start()
    }
    // Main thread only. Under the guard an in-flight tick can neither notify nor re-post
    // once this ran; the explicit cancel is belt and braces.
    private fun removeNotification() = synchronized(tickLock) {
        tick?.let { ticker.removeCallbacks(it) }; tick=null
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION)
    }
    private fun pauseRemaining(reason: String) {
        for(job in OcrRuntime.store.all().filter { it.optString("backend")=="onDevice" &&
            it.getString("status") in OcrStore.active }) {
            OcrRuntime.requestStop(job.getString("id"),false)
            OcrRuntime.store.pauseAfterFailure(job.getString("id"),reason)
        }
    }
    override fun onDestroy() {
        if(stoppedReason==null) stoppedReason="interrupted"
        OcrRuntime.currentId?.let { id ->
            Thread({
                try { OcrRuntime.requestStop(id,false) }
                catch(error: Exception) { android.util.Log.w("MekuruLocalOcr","Could not pause on destroy",error) }
            },"mekuru-ocr-destroy").start()
        }
        removeNotification()
        tickerThread.quitSafely()
        wakeLock?.let { if(it.isHeld) it.release() }; wakeLock=null
        // The worker clears currentId itself; the lease must not outlive the service.
        OcrRuntime.serviceRunning.set(false)
        super.onDestroy()
    }
    override fun onTrimMemory(level: Int) {
        if(level==TRIM_MEMORY_RUNNING_CRITICAL || level==TRIM_MEMORY_COMPLETE)
            OcrRuntime.currentId?.let { OcrRuntime.requestStop(it,false) }
        super.onTrimMemory(level)
    }
    private fun notification(job: JSONObject?): Notification {
        val launch=packageManager.getLaunchIntentForPackage(packageName)
        val builder=NotificationCompat.Builder(this,CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .setContentTitle(job?.optString("title") ?: getString(R.string.ocr_notification_channel))
            .setOnlyAlertOnce(true).setOngoing(true)
        if(launch!=null) builder.setContentIntent(PendingIntent.getActivity(this,0,launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        if(job==null) builder.setContentText(getString(R.string.ocr_preparing)).setProgress(0,0,true)
        else {
            val count=job.getJSONObject("outcomes").length()
            val total=job.getJSONArray("pages").length()
            builder.setContentText(getString(R.string.ocr_notification_progress,count,total))
                .setProgress(total,count,job.getString("status")=="preparing")
            for((action,label) in listOf("pause" to R.string.ocr_pause,"cancel" to R.string.ocr_cancel)) {
                val intent=Intent(this,OcrJobService::class.java).setAction(action)
                    .putExtra("id",job.getString("id"))
                val pending=PendingIntent.getService(this,action.hashCode(),intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                builder.addAction(0,getString(label),pending)
            }
        }
        return builder.build()
    }
    companion object { const val CHANNEL="local_manga_ocr"; const val NOTIFICATION=3917 }
}
