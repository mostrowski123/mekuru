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

/** Greedy decoding and text clean-up matching manga_ocr's generation config
 * and post_process(), so on-device text agrees with the server. */
object MangaOcrDecode {
    const val BOS = 2
    const val EOS = 3
    const val MAX_TOKENS = 300
    private const val NO_REPEAT_NGRAM = 3

    /** Argmax over [logits], never completing a trigram already present in [sequence]. */
    fun next(logits: FloatArray, sequence: List<Int>): Int {
        val banned = HashSet<Int>()
        val prefix = NO_REPEAT_NGRAM - 1
        if (sequence.size >= prefix) {
            val tail = sequence.subList(sequence.size - prefix, sequence.size)
            for (i in 0..sequence.size - NO_REPEAT_NGRAM) {
                if (sequence.subList(i, i + prefix) == tail) banned.add(sequence[i + prefix])
            }
        }
        var best = -1
        for (i in logits.indices) {
            if (i !in banned && (best < 0 || logits[i] > logits[best])) best = i
        }
        return best
    }

    private const val HALF_KANA = "｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ"
    private const val FULL_KANA = "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン"

    /** manga_ocr.ocr.post_process: strip whitespace, normalize dot runs, then
     * jaconv.h2z(ascii=True, digit=True) with its default kana conversion. */
    fun postProcess(text: String): String {
        var result = text.filterNot { it.isWhitespace() }.replace("…", "...")
        result = Regex("[・.]{2,}").replace(result) { ".".repeat(it.value.length) }
        val out = StringBuilder(result.length)
        for (ch in result) {
            val kana = HALF_KANA.indexOf(ch)
            when {
                kana >= 0 -> out.append(FULL_KANA[kana])
                ch == 'ﾞ' || ch == 'ﾟ' -> {
                    // jaconv composes only where a precomposed kana exists (ｶﾞ -> ガ)
                    // and otherwise keeps the half-width mark as is.
                    val mark = if (ch == 'ﾞ') "\u3099" else "\u309A"
                    val bases = if (ch == 'ﾞ') "ウカキクケコサシスセソタチツテトハヒフヘホ" else "ハヒフヘホ"
                    val composed = if (out.isNotEmpty() && out.last() in bases) java.text.Normalizer.normalize(
                        out.last() + mark, java.text.Normalizer.Form.NFC) else ""
                    if (composed.length == 1) out.setCharAt(out.length - 1, composed[0]) else out.append(ch)
                }
                ch in '!'..'~' -> out.append(ch + 0xFEE0)
                else -> out.append(ch)
            }
        }
        return out.toString()
    }
}

/** Pillow-compatible separable bicubic resize of RGB bytes, including
 * antialias support on downscaling and rounding after each pass. */
object OcrPixels {
    /** PIL convert("L") replicated into every channel. */
    fun grayscale(rgb: IntArray): IntArray = IntArray(rgb.size) {
        val p = rgb[it]
        val l = (((p ushr 16) and 255)*19595 + ((p ushr 8) and 255)*38470 + (p and 255)*7471 + 0x8000) ushr 16
        (l shl 16) or (l shl 8) or l
    }
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
    /** Channel-first float tensor, (x/255 - mean) / std per channel. */
    fun normalize(rgb: IntArray, mean: Float, std: Float): FloatArray =
        FloatArray(rgb.size*3) { i ->
            val c = i/rgb.size
            val value = (rgb[i%rgb.size] ushr (16-c*8)) and 255
            (value/255f-mean)/std
        }
}
