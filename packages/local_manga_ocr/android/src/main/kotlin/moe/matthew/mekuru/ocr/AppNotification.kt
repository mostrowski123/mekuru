package moe.matthew.mekuru.ocr

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/** A one-off notification the app's Dart side posts from background work (a
 * download that gave up while Mekuru was closed). The plugin is the native code
 * WorkManager's background engine has; the app's own channels live in
 * MainActivity. Skipped while Mekuru is on screen, which shows the outcome
 * itself. Tapping it opens Mekuru. */
object AppNotification {
    fun post(context: Context, args: JSONObject): Boolean {
        val process = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(process)
        if (process.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = args.getString("channel")
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(channel, args.getString("channelName"), NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val id = args.getInt("id")
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(args.getString("title"))
            .setContentText(args.getString("text"))
            .setAutoCancel(true)
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            builder.setContentIntent(
                PendingIntent.getActivity(context, id, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
        }
        manager.notify(id, builder.build())
        return true
    }
}
