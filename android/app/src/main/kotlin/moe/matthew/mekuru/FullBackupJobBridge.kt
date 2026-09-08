package moe.matthew.mekuru

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors
import moe.matthew.mekuru.backup.FullBackupJobRunner
import moe.matthew.mekuru.backup.JobSpec
import moe.matthew.mekuru.backup.JobStore
import moe.matthew.mekuru.backup.ZipPeek
import org.json.JSONObject

/**
 * Method channel `mekuru/full_backup_job`: the Dart side commits a job,
 * polls its status, cancels it and consumes its result here. The service
 * itself never touches the channel, so it outlives the engine.
 */
class FullBackupJobBridge(private val activity: Activity) {
    private var pendingPermissionResult: MethodChannel.Result? = null

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("full_backup_error", e.message, null)
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_NOTIFICATIONS) return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val store = FullBackupJobService.storeFor(activity)
        when (call.method) {
            "commitJob" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("bad_args", "job spec is required", null)
                    return
                }
                runIo(result) { commit(store, JobSpec.fromJson(JSONObject(args))) }
            }
            "status" -> runIo(result) {
                val live = FullBackupJobService.live
                store.status(
                    live?.let {
                        JobStore.Live(it.kind ?: JobSpec.KIND_EXPORT, it.control.phase, it.control.done, it.control.total)
                    },
                )
            }
            "cancel" -> runIo(result) { cancel(store) }
            "consumeResult" -> runIo(result) { store.consumeResult() }
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "inspectZip" -> {
                val uri = call.argument<String>("uri")
                val name = call.argument<String>("name")
                if (name.isNullOrBlank() || uri.isNullOrBlank()) {
                    result.error("bad_args", "uri and name are required", null)
                    return
                }
                runIo(result) { inspectZip(Uri.parse(uri), name) }
            }
            "isServiceRunning" -> result.success(FullBackupJobService.isRunning)
            "notificationsEnabled" -> result.success(
                (activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled(),
            )
            "activeNotificationIds" -> runIo(result) {
                val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.activeNotifications.map { it.id }
            }
            "abortForTest" -> debugOnly(result) {
                val after = (call.argument<Number>("afterBytes") ?: 0).toLong()
                val live = FullBackupJobService.live
                if (live != null) live.control.abortAfterBytes = after else FullBackupJobService.pendingAbortAfterBytes = after
                result.success(live != null)
            }
            "recoverForTest" -> debugOnly(result) {
                FullBackupRecovery.run(activity)
                result.success(null)
            }
            "setForceNonResumableForTest" -> debugOnly(result) {
                SafJobIo.forceNonResumable = call.argument<Boolean>("value") == true
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun commit(store: JobStore, requested: JobSpec): Any? {
        if (FullBackupJobService.isRunning || store.specFile.exists()) {
            throw IllegalStateException("busy")
        }
        val io = SafJobIo(activity.contentResolver)
        var spec = requested
        store.dir.mkdirs()
        store.journalFile.delete()
        store.cancelledFile.delete()
        store.lastErrorFile.delete()
        if (spec.isExport) {
            spec = io.createPartial(spec)
        } else {
            val staging = File(requireNotNull(spec.stagingPath) { "stagingPath" })
            JobStore.retire(staging)
            JobStore.retire(store.rollbackDir)
            staging.mkdirs()
        }
        store.writeSpec(spec)
        val seen = FullBackupJobService.jobStarts
        FullBackupJobService.start(activity)
        // Return only once the service owns the job, so no status poll can
        // read the freshly committed files as a paused job.
        FullBackupJobService.awaitJobStart(seen, START_TIMEOUT_MS)
        return null
    }

    private fun cancel(store: JobStore): Boolean {
        FullBackupJobService.live?.let { return it.requestCancel() }
        val spec = store.readSpec() ?: return false
        if (store.extractedMarker.exists()) return false
        // Paused: no worker to stop, so finish the cancel right here.
        store.markCancelled()
        val runner = FullBackupJobRunner(store, SafJobIo(activity.contentResolver))
        runner.cleanup(spec)
        store.writeResult(JobStore.resultCancelled(spec.kind))
        return true
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, arrayOf(permission), REQUEST_NOTIFICATIONS)
    }

    /**
     * Peeks the manifest and, when the source can be seeked, checks for an
     * end-of-central-directory record so a truncated copy is refused before
     * a multi-gigabyte extraction, not after. `content://` and `file://`
     * sources both go through the resolver.
     */
    private fun inspectZip(uri: Uri, name: String): Map<String, Any?> {
        val resolver = activity.contentResolver
        val stream = resolver.openInputStream(uri) ?: throw IllegalStateException("open_failed")
        val peek = ZipPeek.peek(stream, name)
        val complete: Boolean? = try {
            resolver.openFileDescriptor(uri, "r")?.use { pfd ->
                if (pfd.statSize < 0) null else FileInputStream(pfd.fileDescriptor).use { readTail(it, pfd.statSize) }
            }
        } catch (_: Exception) {
            null
        }
        return mapOf("isZip" to peek.isZip, "text" to peek.text, "complete" to complete)
    }

    private fun readTail(input: FileInputStream, size: Long): Boolean {
        val tailSize = minOf(size, ZipPeek.END_RECORD_TAIL.toLong()).toInt()
        input.channel.position(size - tailSize)
        val tail = ByteArray(tailSize)
        var read = 0
        while (read < tailSize) {
            val n = input.read(tail, read, tailSize - read)
            if (n < 0) break
            read += n
        }
        return ZipPeek.hasEndRecord(tail.copyOf(read))
    }

    private inline fun debugOnly(result: MethodChannel.Result, block: () -> Unit) {
        val debuggable = activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (!debuggable) {
            result.error("not_available", "test seams are disabled in release builds", null)
            return
        }
        block()
    }

    /** One worker thread: the status poll calls in twice a second for hours. */
    private fun runIo(result: MethodChannel.Result, task: () -> Any?) {
        io.execute {
            try {
                val value = task()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                val code = if (e is IllegalStateException && e.message == "busy") "busy" else "full_backup_io_error"
                activity.runOnUiThread { result.error(code, e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "mekuru/full_backup_job"
        const val REQUEST_NOTIFICATIONS = 7314
        private const val START_TIMEOUT_MS = 5_000L
        private val io = Executors.newSingleThreadExecutor { Thread(it, "mekuru-full-backup-bridge") }
    }
}
