package moe.matthew.mekuru.ocr

import kotlin.math.*

/** Pre- and post-processing for NDLOCR-Lite's text-line recognizer (PARSeq,
 * the 100-character model, National Diet Library, CC BY 4.0), which reads the
 * long lines of scanned text pages that manga-ocr cannot. Mirrors the app's
 * `ndl_ocr_algorithms.dart` and shares its test vectors (`ndl_vectors.json`),
 * so both platforms feed the model identical tensors. Pixels are packed RGB;
 * any alpha byte is ignored. */
object NdlAlgorithms {
    const val MODEL_FILE = "parseq-ndl-24x768-100-tiny-153epoch-tegaki3-r8data-202604.onnx"
    const val CHARSET_FILE = "NDLmoji.yaml"
    const val INPUT_WIDTH = 768
    const val INPUT_HEIGHT = 24
    /** A line is read by NDL when it is longer than this many times its thickness. */
    const val LONG_LINE_RATIO = 14.0

    /** Whether a detected line quad (TL, TR, BR, BL) is too long for manga-ocr:
     * its length along the reading direction over its thickness. */
    fun isLongLine(quad: List<P>, vertical: Boolean): Boolean {
        val down = ((quad[0]-quad[3]).norm()+(quad[1]-quad[2]).norm())/2
        val across = ((quad[0]-quad[1]).norm()+(quad[3]-quad[2]).norm())/2
        return if (vertical) down > LONG_LINE_RATIO*across else across > LONG_LINE_RATIO*down
    }

    /** The `charset_train` list of `NDLmoji.yaml`: that line's double-quoted
     * value, with `\"` and `\\` unescaped, split into code points. */
    fun parseCharset(yaml: String): List<String> {
        val key = "charset_train:"
        val line = yaml.split('\n').firstOrNull { it.trimStart().startsWith(key) }
            ?: throw IllegalArgumentException("No charset_train")
        val quote = line.indexOf('"', line.indexOf(key))
        require(quote >= 0) { "charset_train is not quoted" }
        val chars = mutableListOf<String>()
        var escaped = false
        for (cp in line.substring(quote+1).codePoints()) {
            val ch = String(Character.toChars(cp))
            if (escaped) {
                require(ch == "\"" || ch == "\\") { "Unsupported escape \\$ch in charset_train" }
                chars.add(ch); escaped = false
            } else if (ch == "\\") escaped = true
            else if (ch == "\"") return chars
            else chars.add(ch)
        }
        throw IllegalArgumentException("charset_train is not terminated")
    }

    /** Greedy decoding of `[1, steps, classes]` logits: the best class at each
     * step (the first on ties) up to the first end token, class 0. Class `i`
     * is `charset[i - 1]`. */
    fun decode(logits: FloatArray, steps: Int, classes: Int, charset: List<String>): String {
        val text = StringBuilder()
        for (step in 0 until steps) {
            val row = step*classes
            var best = 0
            for (c in 1 until classes) if (logits[row+c] > logits[row+best]) best = c
            if (best == 0) break
            text.append(charset[best-1])
        }
        return text.toString()
    }

    /** NDL turns a line upright when it is taller than 0.8 times its width. */
    fun isVertical(width: Int, height: Int) = height > width*0.8

    /** `cv2.ROTATE_90_COUNTERCLOCKWISE`: [height] wide, [width] tall. */
    fun rotateCounterClockwise(pixels: IntArray, width: Int, height: Int): IntArray {
        val out = IntArray(pixels.size)
        for (y in 0 until width) for (x in 0 until height) out[y*height+x] = pixels[x*width+width-1-y]
        return out
    }

    /** `cv2.resize(INTER_LINEAR)` semantics in doubles, in exactly the order
     * the Dart doc comment specifies (no fused multiply-add), so the result is
     * bit-identical to the Dart version. */
    fun resize(pixels: IntArray, width: Int, height: Int,
               outWidth: Int = INPUT_WIDTH, outHeight: Int = INPUT_HEIGHT): IntArray {
        require(width > 0 && height > 0 && pixels.size == width*height)
        val xs = taps(width, outWidth)
        val ys = taps(height, outHeight)
        val out = IntArray(outWidth*outHeight)
        for (y in 0 until outHeight) {
            val ty = ys[y]
            for (x in 0 until outWidth) {
                val tx = xs[x]
                val p00 = pixels[ty.i0*width+tx.i0]; val p01 = pixels[ty.i0*width+tx.i1]
                val p10 = pixels[ty.i1*width+tx.i0]; val p11 = pixels[ty.i1*width+tx.i1]
                var rgb = 0
                for (shift in 16 downTo 0 step 8) {
                    val top = ((p00 shr shift) and 255)*tx.w0 + ((p01 shr shift) and 255)*tx.w1
                    val bottom = ((p10 shr shift) and 255)*tx.w0 + ((p11 shr shift) and 255)*tx.w1
                    rgb = (rgb shl 8) or floor(top*ty.w0 + bottom*ty.w1 + .5).toInt()
                }
                out[y*outWidth+x] = rgb
            }
        }
        return out
    }

    private class Tap(val i0: Int, val i1: Int, val w0: Double, val w1: Double)
    private fun taps(input: Int, output: Int): Array<Tap> {
        val scale = input.toDouble()/output
        return Array(output) { i ->
            val at = min(max((i+.5)*scale-.5, 0.0), input-1.0)
            val i0 = floor(at).toInt()
            val w1 = at-i0
            Tap(i0, min(i0+1, input-1), 1-w1, w1)
        }
    }

    /** One line crop, upright and resized to [INPUT_WIDTH] x [INPUT_HEIGHT]. */
    fun resizeLine(pixels: IntArray, width: Int, height: Int): IntArray =
        if (isVertical(width, height)) resize(rotateCounterClockwise(pixels, width, height), height, width)
        else resize(pixels, width, height)

    /** Channel-first `v / 127.5 - 1`, rounded to float after the division and
     * again after the subtraction, like NDL's numpy code. R, G, B as the model
     * was trained; NDL's parseq.py reverses them (see ndl_ocr_algorithms.dart). */
    fun normalize(rgb: IntArray): FloatArray = FloatArray(rgb.size*3) { i ->
        SCALED[(rgb[i%rgb.size] shr (16-i/rgb.size*8)) and 255]
    }
    private val SCALED = FloatArray(256) { (it/127.5).toFloat()-1f }
}
