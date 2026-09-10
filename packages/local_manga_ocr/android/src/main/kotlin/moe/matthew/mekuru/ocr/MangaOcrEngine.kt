package moe.matthew.mekuru.ocr

import ai.onnxruntime.*
import android.content.Context
import android.graphics.Bitmap
import org.json.JSONArray
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import ai.onnxruntime.platform.Fp16Conversions
import java.io.Closeable
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.nio.ShortBuffer
import java.util.concurrent.CancellationException
import kotlin.math.*

data class Recognized(val text: String, val truncated: Boolean)
interface PageOcrEngine : Closeable {
    fun process(source: MangaImageSource, checkpoint: () -> Unit, phase: (String) -> Unit): JSONArray
    fun cancel()
}

/** manga-ocr (kha-white/manga-ocr-base, the same recognizer as the Mekuru OCR
 * server) through its onnx-community ONNX export: a DeiT encoder plus a
 * two-layer BERT decoder, driven by a greedy loop that mirrors the server's
 * generation config (no_repeat_ngram_size 3, max 300 tokens). The decoder
 * export carries no KV cache, so each step re-runs the whole prefix.
 * ponytail: O(T^2) per crop; export decoder_with_past via optimum and host it
 * if phone latency demands, and add 4-beam search if quality demands. */
class MangaOcrEngine(directory: File, threads: Int, loadCheckpoint: () -> Unit = {}) : PageOcrEngine {
    private val env = OrtEnvironment.getEnvironment()
    private val sessions = mutableListOf<OrtSession>()
    private val options = OrtSession.RunOptions()
    @Volatile private var cancelled = false
    private var closed = false
    private val vocabulary: List<String>
    private val encoder: OrtSession
    private val decoder: OrtSession
    private val encoderInput: String
    private val encoderInputType: OnnxJavaType
    private val hiddenType: OnnxJavaType
    private var detector: ComicTextDetectorNative? = null
    var regionProgress: (Int,Int) -> Unit = { _,_ -> }
    var statistics=org.json.JSONObject()
        private set
    init {
        try {
            check(OpenCVLoader.initLocal()) { "opencv_unavailable" }
            fun session(name: String): OrtSession = OrtSession.SessionOptions().use { so ->
                loadCheckpoint()
                so.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
                so.setIntraOpNumThreads(threads.coerceIn(1,2))
                so.setInterOpNumThreads(1)
                so.setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL)
                so.addConfigEntry("session.intra_op.allow_spinning", "0")
                so.setMemoryPatternOptimization(false)
                so.setCPUArenaAllocator(false)
                env.createSession(File(directory,name).absolutePath,so).also {
                    sessions.add(it)
                    loadCheckpoint()
                }
            }
            detector=ComicTextDetectorNative(File(directory,"comictextdetector.onnx"),threads)
            loadCheckpoint()
            encoder=session("encoder_model_fp16.onnx")
            decoder=session("decoder_model_int8.onnx")
            encoderInput=encoder.inputNames.first()
            encoderInputType=(encoder.inputInfo.getValue(encoderInput).info as TensorInfo).type
            hiddenType=(decoder.inputInfo.getValue("encoder_hidden_states").info as TensorInfo).type
            // BERT WordPiece vocabulary, one token per line; ids 0..4 are special.
            vocabulary = File(directory,"vocab.txt").readLines()
        } catch (e: Throwable) { close(); throw e }
    }
    @Synchronized override fun cancel() {
        cancelled=true
        if(!closed) options.setTerminate(true)
    }
    private fun check() { if (cancelled) throw CancellationException("stopped") }
    @Synchronized override fun close() {
        if(closed) return
        closed=true
        sessions.asReversed().forEach { try { it.close() } catch (_: Exception) {} }
        sessions.clear()
        detector?.close(); detector=null
        options.close()
        // The process-wide OrtEnvironment is shared; sessions own all job resources.
    }
    /** Reads fp32, fp16 and bf16 tensors alike. */
    private fun floats(tensor: OnnxValue): FloatArray {
        val buffer = (tensor as OnnxTensor).floatBuffer
        return FloatArray(buffer.remaining()).also { buffer.get(it) }
    }
    private fun tensor(values: FloatArray, shape: LongArray, type: OnnxJavaType): OnnxTensor =
        if (type == OnnxJavaType.FLOAT16) OnnxTensor.createTensor(env,
            ShortBuffer.wrap(ShortArray(values.size) { Fp16Conversions.floatToFp16(values[it]) }),
            shape, OnnxJavaType.FLOAT16)
        else OnnxTensor.createTensor(env, FloatBuffer.wrap(values), shape)
    fun recognize(bitmap: Bitmap, checkpoint: () -> Unit): Recognized {
        check(); checkpoint()
        val pixels = IntArray(bitmap.width*bitmap.height)
        bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height)
        // manga_ocr: img.convert("L").convert("RGB"), bicubic 224, (x/255-.5)/.5
        val normalized = OcrPixels.normalize(
            OcrPixels.resizeRgb(OcrPixels.grayscale(pixels),bitmap.width,bitmap.height),.5f,.5f)
        val tokens = mutableListOf(MangaOcrDecode.BOS)
        var truncated = true
        tensor(normalized,longArrayOf(1,3,224,224),encoderInputType).use { input ->
            encoder.run(mapOf(encoderInput to input),options).use { encoded ->
                val encodedInfo = encoded[0].info as TensorInfo
                tensor(floats(encoded[0]),encodedInfo.shape,hiddenType).use { hidden ->
                    while (tokens.size < MangaOcrDecode.MAX_TOKENS) {
                        check(); checkpoint()
                        val ids = LongArray(tokens.size) { tokens[it].toLong() }
                        val next = OnnxTensor.createTensor(env,LongBuffer.wrap(ids),
                            longArrayOf(1,tokens.size.toLong())).use { input ->
                            decoder.run(mapOf("input_ids" to input,"encoder_hidden_states" to hidden),
                                options).use { out ->
                                // Only the last row of [1, T, vocab] matters; skip copying the rest.
                                val vocabSize = (out[0].info as TensorInfo).shape.last().toInt()
                                val buffer = (out[0] as OnnxTensor).floatBuffer
                                buffer.position(buffer.limit()-vocabSize)
                                MangaOcrDecode.next(FloatArray(vocabSize).also { buffer.get(it) },tokens)
                            }
                        }
                        if (next == MangaOcrDecode.EOS) { truncated = false; break }
                        tokens.add(next)
                    }
                }
            }
        }
        val text = tokens.drop(1).joinToString("") { id ->
            vocabulary.getOrNull(id)?.takeUnless { it.startsWith("[") || it.startsWith("<unused") } ?: ""
        }
        return Recognized(MangaOcrDecode.postProcess(text),truncated)
    }

    private fun recognizeLine(source: MangaImageSource, quad: List<P>, vertical: Boolean,
                              checkpoint: () -> Unit, depth: Int = 0): String {
        val crop=source.crop(quad)
        val recognized=try { recognize(crop,checkpoint) } finally { crop.recycle() }
        if (!recognized.truncated) return recognized.text
        check(depth<6) { "text_too_long" }
        // Split geometry and preserve text order, rather than accepting 128-token truncation.
        val middleA=if(vertical) (quad[0]+quad[3])*.5 else (quad[0]+quad[1])*.5
        val middleB=if(vertical) (quad[1]+quad[2])*.5 else (quad[3]+quad[2])*.5
        val first=if(vertical) listOf(quad[0],quad[1],middleB,middleA)
            else listOf(quad[0],middleA,middleB,quad[3])
        val second=if(vertical) listOf(middleA,middleB,quad[2],quad[3])
            else listOf(middleA,quad[1],quad[2],middleB)
        return recognizeLine(source,first,vertical,checkpoint,depth+1)+
            recognizeLine(source,second,vertical,checkpoint,depth+1)
    }

    override fun process(source: MangaImageSource, checkpoint: () -> Unit,
                         phase: (String) -> Unit): JSONArray {
        phase("detecting"); check(); checkpoint()
        val blocks=detect(source)
        val detectorStats=statistics.optJSONObject("detector")
        statistics=org.json.JSONObject().put("detector",detectorStats).put("detectedBlocks",blocks.size)
            .put("singleLine",0).put("wholeAligned",0).put("lineFallback",0).put("truncatedWhole",0)
        fun count(key: String) { statistics.put(key,statistics.getInt(key)+1) }
        val result=JSONArray()
        regionProgress(0,blocks.size)
        for ((blockIndex, block) in blocks.withIndex()) {
            phase("recognizing"); check(); checkpoint()
            val wholeCrop=source.crop(block.box.quad())
            val whole=try { recognize(wholeCrop,checkpoint) } finally { wholeCrop.recycle() }
            if(whole.truncated) count("truncatedWhole")
            val lines=if(block.lines.size==1 && !whole.truncated) {
                count("singleLine"); listOf(whole.text)
            } else {
                val anchors=block.lines.map { recognizeLine(source,it,block.vertical,checkpoint) }
                val aligned=if(whole.truncated) null else LineAlignment.align(whole.text,anchors)
                if(aligned==null) { count("lineFallback"); anchors }
                else { count("wholeAligned"); aligned }
            }
            regionProgress(blockIndex+1,blocks.size)
            if (lines.all { it.isBlank() }) continue
            result.put(org.json.JSONObject().put("box",JSONArray(block.box.list()))
                .put("vertical",block.vertical).put("fontSize",block.fontSize)
                .put("lines",JSONArray(lines))
                .put("linesCoords",JSONArray(block.lines.map { q -> q.map { listOf(it.x,it.y) } }))
                .put("words",JSONArray()))
        }
        OcrDiagnostics.record(statistics)
        return result
    }

    private fun detect(source: MangaImageSource): List<DetectedBlock> {
        val bitmap=source.preview()
        val rgba=Mat(); val rgb=Mat(); val resized=Mat(); val padded=Mat()
        try {
            Utils.bitmapToMat(bitmap,rgba)
            Imgproc.cvtColor(rgba,rgb,Imgproc.COLOR_RGBA2RGB)
            val ratio=min(1024.0/source.width,1024.0/source.height)
            val w=round(source.width*ratio).toInt().coerceAtLeast(1)
            val h=round(source.height*ratio).toInt().coerceAtLeast(1)
            Imgproc.resize(rgb,resized,Size(w.toDouble(),h.toDouble()),0.0,0.0,Imgproc.INTER_LINEAR)
            Core.copyMakeBorder(resized,padded,0,1024-h,0,1024-w,Core.BORDER_CONSTANT,Scalar.all(0.0))
            val bytes=ByteArray(1024*1024*3); padded.get(0,0,bytes)
            val data=FloatArray(bytes.size) { i ->
                (bytes[(i%(1024*1024))*3+i/(1024*1024)].toInt() and 255)/255f
            }
            check()
            val output=checkNotNull(detector) { "detector_closed" }.run(data)
            check()
            val mask=output[1]; val lines=output[2]
            if(BuildConfig.DEBUG) {
                val rows=IntArray(1024); val columns=IntArray(1024)
                for(i in 0 until 1024*1024) if(lines[i]>.3f) {
                    rows[i/1024]++; columns[i%1024]++
                }
                statistics=org.json.JSONObject().put("detector",org.json.JSONObject()
                    .put("backend","opencv-dnn-cpu")
                    .put("rows",JSONArray(rows.toList())).put("columns",JSONArray(columns.toList()))
                    .put("width",source.width).put("height",source.height))
            }
            return postprocess(output[0],mask,lines,source.width,source.height,w,h)
        } finally {
            bitmap.recycle(); rgba.release(); rgb.release(); resized.release(); padded.release()
        }
    }

    /** DBNet/Yolo postprocessing port from Comic Text Detector (GPL-3.0).
     * minAreaRect expansion is computed analytically for its rectangular input. */
    private fun postprocess(raw: FloatArray, mask: FloatArray, linesMap: FloatArray,
                            width: Int,height: Int,scaledWidth: Int,scaledHeight: Int): List<DetectedBlock> {
        val sx=width.toDouble()/scaledWidth; val sy=height.toDouble()/scaledHeight
        fun scaled(p: Point)=P((p.x*sx).coerceIn(0.0,width-1.0),(p.y*sy).coerceIn(0.0,height-1.0))
        data class Candidate(val box: Box,val score: Float,val cls: Int)
        val candidates=mutableListOf<Candidate>()
        for (i in raw.indices step 7) {
            if(raw[i+4]<=.4f) continue
            val cls=if(raw[i+5]>raw[i+6]) 0 else 1
            val score=raw[i+4]*raw[i+5+cls]
            if(score<=.4f) continue
            candidates.add(Candidate(Box(
                ((raw[i]-raw[i+2]/2)*sx).coerceIn(0.0,width-1.0),
                ((raw[i+1]-raw[i+3]/2)*sy).coerceIn(0.0,height-1.0),
                ((raw[i]+raw[i+2]/2)*sx).coerceIn(0.0,width-1.0),
                ((raw[i+1]+raw[i+3]/2)*sy).coerceIn(0.0,height-1.0)),score,cls))
        }
        val kept=mutableListOf<Candidate>()
        for(c in candidates.sortedByDescending { it.score }.take(30000)) {
            if(c.box.area<=0) continue
            if(kept.none { k -> k.cls==c.cls &&
                k.box.intersect(c.box)/(k.box.area+c.box.area-k.box.intersect(c.box))>.35 }) kept.add(c)
            if(kept.size==300) break
        }
        val binary=Mat(1024,1024,CvType.CV_8UC1)
        val hierarchy=Mat()
        val contours=mutableListOf<MatOfPoint>()
        val lines=mutableListOf<List<P>>()
        try {
            binary.put(0,0,ByteArray(1024*1024) { if(linesMap[it]>.3f) 255.toByte() else 0 })
            Imgproc.findContours(binary,contours,hierarchy,Imgproc.RETR_LIST,Imgproc.CHAIN_APPROX_SIMPLE)
            for (contour in contours.take(1000)) {
                val points=MatOfPoint2f(*contour.toArray())
                try {
                    val rect=Imgproc.minAreaRect(points)
                    if(min(rect.size.width,rect.size.height)<2) continue
                    val roi=Imgproc.boundingRect(contour)
                    val region=Mat.zeros(roi.height,roi.width,CvType.CV_8UC1)
                    val shifted=MatOfPoint(*contour.toArray().map { Point(it.x-roi.x,it.y-roi.y) }.toTypedArray())
                    val score=try {
                        Imgproc.fillPoly(region,listOf(shifted),Scalar.all(1.0))
                        val support=ByteArray(roi.width*roi.height); region.get(0,0,support)
                        var sum=0.0; var count=0
                        for (i in support.indices) if(support[i].toInt()!=0) {
                            sum+=linesMap[(roi.y+i/roi.width)*1024+roi.x+i%roi.width]; count++
                        }
                        if(count==0) 0.0 else sum/count
                    } finally { region.release(); shifted.release() }
                    if(score<=.6) continue
                    val distance=rect.size.area()*1.5/(2*(rect.size.width+rect.size.height))
                    rect.size=Size(rect.size.width+2*distance,rect.size.height+2*distance)
                    val corners=Array(4) { Point() }; rect.points(corners)
                    val xs=corners.sortedBy { it.x }
                    val left=xs.take(2).sortedBy { it.y }; val right=xs.drop(2).sortedBy { it.y }
                    lines.add(listOf(left[0],right[0],right[1],left[1]).map { scaled(it) })
                } finally { points.release() }
            }
        } finally { contours.forEach { it.release() }; binary.release(); hierarchy.release() }
        fun maskMean(box: Box): Double {
            val x1=(box.x1/sx).toInt().coerceIn(0,1023); val x2=ceil(box.x2/sx).toInt().coerceIn(x1+1,1024)
            val y1=(box.y1/sy).toInt().coerceIn(0,1023); val y2=ceil(box.y2/sy).toInt().coerceIn(y1+1,1024)
            var sum=0.0
            for(y in y1 until y2) for(x in x1 until x2) sum+=mask[y*1024+x]
            return sum/((x2-x1)*(y2-y1))
        }
        return ComicGeometry.group(kept.map { DetectedBlock(it.box,it.cls==1) },
            lines,width,height,::maskMean)
    }
}
