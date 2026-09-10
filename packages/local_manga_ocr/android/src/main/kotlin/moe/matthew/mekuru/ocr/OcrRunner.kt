package moe.matthew.mekuru.ocr

import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CancellationException

data class OcrPageOutput(val blocks: JSONArray, val inputHash: String)
class OcrPause(val reason: String) : CancellationException(reason)

/** Platform-independent job loop. The Android service owns model/resources;
 * tests exercise actual journal and cache writes with deterministic page IO. */
class OcrRunner(private val store: OcrStore,private val id: String) {
    fun run(
        resourceCheck: () -> Unit = {},
        process: (JSONObject,JSONObject,()->Unit,(String)->Unit)->OcrPageOutput
    ) {
        var lastCheck=0L
        fun checkpoint(force: Boolean = false) {
            val now=System.nanoTime()
            if(!force && now-lastCheck<1_000_000_000) return
            lastCheck=now
            if(store.read(id).getString("status") !in setOf("running","preparing")) throw OcrPause("stopped")
            resourceCheck()
        }
        try {
            val (job,book)=store.snapshot(id)
            if(job.getString("status")=="queued") store.transition(id,"preparing")
            checkpoint(true)
            store.transition(id,"running")
            var consecutiveFailures=0
            for(index in job.getJSONArray("pages").ints()) {
                checkpoint(true)
                val current=store.read(id)
                if(current.getJSONObject("outcomes").has(index.toString())) continue
                val page=book.getJSONArray("pages").getJSONObject(index)
                if(!job.optBoolean("replace") && OcrStore.pageComplete(book,page)) {
                    store.outcome(id,index,"skipped"); continue
                }
                try {
                    val started=System.nanoTime()
                    val output=process(book,page,{ checkpoint() },{ phase -> store.phase(id,phase,index) })
                    checkpoint(true)
                    store.commit(id,index,output.blocks,output.inputHash,(System.nanoTime()-started)/1e6)
                    consecutiveFailures=0
                } catch(stop: CancellationException) { throw stop }
                catch(error: Exception) {
                    checkpoint(true)
                    store.outcome(id,index,"failed",error.message ?: "page_failed")
                    consecutiveFailures++
                    if(consecutiveFailures>=3) {
                        store.transition(id,"failed","consecutive_page_failures"); return
                    }
                }
            }
            val outcomes=store.read(id).getJSONObject("outcomes")
            val failed=outcomes.keys().asSequence().any { outcomes.getString(it)=="failed" }
            store.transition(id,if(failed) "completedWithErrors" else "completed")
        } catch(stop: CancellationException) {
            val job=store.read(id)
            when(job.getString("status")) {
                "cancelling" -> store.transition(id,"cancelled")
                in OcrStore.active -> store.transition(id,"paused",
                    job.stringOrNull("reason") ?: (stop as? OcrPause)?.reason ?: "interrupted")
            }
        } catch(error: Throwable) {
            store.pauseAfterFailure(id,
                if(error is OutOfMemoryError) "low_memory" else error.message ?: "runtime_error")
        }
    }
}
