package moe.matthew.mekuru.ocr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import org.json.JSONObject
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import java.io.Closeable
import java.io.File
import java.security.MessageDigest
import kotlin.math.*

/** Reads the same private files or persisted SAF tree grants as the reader.
 * No Activity is needed, so SAF-backed manga also works with the screen off. */
class MangaImageSource(private val context: Context,book: JSONObject,page: JSONObject) : Closeable {
    private val uri: Uri
    private val descriptor: ParcelFileDescriptor
    private val decoder: BitmapRegionDecoder
    val width: Int
    val height: Int
    init {
        val name=page.getString("imageFileName")
        require(!name.startsWith("/") && name.split('/','\\').none { it==".." }) { "invalid_image_path" }
        val tree=book.stringOrNull("safTreeUri")
        uri=if(tree!=null) {
            resolveTree(context,Uri.parse(tree),
                book.getString("safImageDirRelativePath").trimEnd('/')+"/"+name)
        } else Uri.fromFile(File(book.getString("imageDirPath"),name))
        descriptor=open()
        try {
            @Suppress("DEPRECATION")
            val region=BitmapRegionDecoder.newInstance(descriptor.fileDescriptor,false)
                ?: throw IllegalArgumentException("unsupported_image")
            decoder=region
            width=decoder.width; height=decoder.height
            require(width>0 && height>0 && width.toLong()*height<=200_000_000) { "image_too_large" }
            val expectedWidth=page.optInt("imgWidth")
            val expectedHeight=page.optInt("imgHeight")
            require((expectedWidth==0 || width==expectedWidth) &&
                (expectedHeight==0 || height==expectedHeight)) { "image_changed" }
        } catch(e: Throwable) { descriptor.close(); throw e }
    }
    private fun open(): ParcelFileDescriptor = if(uri.scheme=="file")
        ParcelFileDescriptor.open(File(uri.path!!),ParcelFileDescriptor.MODE_READ_ONLY)
        else context.contentResolver.openFileDescriptor(uri,"r")
            ?: throw IllegalStateException("image_unreadable")
    fun hash(): String {
        val digest=MessageDigest.getInstance("SHA-256")
        ParcelFileDescriptor.AutoCloseInputStream(open()).use { input ->
            val bytes=ByteArray(64*1024)
            while(true) {
                val count=input.read(bytes); if(count<0) break
                digest.update(bytes,0,count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    fun preview(): Bitmap {
        var sample=1
        while(max(width,height)/sample>2048) sample*=2
        return decoder.decodeRegion(Rect(0,0,width,height),
            BitmapFactory.Options().apply { inSampleSize=sample; inPreferredConfig=Bitmap.Config.ARGB_8888 })
            ?: throw IllegalStateException("image_unreadable")
    }
    fun crop(quad: List<P>): Bitmap {
        val box=bounds(quad)
        val rect=Rect(floor(box.x1).toInt().coerceIn(0,width-1),
            floor(box.y1).toInt().coerceIn(0,height-1),
            ceil(box.x2).toInt().coerceIn(1,width),ceil(box.y2).toInt().coerceIn(1,height))
        require(rect.width()>0 && rect.height()>0) { "invalid_crop" }
        var sample=1
        while(rect.width().toLong()*rect.height()/(sample*sample)>4_000_000) sample*=2
        val bitmap=decoder.decodeRegion(rect,BitmapFactory.Options().apply {
            inSampleSize=sample; inPreferredConfig=Bitmap.Config.ARGB_8888
        }) ?: throw IllegalStateException("image_unreadable")
        // Whole rectangular blocks must retain native crop pixels. Warping an
        // already rectangular crop introduces a second resize and border pixels.
        if (quad.zip(box.quad()).all { (a,b) -> (a-b).norm()<.001 }) return bitmap
        // Preserve skew and vertical orientation, applying a bounded perspective transform.
        val source=Mat(); val warped=Mat()
        val pts=MatOfPoint2f(*quad.map {
            Point((it.x-rect.left)*bitmap.width/rect.width(),
                (it.y-rect.top)*bitmap.height/rect.height())
        }.toTypedArray())
        val outWidth=max(1,round(((quad[1]-quad[0]).norm()+(quad[2]-quad[3]).norm())/2/sample).toInt())
        val outHeight=max(1,round(((quad[3]-quad[0]).norm()+(quad[2]-quad[1]).norm())/2/sample).toInt())
        val dst=MatOfPoint2f(Point(0.0,0.0),Point(outWidth-1.0,0.0),
            Point(outWidth-1.0,outHeight-1.0),Point(0.0,outHeight-1.0))
        var transform: Mat?=null
        try {
            Utils.bitmapToMat(bitmap,source)
            transform=Imgproc.getPerspectiveTransform(pts,dst)
            Imgproc.warpPerspective(source,warped,transform,Size(outWidth.toDouble(),outHeight.toDouble()),
                Imgproc.INTER_LINEAR,Core.BORDER_CONSTANT,Scalar.all(255.0))
            return Bitmap.createBitmap(outWidth,outHeight,Bitmap.Config.ARGB_8888).also { Utils.matToBitmap(warped,it) }
        } finally { bitmap.recycle(); source.release(); warped.release(); pts.release(); dst.release(); transform?.release() }
    }
    override fun close() { try { decoder.recycle() } finally { descriptor.close() } }
    companion object {
        private fun resolveTree(context: Context,tree: Uri,path: String): Uri {
            var id=DocumentsContract.getTreeDocumentId(tree)
            for(segment in path.split('/').filter { it.isNotEmpty() }) {
                require(segment!="." && segment!="..") { "invalid_image_path" }
                val children=DocumentsContract.buildChildDocumentsUriUsingTree(tree,id)
                var next: String?=null
                context.contentResolver.query(children,arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME),null,null,null)?.use { cursor ->
                    while(cursor.moveToNext()) if(cursor.getString(1)==segment) {
                        next=cursor.getString(0); break
                    }
                }
                id=next ?: throw IllegalStateException("image_access_lost")
            }
            return DocumentsContract.buildDocumentUriUsingTree(tree,id)
        }
    }
}
