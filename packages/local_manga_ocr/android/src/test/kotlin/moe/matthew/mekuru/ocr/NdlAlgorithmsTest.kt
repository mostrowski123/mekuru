package moe.matthew.mekuru.ocr

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

/** The same vectors as the app's ndl_ocr_algorithms_test.dart. */
class NdlAlgorithmsTest {
    private val vectors = JSONObject(javaClass.getResource("/ndl_vectors.json")!!.readText())
    private fun sha256(bytes: ByteArray) =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun strings(array: org.json.JSONArray) = (0 until array.length()).map { array.getString(it) }

    @Test fun resizedPixelsAndTensorsMatchSharedDigests() {
        val rows = vectors.getJSONArray("resize").objects()
        assertTrue(rows.isNotEmpty())
        for (row in rows) {
            val w = row.getInt("width"); val h = row.getInt("height")
            assertEquals("${w}x$h", row.getBoolean("vertical"), NdlAlgorithms.isVertical(w, h))
            val image = IntArray(w*h) {
                val x = it%w; val y = it/w
                (((x*13+y*7)%256) shl 16) or (((x*3+y*29)%256) shl 8) or ((x*47+y*11)%256)
            }
            val rgb = NdlAlgorithms.resizeLine(image, w, h)
            val bytes = ByteArray(rgb.size*3) { ((rgb[it/3] shr (16-(it%3)*8)) and 255).toByte() }
            assertEquals("${w}x$h", row.getString("rgbSha256"), sha256(bytes))
            val tensor = NdlAlgorithms.normalize(rgb)
            val le = ByteBuffer.allocate(tensor.size*4).order(ByteOrder.LITTLE_ENDIAN)
            le.asFloatBuffer().put(tensor)
            assertEquals("${w}x$h", row.getString("tensorSha256"), sha256(le.array()))
        }
    }
    @Test fun verticalLineIsTurnedCounterClockwise() {
        // 2 wide, 3 tall: a b / c d / e f becomes b d f / a c e.
        assertArrayEquals(intArrayOf(2,4,6,1,3,5),
            NdlAlgorithms.rotateCounterClockwise(intArrayOf(1,2,3,4,5,6), 2, 3))
        assertFalse(NdlAlgorithms.isVertical(100, 80))
        assertTrue(NdlAlgorithms.isVertical(100, 81))
    }
    @Test fun normalizationIsRgbChannelFirst() {
        assertArrayEquals(floatArrayOf(1f,-1f,-1f,1f,-1f,-1f),
            NdlAlgorithms.normalize(intArrayOf(0xff0000, 0x00ff00)), 0f)
        // Bitmap.getPixels carries alpha; it must not leak into the red channel.
        assertArrayEquals(NdlAlgorithms.normalize(intArrayOf(0x123456)),
            NdlAlgorithms.normalize(intArrayOf(0xff123456.toInt())), 0f)
    }
    @Test fun decodeMatchesSharedCases() {
        for (row in vectors.getJSONArray("decode").objects()) {
            val raw = row.getJSONArray("logits")
            val logits = FloatArray(raw.length()) { raw.getDouble(it).toFloat() }
            assertEquals(row.getString("text"), NdlAlgorithms.decode(logits, row.getInt("steps"),
                row.getInt("classes"), strings(row.getJSONArray("charset"))))
        }
    }
    @Test fun charsetMatchesSharedCases() {
        for (row in vectors.getJSONArray("charset").objects()) {
            assertEquals(strings(row.getJSONArray("chars")), NdlAlgorithms.parseCharset(row.getString("yaml")))
        }
    }
    @Test fun charsetRejectsMissingOrUnsupportedValues() {
        for (yaml in listOf("model:\n", "  charset_train: \"a\\nb\"\n", "  charset_train: \"abc\n")) {
            assertThrows(IllegalArgumentException::class.java) { NdlAlgorithms.parseCharset(yaml) }
        }
    }
    @Test fun longLinesAreLongerThanFourteenTimesTheirThickness() {
        // TL, TR, BR, BL of a 10-wide column and a 10-tall row.
        fun quad(w: Double, h: Double) = listOf(P(0.0,0.0), P(w,0.0), P(w,h), P(0.0,h))
        assertTrue(NdlAlgorithms.isLongLine(quad(10.0, 141.0), vertical = true))
        assertFalse(NdlAlgorithms.isLongLine(quad(10.0, 140.0), vertical = true))
        assertFalse(NdlAlgorithms.isLongLine(quad(10.0, 141.0), vertical = false))
        assertTrue(NdlAlgorithms.isLongLine(quad(141.0, 10.0), vertical = false))
        assertFalse(NdlAlgorithms.isLongLine(quad(140.0, 10.0), vertical = false))
        // A slanted column: measured along its sides, not its bounding box.
        val slanted = listOf(P(0.0,0.0), P(10.0,0.0), P(110.0,100.0), P(100.0,100.0))
        assertTrue(NdlAlgorithms.isLongLine(slanted, vertical = true))
    }
}
