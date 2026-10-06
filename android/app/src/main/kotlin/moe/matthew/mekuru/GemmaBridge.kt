package moe.matthew.mekuru

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.ThinkingConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Method channel `mekuru/gemma`: Gemma 4 E2B in Google's LiteRT-LM for the
 * Sentence tab's high-quality mode. Every LiteRT-LM call runs on one
 * background thread (loading takes seconds and the calls block), and every
 * reply goes back to the main thread, which is where Flutter wants it.
 *
 * [engine], [loadedPath] and [backendName] belong to the worker thread.
 */
class GemmaBridge {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var engine: Engine? = null
    private var loadedPath: String? = null
    private var backendName: String? = null

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "mekuru/gemma").setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    val reply: Any? = when (call.method) {
                        "load" -> load(call.argument<String>("path")!!, call.argument<String>("cacheDir")!!)
                        "translate" -> translate(
                            call.argument<String>("text") ?: "",
                            call.argument<String>("language") ?: "English",
                        )
                        "close" -> { close(); null }
                        else -> { main.post { result.notImplemented() }; return@execute }
                    }
                    main.post { result.success(reply) }
                } catch (e: Throwable) {
                    // Throwable: a JNI link failure is an Error, and an
                    // unanswered call would hang the Dart side for good.
                    main.post { result.error("gemma_error", e.message, null) }
                }
            }
        }
    }

    /**
     * GPU first, then CPU. Some phones can't create a GPU engine; on others
     * (no OpenCL, so LiteRT-LM picks WebGPU) it loads but fails on every
     * message, so a GPU engine must answer a warm-up message to be kept.
     * Once CPU has stood in for a failed GPU, this process skips GPU. Loading
     * the model that is already live is a no-op: two sentences tapped at once
     * both ask for a load.
     */
    private fun load(path: String, cacheDir: String): String {
        val live = backendName
        if (engine != null && loadedPath == path && live != null) return live
        close()
        if (gpuUnusable) return start(path, cacheDir, "cpu", Backend.CPU())
        return try {
            start(path, cacheDir, "gpu", Backend.GPU(), warmUp = true)
        } catch (e: Throwable) {
            Log.w("GemmaBridge", "GPU engine unusable, using CPU", e)
            // Only once CPU works: a missing model fails both, and isn't the GPU's fault.
            start(path, cacheDir, "cpu", Backend.CPU()).also { gpuUnusable = true }
        }
    }

    private fun start(
        path: String,
        cacheDir: String,
        name: String,
        backend: Backend,
        warmUp: Boolean = false,
    ): String {
        val candidate = Engine(EngineConfig(modelPath = path, backend = backend, cacheDir = cacheDir))
        try {
            candidate.initialize()
            if (warmUp) {
                candidate.createConversation(conversationConfig(maxOutputToken = 1)).use {
                    it.sendMessage("Hi")
                }
            }
        } catch (e: Throwable) {
            try {
                candidate.close()
            } catch (_: Throwable) {
                // The initialize failure is the one worth reporting.
            }
            throw e
        }
        engine = candidate
        loadedPath = path
        backendName = name
        return name
    }

    private fun translate(text: String, language: String): String {
        val loaded = engine ?: error("Gemma is not loaded")
        // A fresh conversation per sentence: no context leaks between taps.
        loaded.createConversation(conversationConfig(maxOutputToken = 160)).use { conversation ->
            val reply = conversation.sendMessage(
                "Translate the following Japanese text into natural $language. " +
                    "Output only the translation.\n\n$text",
            )
            return reply.contents.contents
                .filterIsInstance<Content.Text>()
                .joinToString("") { it.text }
        }
    }

    /** Never throws: the idle timer and the model deletion both call it. */
    private fun close() {
        val live = engine ?: return
        engine = null
        loadedPath = null
        backendName = null
        try {
            live.close()
        } catch (e: Throwable) {
            Log.w("GemmaBridge", "closing the engine failed", e)
        }
    }

    private fun conversationConfig(maxOutputToken: Int) = ConversationConfig(
        samplerConfig = SamplerConfig(topK = 1, topP = 1.0, temperature = 0.0, seed = 0),
        maxOutputToken = maxOutputToken,
        thinkingConfig = ThinkingConfig(enableThinking = false),
    )

    fun dispose() {
        worker.execute { close() }
        worker.shutdown()
    }

    private companion object {
        /** Set once CPU has replaced a failed GPU; outlives the activity's bridge. */
        @Volatile
        var gpuUnusable = false
    }
}
