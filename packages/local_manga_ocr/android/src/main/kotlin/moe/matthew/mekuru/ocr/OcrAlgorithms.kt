package moe.matthew.mekuru.ocr

import kotlin.math.*

/** Character offsets are Unicode code points here; conversion back to UTF-16
 * happens only when building Java/Dart strings. Do not split surrogate pairs. */
object LineAlignment {
    fun align(whole: String, lines: List<String>): List<String>? {
        if (lines.isEmpty() || lines.any { it.isEmpty() } || whole.isEmpty()) return null
        if (lines.size == 1) return listOf(whole)
        val source = lines.joinToString("").codePoints().toArray()
        val target = whole.codePoints().toArray()
        // Decoding is bounded, but also bound independently for malformed inputs.
        if (source.size.toLong() * target.size > 4_000_000) return null
        val n = source.size
        val m = target.size
        val forward = Array(n + 1) { IntArray(m + 1) }
        for (i in 0..n) forward[i][0] = i
        for (j in 0..m) forward[0][j] = j
        for (i in 1..n) for (j in 1..m) {
            forward[i][j] = minOf(forward[i-1][j] + 1,
                forward[i][j-1] + 1, forward[i-1][j-1] +
                    if (source[i-1] == target[j-1]) 0 else 1)
        }
        val cost = forward[n][m]
        if (cost.toDouble() / max(n, m) > .25) return null
        val backward = Array(n + 1) { IntArray(m + 1) }
        for (i in 0..n) backward[i][m] = n-i
        for (j in 0..m) backward[n][j] = m-j
        for (i in n-1 downTo 0) for (j in m-1 downTo 0) {
            backward[i][j] = minOf(backward[i+1][j] + 1,
                backward[i][j+1] + 1, backward[i+1][j+1] +
                    if (source[i] == target[j]) 0 else 1)
        }
        val cuts = mutableListOf(0)
        var boundary = 0
        for (line in lines.dropLast(1)) {
            boundary += line.codePointCount(0, line.length)
            val candidates = (0..m).filter {
                forward[boundary][it] + backward[boundary][it] == cost
            }
            if (candidates.size != 1 || candidates.single() <= cuts.last()) return null
            cuts.add(candidates.single())
        }
        if (cuts.last() >= m) return null
        cuts.add(m)
        return cuts.zipWithNext().map { (a, b) -> String(target, a, b-a) }
    }
}

/** Port of Baberu onnx_infer.py decoding controls (Apache-2.0).
 * Modified for Android, 2026-09-10. See assets/licenses/BABERU.txt. */
object BaberuDecode {
    fun next(logits: FloatArray, sequence: List<Int>, contentIds: Set<Int>): Int {
        val values = DoubleArray(logits.size) { logits[it].toDouble() }
        for (id in sequence.toSet()) if (id in values.indices) {
            values[id] = if (values[id] < 0) values[id] * 1.2 else values[id] / 1.2
        }
        val last = sequence.lastOrNull()
        if (last != null && last in contentIds &&
            sequence.asReversed().takeWhile { it == last }.size >= 12) {
            values[last] = Double.NEGATIVE_INFINITY
        }
        var best = 0
        for (i in 1 until values.size) if (values[i] > values[best]) best = i
        return best
    }

    fun content(character: String): Boolean {
        if (character.codePointCount(0, character.length) != 1 ||
            character in listOf("ー", "ｰ", "〜", "~")) return false
        val cp=character.codePointAt(0)
        val kind=Character.getType(cp)
        return Character.isLetterOrDigit(cp) || kind==Character.LETTER_NUMBER.toInt() ||
            kind==Character.OTHER_NUMBER.toInt()
    }
}

/** Pillow-compatible separable bicubic resize of RGB bytes, including
 * antialias support on downscaling and rounding after each pass. */
object BaberuPixels {
    private fun kernel(x0: Double): Double {
        val x = abs(x0)
        return when {
            x < 1 -> ((1.5*x - 2.5)*x)*x + 1
            x < 2 -> (((-.5*x + 2.5)*x - 4)*x) + 2
            else -> 0.0
        }
    }
    private data class Coeff(val first: Int, val weights: IntArray)
    private fun coefficients(input: Int, output: Int): List<Coeff> =
        (0 until output).map { at ->
            val scale = input.toDouble()/output
            val filterScale = max(1.0, scale)
            val center = (at+.5)*scale
            val first = max(0, (center-2*filterScale+.5).toInt())
            val end = min(input, (center+2*filterScale+.5).toInt())
            val raw = DoubleArray(end-first) {
                kernel((it+first-center+.5)/filterScale)
            }
            val sum = raw.sum()
            Coeff(first, IntArray(raw.size) {
                val value = raw[it] / sum * (1 shl 22)
                if (value < 0) (value-.5).toInt() else (value+.5).toInt()
            })
        }
    fun resizeRgb(pixels: IntArray, width: Int, height: Int, size: Int = 224): IntArray {
        require(width > 0 && height > 0 && pixels.size == width*height)
        val xs = coefficients(width, size)
        val ys = coefficients(height, size)
        val middle = IntArray(size*height)
        fun channel(sum: Long) = (sum shr 22).toInt().coerceIn(0,255)
        for (y in 0 until height) for (x in 0 until size) {
            val c = xs[x]
            var r = 1L shl 21; var g = r; var b = r
            for (k in c.weights.indices) {
                val p = pixels[y*width+c.first+k]; val w = c.weights[k].toLong()
                r += ((p ushr 16) and 255)*w
                g += ((p ushr 8) and 255)*w; b += (p and 255)*w
            }
            middle[y*size+x] = (channel(r) shl 16) or (channel(g) shl 8) or channel(b)
        }
        return IntArray(size*size) { index ->
            val x = index % size; val c = ys[index/size]
            var r = 1L shl 21; var g = r; var b = r
            for (k in c.weights.indices) {
                val p = middle[(c.first+k)*size+x]; val w = c.weights[k].toLong()
                r += ((p ushr 16) and 255)*w
                g += ((p ushr 8) and 255)*w; b += (p and 255)*w
            }
            (channel(r) shl 16) or (channel(g) shl 8) or channel(b)
        }
    }
    fun normalize(rgb: IntArray): FloatArray {
        val means = floatArrayOf(.485f,.456f,.406f)
        val stds = floatArrayOf(.229f,.224f,.225f)
        return FloatArray(rgb.size*3) { i ->
            val c = i/rgb.size
            val value = (rgb[i%rgb.size] ushr (16-c*8)) and 255
            (value/255f-means[c])/stds[c]
        }
    }
}
