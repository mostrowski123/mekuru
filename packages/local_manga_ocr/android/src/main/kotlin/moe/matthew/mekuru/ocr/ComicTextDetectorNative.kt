package moe.matthew.mekuru.ocr

import java.io.Closeable
import java.io.File

/** The pinned detector produces corrupt segmentation outputs in ORT 1.24.3
 * ARM64 CPU execution (also with graph optimizations disabled). OpenCV DNN CPU
 * matches the reference tensor outputs with the identical downloaded weights.
 * Keep lifetime explicit: Java Net.finalize() cannot guarantee model release. */
class ComicTextDetectorNative(file: File, threads: Int) : Closeable {
    private var pointer = create(file.absolutePath, threads)
    @Synchronized fun run(pixels: FloatArray): Array<FloatArray> {
        check(pointer != 0L) { "detector_closed" }
        return forward(pointer, pixels)
    }
    @Synchronized override fun close() {
        if (pointer != 0L) { destroy(pointer); pointer = 0L }
    }
    private external fun create(path: String, threads: Int): Long
    private external fun forward(pointer: Long, pixels: FloatArray): Array<FloatArray>
    private external fun destroy(pointer: Long)
    companion object { init { System.loadLibrary("mekuru_ocr_detector") } }
}
