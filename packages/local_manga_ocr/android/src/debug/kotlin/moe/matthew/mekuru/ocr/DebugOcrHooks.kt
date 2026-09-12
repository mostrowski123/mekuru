package moe.matthew.mekuru.ocr

import org.json.JSONObject
import org.json.JSONArray

/** Compiled only into debug variants. Real native storage/service, fake inference. */
object DebugOcrHooks {
    const val enabled=true
    fun accept(job: JSONObject)=job.optBoolean("testEngine")
    fun evaluate(context: android.content.Context,args: JSONObject): JSONObject {
        val manifest=java.io.File(args.getString("manifestPath")).canonicalFile
        require(manifest.path.startsWith(context.filesDir.canonicalPath+java.io.File.separator))
        val rows=JSONArray(manifest.readText())
        val output=java.io.File(manifest.parentFile,"predictions.jsonl")
        val metadata=java.io.File(manifest.parentFile,"evaluation.json")
        OcrRuntime.models.verify()
        val started=System.currentTimeMillis()
        var completed=0
        MangaOcrEngine(OcrRuntime.models.installedDirectory,2).use { engine ->
            java.io.FileOutputStream(output).bufferedWriter().use { writer ->
                for(i in 0 until rows.length()) {
                    val row=rows.getJSONObject(i)
                    val image=java.io.File(manifest.parentFile,row.getString("image")).canonicalFile
                    require(image.path.startsWith(requireNotNull(manifest.parentFile).canonicalPath+java.io.File.separator))
                    val start=System.nanoTime()
                    val record=JSONObject().put("id",row.getString("id"))
                    if(args.optString("mode")=="pages") {
                        val book=JSONObject().put("imageDirPath",manifest.parent)
                        val page=JSONObject().put("imageFileName",row.getString("image"))
                            .put("imgWidth",row.getInt("width")).put("imgHeight",row.getInt("height"))
                        MangaImageSource(context,book,page).use { source ->
                            record.put("blocks",engine.process(source,{},{ }))
                                .put("diagnostics",engine.statistics.cloneJson())
                        }
                    } else {
                        val bitmap=android.graphics.BitmapFactory.decodeFile(image.path)
                            ?: error("evaluation_image_unreadable")
                        val recognized=try { engine.recognize(bitmap,{}) } finally { bitmap.recycle() }
                        record.put("text",recognized.text).put("truncated",recognized.truncated)
                    }
                    writer.write(record.put("ms",(System.nanoTime()-start)/1e6).toString())
                    writer.newLine(); writer.flush()
                    completed++
                    if(completed%10==0) OcrWrites.atomic(metadata,JSONObject().put("completed",completed)
                        .put("total",rows.length()).put("elapsedMs",System.currentTimeMillis()-started)
                        .put("nativeHeapBytes",android.os.Debug.getNativeHeapAllocatedSize()).toString())
                }
            }
        }
        val result=JSONObject().put("completed",completed).put("total",rows.length())
            .put("elapsedMs",System.currentTimeMillis()-started).put("status","completed")
            .put("abi",android.os.Build.SUPPORTED_ABIS[0]).put("sdk",android.os.Build.VERSION.SDK_INT)
            .put("modelVersion",OcrRuntime.models.version)
        OcrWrites.atomic(metadata,result.toString())
        // Predictions are streamed to the private host monitor. Keep the method
        // channel response small, even for a complete multi-thousand-crop run.
        return result
    }
    fun detectorFixture(context: android.content.Context,args: JSONObject): JSONObject {
        val file=java.io.File(args.getString("path")).canonicalFile
        require(file.path.startsWith(context.filesDir.canonicalPath+java.io.File.separator))
        val engine=ComicTextDetectorNative(file,1)
        val passes=JSONArray()
        try {
            for(value in listOf(.25f,.75f)) {
                val result=engine.run(FloatArray(3*1024*1024) { value })
                passes.put(JSONArray(result.map { array -> JSONObject()
                    .put("size",array.size).put("first",array.first()).put("last",array.last()) }))
            }
        } finally { engine.close() }
        val rejected=try { engine.run(FloatArray(0)); false } catch(_: IllegalStateException) { true }
        return JSONObject().put("passes",passes).put("closedRejected",rejected)
    }
    /** A `testEngine` speed test exercises the lease, thread and cancel plumbing
     * without weights: it sleeps `testDelaySteps` x 25 ms and finds no text. */
    fun benchmarkEngine(args: JSONObject): PageOcrEngine? {
        if(!accept(args)) return null
        return object : PageOcrEngine {
            @Volatile private var cancelled=false
            override fun process(source: MangaImageSource,checkpoint: ()->Unit,phase: (String)->Unit): JSONArray {
                for(i in 0 until args.optInt("testDelaySteps",10)) {
                    if(cancelled) throw java.util.concurrent.CancellationException("stopped")
                    checkpoint(); Thread.sleep(25)
                }
                return JSONArray()
            }
            override fun cancel() { cancelled=true }
            override fun close() {}
        }
    }
    fun processor(job: JSONObject): ((JSONObject,JSONObject,()->Unit,(String)->Unit)->OcrPageOutput)? {
        if(!accept(job)) return null
        return { _,page,checkpoint,phase ->
            phase("recognizing")
            val steps=job.optInt("testDelaySteps",10)
            for(i in 0 until steps) { checkpoint(); Thread.sleep(25) }
            val index=page.getInt("pageIndex")
            if(index==job.optInt("testFailPage",-1)) throw IllegalStateException("test_page_failure")
            val blocks=JSONArray()
            if(index!=job.optInt("testBlankPage",-1)) blocks.put(JSONObject()
                .put("box",JSONArray(listOf(10,10,40,100))).put("vertical",true).put("fontSize",30)
                .put("lines",JSONArray(listOf("日本語")))
                .put("linesCoords",JSONArray(listOf(listOf(listOf(10,10),listOf(40,10),listOf(40,100),listOf(10,100)))))
                .put("words",JSONArray()))
            OcrPageOutput(blocks,"test-"+index)
        }
    }
}
