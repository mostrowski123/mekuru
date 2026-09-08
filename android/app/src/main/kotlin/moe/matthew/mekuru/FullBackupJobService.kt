package moe.matthew.mekuru

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean
import moe.matthew.mekuru.backup.FullBackupJobRunner
import moe.matthew.mekuru.backup.JobControl
import moe.matthew.mekuru.backup.JobSpec
import moe.matthew.mekuru.backup.JobStore

/**
 * Foreground service (type dataSync) that runs the committed full-backup
 * job to completion, independent of the Flutter engine: the activity can be
 * destroyed, the app swiped away, and the archive keeps streaming. The
 * notification is the only UI while the app is not in front.
 *
 * Not sticky: a background restart could not call startForeground on
 * Android 12+ anyway, and [FullBackupRecovery] resumes the job on the next
 * launch from what [JobStore] finds on disk.
 */
class FullBackupJobService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var notificationTicker: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(getString(R.string.full_backup_notification_preparing), null, indeterminate = true),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } catch (_: Exception) {
            // Not allowed to run in the foreground right now (background start
            // restriction, exhausted dataSync budget): the job stays paused on
            // disk and resumes on the next launch.
            stopSelf()
            return
        }
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mekuru:full_backup")
            .apply { acquire(WAKE_LOCK_TIMEOUT_MS) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (running.compareAndSet(false, true)) {
            Thread({ work() }, "mekuru-full-backup").start()
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15 dataSync budget exhausted: stop now, resume next launch.
        live?.control?.paused = true
        stopForeground(STOP_FOREGROUND_REMOVE)
        notify(plainNotification(getString(R.string.full_backup_notification_paused)))
        stopSelf()
    }

    override fun onDestroy() {
        live?.control?.paused = true
        releaseWakeLock()
        super.onDestroy()
    }

    private fun work() {
        val store = storeFor(this)
        val runner = FullBackupJobRunner(store, SafJobIo(contentResolver))
        val spec = store.readSpec()
        var outcome: FullBackupJobRunner.Outcome = FullBackupJobRunner.Outcome.Paused
        try {
            if (spec == null) return
            pendingAbortAfterBytes.also { pendingAbortAfterBytes = -1L }.let { if (it >= 0) runner.control.abortAfterBytes = it }
            live = runner
            synchronized(startLock) {
                jobStarts++
                startLock.notifyAll()
            }
            handler.post { startNotificationTicker(runner.control, spec) }
            outcome = runner.run(spec)
        } finally {
            live = null
            running.set(false)
            val kind = spec?.kind ?: JobSpec.KIND_EXPORT
            handler.post { finish(outcome, kind) }
        }
    }

    private fun finish(outcome: FullBackupJobRunner.Outcome, kind: String) {
        notificationTicker?.let { handler.removeCallbacks(it) }
        notificationTicker = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        releaseWakeLock()
        val text = when (outcome) {
            FullBackupJobRunner.Outcome.Done -> if (kind == JobSpec.KIND_EXPORT) {
                getString(R.string.full_backup_notification_export_done)
            } else {
                getString(R.string.full_backup_notification_restore_ready)
            }
            FullBackupJobRunner.Outcome.Paused -> getString(R.string.full_backup_notification_paused)
            FullBackupJobRunner.Outcome.Cancelled -> null
            is FullBackupJobRunner.Outcome.Failed -> getString(R.string.full_backup_notification_failed)
        }
        if (text != null && !MainActivity.visible) notify(plainNotification(text))
        stopSelf()
    }

    private fun startNotificationTicker(control: JobControl, spec: JobSpec) {
        val title = if (spec.isExport) {
            getString(R.string.full_backup_notification_export_title)
        } else {
            getString(R.string.full_backup_notification_restore_title)
        }
        val ticker = object : Runnable {
            private var lastPercent: Int? = -1

            override fun run() {
                if (!running.get()) return
                val total = control.total
                val done = control.done
                val percent = if (total > 0) ((done * 100) / total).toInt().coerceIn(0, 100) else null
                // One binder call per visible change, not one per second.
                if (percent != lastPercent) {
                    lastPercent = percent
                    notify(buildNotification(title, percent, indeterminate = total <= 0))
                }
                handler.postDelayed(this, NOTIFICATION_PERIOD_MS)
            }
        }
        notificationTicker = ticker
        handler.post(ticker)
    }

    private fun buildNotification(title: String, percent: Int?, indeterminate: Boolean): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(title)
            .setContentText(percent?.let { "$it%" })
            .setProgress(100, percent ?: 0, indeterminate)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openAppIntent())
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

    private fun plainNotification(text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle(getString(R.string.full_backup_channel_name))
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun notify(notification: Notification) {
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Notifications denied: the job still runs.
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.full_backup_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    companion object {
        const val CHANNEL_ID = "full_backup"
        const val NOTIFICATION_ID = 7401
        private const val NOTIFICATION_PERIOD_MS = 1000L
        private const val WAKE_LOCK_TIMEOUT_MS = 6L * 60 * 60 * 1000

        private val running = AtomicBoolean(false)

        /** The runner of the job in flight, for status and cancel. */
        @Volatile var live: FullBackupJobRunner? = null
            private set

        val isRunning: Boolean get() = running.get()

        /** Test seam: applied to the next job to start (see the bridge). */
        @Volatile var pendingAbortAfterBytes = -1L

        private val startLock = Object()

        /** Jobs that have gone live in this process; see [awaitJobStart]. */
        @Volatile var jobStarts = 0L
            private set

        /**
         * Blocks until a job newer than [seen] is live or [timeoutMs] passes.
         * Until the service thread claims a committed job, status has only
         * the job files to go on and would report it as paused.
         */
        fun awaitJobStart(seen: Long, timeoutMs: Long) {
            val deadline = System.currentTimeMillis() + timeoutMs
            synchronized(startLock) {
                while (jobStarts == seen) {
                    val remaining = deadline - System.currentTimeMillis()
                    if (remaining <= 0) return
                    startLock.wait(remaining)
                }
            }
        }

        /** `getApplicationSupportDirectory()` on Android is `filesDir`. */
        fun storeFor(context: Context): JobStore = JobStore.forRoot(context.filesDir)

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, FullBackupJobService::class.java))
        }
    }
}
