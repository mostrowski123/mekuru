package moe.matthew.mekuru.ocr

import android.graphics.Bitmap
import org.aomedia.avif.android.AvifDecoder
import java.nio.ByteBuffer

/** AVIF through libavif, for what Android's own decoders cannot read: every
 * AVIF before Android 12, and BitmapRegionDecoder's on versions that do not
 * list it. The app's `mekuru/image_convert` channel decodes with it too. */
object Avif {
    /** A mutable ARGB_8888 bitmap, or null when [bytes] are not AVIF, hold
     * more than [maxPixels], or fail to decode. */
    fun decode(bytes: ByteArray, maxPixels: Long = 50_000_000): Bitmap? {
        val buffer = ByteBuffer.allocateDirect(bytes.size).put(bytes)
        buffer.flip()
        if (!AvifDecoder.isAvifImage(buffer)) return null
        val info = AvifDecoder.Info()
        if (!AvifDecoder.getInfo(buffer, bytes.size, info) || info.width <= 0 || info.height <= 0 ||
            info.width.toLong() * info.height > maxPixels) return null
        val bitmap = Bitmap.createBitmap(info.width, info.height, Bitmap.Config.ARGB_8888)
        if (AvifDecoder.decode(buffer, bytes.size, bitmap)) return bitmap
        bitmap.recycle()
        return null
    }
}
