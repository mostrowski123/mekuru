package moe.matthew.mekuru.ocr

import android.app.ActivityManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Opt-in troubleshooting. No book text, paths, account data, or uploads. */
object OcrDiagnostics {
    fun read(): JSONObject {
        val context=OcrRuntime.context
        val manager=context.getSystemService(ActivityManager::class.java)
        val memory=ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
        val exits=JSONArray()
        if(Build.VERSION.SDK_INT>=30) {
            for(exit in manager.getHistoricalProcessExitReasons(context.packageName,0,5)) {
                exits.put(JSONObject().put("timestamp",exit.timestamp).put("reason",exit.reason)
                    .put("status",exit.status).put("pssKb",exit.pss).put("rssKb",exit.rss)
                    .put("description",exit.description))
            }
        }
        val latest=File(context.noBackupFilesDir,"local_manga_ocr/last-diagnostics.json")
        return JSONObject().put("device",Build.MANUFACTURER+" "+Build.MODEL)
            .put("sdk",Build.VERSION.SDK_INT).put("abis",JSONArray(Build.SUPPORTED_ABIS.toList()))
            .put("modelVersion",OcrRuntime.models.version).put("engineVersion","baberu-opencv-2")
            .put("availableMemoryBytes",memory.availMem).put("lowMemory",memory.lowMemory)
            .put("processExits",exits)
            .put("lastPage",if(latest.isFile) JSONObject(latest.readText()) else JSONObject.NULL)
    }
    fun record(stats: JSONObject) {
        if(!BuildConfig.DEBUG) return
        try { OcrWrites.atomic(File(OcrRuntime.context.noBackupFilesDir,
            "local_manga_ocr/last-diagnostics.json"),stats.toString()) }
        catch(_: Exception) { /* Diagnostic IO must never fail OCR. */ }
    }
}
