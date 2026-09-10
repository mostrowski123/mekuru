package moe.matthew.mekuru.ocr

import org.junit.*
import org.junit.Assert.*
import java.io.*
import java.net.*
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.CancellationException

class ModelTransferTest {
    private lateinit var root: File
    private val bytes=ByteArray(1024) { (it%251).toByte() }
    @Before fun setup() { root=Files.createTempDirectory("ocr-download-test").toFile() }
    @After fun cleanup() { root.deleteRecursively() }
    private fun spec()=ModelFile("model.onnx",bytes.size.toLong(),
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)},
        "https://example.invalid/model")
    private class Response(val code: Int,val data: ByteArray,val headers: Map<String,String> = emptyMap(),
        val reportLength: Long=data.size.toLong()) : HttpURLConnection(URL("https://example.invalid")) {
        var disconnected=false
        override fun connect() {}
        override fun disconnect() { disconnected=true }
        override fun usingProxy()=false
        override fun getResponseCode()=code
        override fun getInputStream(): InputStream=ByteArrayInputStream(data)
        override fun getHeaderField(name: String)=headers[name]
        override fun getContentLengthLong()=reportLength
    }
    @Test fun streamsAndVerifiesWholeFile() {
        val response=Response(200,bytes)
        val file=File(root,"model.part")
        ModelTransfer { response }.download(spec(),file)
        assertArrayEquals(bytes,file.readBytes()); assertTrue(response.disconnected)
    }
    @Test fun resumesOnlyValidatedRange() {
        val file=File(root,"model.part"); file.writeBytes(bytes.copyOfRange(0,400))
        val response=Response(206,bytes.copyOfRange(400,1024),mapOf("Content-Range" to "bytes 400-1023/1024"))
        ModelTransfer { response }.download(spec(),file)
        assertEquals("bytes=400-",response.getRequestProperty("Range"))
        assertArrayEquals(bytes,file.readBytes())
    }
    @Test fun ignoredRangeReplacesPartialRatherThanAppending() {
        val file=File(root,"model.part"); file.writeBytes(bytes.copyOfRange(0,400))
        ModelTransfer { Response(200,bytes) }.download(spec(),file)
        assertArrayEquals(bytes,file.readBytes())
    }
    @Test fun wrongRangeDoesNotModifyPartial() {
        val file=File(root,"model.part"); file.writeBytes(bytes.copyOfRange(0,400))
        val response=Response(206,bytes.copyOfRange(400,1024),mapOf("Content-Range" to "bytes 399-1023/1024"))
        assertThrows(IOException::class.java) { ModelTransfer { response }.download(spec(),file) }
        assertEquals(400,file.length())
    }
    @Test fun changedEtagCannotCombineArtifacts() {
        val file=File(root,"model.part"); file.writeBytes(bytes.copyOfRange(0,400))
        File(file.path+".etag").writeText("old")
        val response=Response(206,bytes.copyOfRange(400,1024),mapOf(
            "Content-Range" to "bytes 400-1023/1024","ETag" to "new"))
        assertThrows(IOException::class.java) { ModelTransfer { response }.download(spec(),file) }
        assertFalse(file.exists())
    }
    @Test fun truncatedConnectionRetainsPartialForRetry() {
        val file=File(root,"model.part")
        assertThrows(IOException::class.java) {
            ModelTransfer { Response(200,bytes.copyOfRange(0,400),reportLength=-1) }.download(spec(),file)
        }
        assertEquals(400,file.length())
    }
    @Test fun corruptCompleteFileIsRemoved() {
        val file=File(root,"model.part")
        assertThrows(IOException::class.java) {
            ModelTransfer { Response(200,ByteArray(1024)) }.download(spec(),file)
        }
        assertFalse(file.exists())
    }
    @Test fun cancellationPreventsTransfer() {
        assertThrows(CancellationException::class.java) {
            ModelTransfer { error("must not open") }.download(spec(),File(root,"model"),{true})
        }
    }
    @Test fun verifiedExistingFileNeedsNoNetwork() {
        val file=File(root,"model.part"); file.writeBytes(bytes)
        ModelTransfer { error("must not open") }.download(spec(),file)
    }
    @Test fun responseLargerThanManifestIsRejected() {
        val file=File(root,"model.part")
        assertThrows(IOException::class.java) {
            ModelTransfer { Response(200,bytes+byteArrayOf(0),reportLength=-1) }.download(spec(),file)
        }
        assertTrue(file.length()<=1024)
    }
    @Test fun failedHttpDoesNotLeaveInstalledArtifact() {
        val file=File(root,"model.part")
        assertThrows(IOException::class.java) { ModelTransfer { Response(503,byteArrayOf()) }.download(spec(),file) }
        assertFalse(file.exists())
    }
    @Test fun manifestRejectsUnsafeNamesAndInsecureUrls() {
        assertThrows(IllegalArgumentException::class.java) { spec().copy(name="../outside") }
        assertThrows(IllegalArgumentException::class.java) { spec().copy(url="http://example.invalid/model") }
    }
}
