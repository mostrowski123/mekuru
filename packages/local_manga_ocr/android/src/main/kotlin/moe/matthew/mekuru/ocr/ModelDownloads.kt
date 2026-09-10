package moe.matthew.mekuru.ocr

import android.content.Context
import android.os.Build
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import kotlin.concurrent.withLock

data class ModelFile(val name: String, val bytes: Long, val sha256: String, val url: String) {
    init {
        require(name.matches(Regex("[a-zA-Z0-9_.-]+")) && !name.startsWith(".")) { "invalid_model_name" }
        require(bytes > 0 && sha256.matches(Regex("[a-f0-9]{64}"))) { "invalid_manifest" }
        require(url.startsWith("https://")) { "model_requires_https" }
    }
}
fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered().use { stream ->
        val bytes = ByteArray(64*1024)
        while (true) {
            val count = stream.read(bytes)
            if (count < 0) break
            digest.update(bytes, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

/** Streaming, resumable transfer. Final hashes, rather than ETags, establish
 * model identity. ETags only prevent appending bytes from different responses. */
class ModelTransfer(
    private val open: (String) -> HttpURLConnection = { URL(it).openConnection() as HttpURLConnection }
) {
    @Volatile private var connection: HttpURLConnection? = null
    fun interrupt() { connection?.disconnect() }
    fun download(spec: ModelFile, file: File, stopped: () -> Boolean = { false },
                 progress: (Long) -> Unit = {}) {
        fun checkpoint() { if (stopped()) throw CancellationException("download_cancelled") }
        checkpoint()
        if (file.isFile && file.length() == spec.bytes && sha256(file) == spec.sha256) return
        requireNotNull(file.parentFile).mkdirs()
        if (file.length() >= spec.bytes) file.delete()
        val etagFile = File(file.path + ".etag")
        val offset = file.length()
        val request = open(spec.url)
        connection = request
        request.connectTimeout = 15000
        request.readTimeout = 15000
        request.setRequestProperty("Accept-Encoding", "identity")
        if (offset > 0) {
            request.setRequestProperty("Range", "bytes=" + offset + "-")
            if (etagFile.isFile) request.setRequestProperty("If-Range", etagFile.readText())
        }
        try {
            val code = request.responseCode
            val append = code == 206 && offset > 0
            if (code != 200 && code != 206) throw IOException("download_http_" + code)
            if (append) {
                val range = request.getHeaderField("Content-Range") ?: ""
                val match = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(range)
                if (match == null || match.groupValues[1].toLong() != offset ||
                    match.groupValues[2].toLong() != spec.bytes-1 ||
                    match.groupValues[3].toLong() != spec.bytes) {
                    throw IOException("invalid_content_range")
                }
                val previous = if (etagFile.isFile) etagFile.readText() else null
                val returned = request.getHeaderField("ETag")
                if (previous != null && returned != null && previous != returned) {
                    file.delete(); etagFile.delete()
                    throw IOException("download_changed")
                }
            }
            val length = request.contentLengthLong
            val expected = spec.bytes - if (append) offset else 0
            if (length >= 0 && length != expected) throw IOException("download_size_mismatch")
            val free = requireNotNull(file.parentFile).usableSpace
            if (free > 0 && free < expected + 8*1024*1024) throw IOException("insufficient_storage")
            request.getHeaderField("ETag")?.let { etagFile.writeText(it) }
            var received = if (append) offset else 0L
            request.inputStream.use { input ->
                FileOutputStream(file, append).use { output ->
                    val buffer = ByteArray(64*1024)
                    while (true) {
                        checkpoint()
                        val count = input.read(buffer)
                        if (count < 0) break
                        received += count
                        if (received > spec.bytes) throw IOException("download_size_mismatch")
                        output.write(buffer, 0, count)
                        progress(received)
                    }
                    output.fd.sync()
                }
            }
            checkpoint()
            if (file.length() != spec.bytes) throw IOException("download_incomplete")
            if (sha256(file) != spec.sha256) {
                file.delete(); etagFile.delete()
                throw IOException("download_hash_mismatch")
            }
            etagFile.delete()
        } finally {
            request.disconnect()
            connection = null
        }
    }
}

class ModelPack(private val context: Context) {
    val manifest: JSONObject = JSONObject(context.assets.open("local_manga_ocr/manifest.json")
        .bufferedReader().use { it.readText() })
    val version = manifest.getString("version")
    val files = manifest.getJSONArray("files").objects().map {
        ModelFile(it.getString("name"), it.getLong("bytes"), it.getString("sha256"), it.getString("url"))
    }
    private val root = File(context.noBackupFilesDir, "local_manga_ocr")
    val staging = File(root, version + ".partial")
    val installedDirectory = File(root, version)
    private val statusFile = File(root, "download.json")
    init {
        val previous=File(root,version+".previous")
        if(!installedDirectory.exists() && previous.exists()) previous.renameTo(installedDirectory)
    }
    // Any 64-bit ABI: phones are arm64; x86_64 covers the emulator used for verification.
    val supported get() = Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()
    fun installed(): Boolean = File(installedDirectory, "INSTALLED").isFile &&
        files.all { File(installedDirectory, it.name).length() == it.bytes }
    fun verify() {
        check(installed()) { "model_missing" }
        for (spec in files) check(sha256(File(installedDirectory, spec.name)) == spec.sha256) {
            "model_corrupt"
        }
    }
    fun state(): JSONObject = OcrWrites.lock.withLock {
        val state = if (statusFile.isFile) {
            try { JSONObject(statusFile.readText()) } catch (_: Exception) { JSONObject() }
        } else JSONObject()
        if (installed()) state.put("status", "installed")
        state.put("installed", installed()).put("supported", supported)
            .put("version", version).put("totalBytes", files.sumOf { it.bytes })
            .put("downloadedBytes", if (installed()) files.sumOf { it.bytes }
                else files.sumOf { File(staging, it.name).length().coerceAtMost(it.bytes) })
    }
    fun status(status: String, error: String? = null,downloadId: String? = null) = OcrWrites.lock.withLock {
        val value = JSONObject().put("status", status)
        val owner=downloadId ?: if(statusFile.isFile) {
            try { JSONObject(statusFile.readText()).stringOrNull("downloadId") } catch(_: Exception) { null }
        } else null
        if(owner!=null) value.put("downloadId",owner)
        if (error != null) value.put("error", error)
        OcrWrites.atomic(statusFile, value.toString())
    }
    fun install() = OcrWrites.lock.withLock {
        check(state().optString("status") != "cancelled") { "download_cancelled" }
        for (spec in files) {
            val file = File(staging, spec.name)
            check(file.length() == spec.bytes && sha256(file) == spec.sha256) { "model_corrupt" }
        }
        check(!OcrRuntime.hasModelLease()) { "model_busy" }
        OcrWrites.atomic(File(staging, "INSTALLED"), version)
        val previous=File(root,version+".previous")
        if (previous.exists()) previous.deleteRecursively()
        if (installedDirectory.exists()) check(installedDirectory.renameTo(previous)) { "model_install_failed" }
        if (!staging.renameTo(installedDirectory)) {
            previous.renameTo(installedDirectory)
            error("model_install_failed")
        }
        previous.deleteRecursively()
        status("installed")
    }
    fun remove() = OcrWrites.lock.withLock {
        check(!OcrRuntime.hasModelLease()) { "model_busy" }
        check(state().optString("status") !in setOf("queued","downloading","verifying")) { "download_busy" }
        installedDirectory.deleteRecursively()
        staging.deleteRecursively()
        status("missing")
    }
}

class ModelDownloadWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    private val network = ModelDownloadNetwork(context, inputData.getBoolean("allowMobileData", false))
    private val transfer = ModelTransfer(network::open)
    override fun onStopped() {
        transfer.interrupt()
        OcrRuntime.initialize(applicationContext)
        val state=OcrRuntime.models.state()
        if(state.optString("downloadId")==id.toString() && state.optString("status") in
            setOf("queued","downloading","verifying")) OcrRuntime.models.status("paused")
        super.onStopped()
    }
    override fun doWork(): Result = synchronized(transferLock) {
        if(isStopped) return@synchronized Result.success()
        perform()
    }
    private fun perform(): Result {
        OcrRuntime.initialize(applicationContext)
        val pack = OcrRuntime.models
        if (pack.installed()) return Result.success()
        val started = System.currentTimeMillis()
        fun cancelled() = isStopped || pack.state().optString("status") == "cancelled" ||
            pack.state().optString("downloadId")!=id.toString()
        return try {
            if (cancelled()) return Result.success()
            pack.status("downloading")
            for (spec in pack.files) {
                transfer.download(spec, File(pack.staging, spec.name),
                    { cancelled() || System.currentTimeMillis()-started > 8*60*1000 })
            }
            if (cancelled()) return Result.success()
            pack.status("verifying")
            pack.install()
            Result.success()
        } catch (_: CancellationException) {
            if (cancelled()) Result.success() else {
                pack.status("queued"); Result.retry()
            }
        } catch (error: Exception) {
            if (cancelled()) Result.success() else if (error.message == "wifi_required") {
                pack.status("queued", "wifi_required"); Result.retry()
            } else if (runAttemptCount < 3 &&
                error.message != "insufficient_storage") {
                pack.status("queued", error.message); Result.retry()
            } else {
                pack.status("failed", error.message); Result.failure()
            }
        }
    }
    companion object { private val transferLock=Any() }
}
