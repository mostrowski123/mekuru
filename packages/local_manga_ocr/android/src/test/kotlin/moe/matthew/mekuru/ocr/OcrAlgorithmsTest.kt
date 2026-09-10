package moe.matthew.mekuru.ocr

import org.junit.Assert.*
import org.junit.Test

class OcrAlgorithmsTest {
    @Test fun unchangedLinesRetainBoundaries() {
        assertEquals(listOf("今日は","晴れです"),LineAlignment.align("今日は晴れです",listOf("今日は","晴れです")))
    }
    @Test fun correctionInsideLinePreservesBoundaries() {
        assertEquals(listOf("今日は","晴れです"),LineAlignment.align("今日は晴れです",listOf("令日は","晴れです")))
    }
    @Test fun insertionAtBoundaryIsAmbiguous() {
        assertNull(LineAlignment.align("abcdXefgh",listOf("abcd","efgh")))
    }
    @Test fun repeatedCharactersDoNotInventBoundary() {
        assertNull(LineAlignment.align("あああああ",listOf("ああ","ああ")))
    }
    @Test fun disagreementAboveThresholdFallsBack() {
        assertNull(LineAlignment.align("月曜日です",listOf("火星","大好き")))
    }
    @Test fun emptyAnchorsAndTextFallBack() {
        assertNull(LineAlignment.align("abc",listOf("","abc")))
        assertNull(LineAlignment.align("",listOf("abc","def")))
        assertNull(LineAlignment.align("abc",emptyList()))
    }
    @Test fun supplementaryKanjiAreNotSplit() {
        assertEquals(listOf("𠮷野家","です"),LineAlignment.align("𠮷野家です",listOf("𠮷野家","です")))
    }
    @Test fun greedyStepNeverRepeatsATrigram() {
        // Sequence 2,5,6,5,6: completing "5,6" with 5 again would repeat the trigram 5,6,5.
        assertEquals(7,MangaOcrDecode.next(floatArrayOf(0f,0f,0f,0f,0f,9f,1f,8f),listOf(2,5,6,5,6)))
        assertEquals(5,MangaOcrDecode.next(floatArrayOf(0f,0f,0f,0f,0f,9f,1f,8f),listOf(2,5,6)))
    }
    @Test fun argmaxTiesUseFirstId() {
        assertEquals(0,MangaOcrDecode.next(floatArrayOf(1f,1f),emptyList()))
    }
    @Test fun postProcessMatchesMangaOcr() {
        assertEquals("こんにちは",MangaOcrDecode.postProcess("こん にち\nは"))
        // Vectors checked against manga_ocr.ocr.post_process 0.1.16.
        assertEquals("え．．．",MangaOcrDecode.postProcess("え…"))
        assertEquals("あ．．．．",MangaOcrDecode.postProcess("あ・・・・"))
        assertEquals("ＡＢＣ１２３！？",MangaOcrDecode.postProcess("ABC123!?"))
        assertEquals("ｘ－ｙ＿ｚ～",MangaOcrDecode.postProcess("x-y_z~"))
        assertEquals("ガギパ。ー",MangaOcrDecode.postProcess("ｶﾞｷﾞﾊﾟ｡ｰ"))
        assertEquals("ヲﾞ",MangaOcrDecode.postProcess("ｦﾞ"))
        assertEquals("ﾞ",MangaOcrDecode.postProcess("ﾞ"))
        assertEquals("漢字ひらがな",MangaOcrDecode.postProcess("漢字ひらがな"))
    }
    @Test fun grayscaleMatchesPillowLuma() {
        assertEquals(0x4c4c4c,OcrPixels.grayscale(intArrayOf(0xff0000))[0])
        assertEquals(0xffffff,OcrPixels.grayscale(intArrayOf(0xffffff))[0])
        assertEquals(0x000000,OcrPixels.grayscale(intArrayOf(0x000000))[0])
    }
    @Test fun resizePreservesConstantRgbAcrossUpsamplingAndDownsampling() {
        for((w,h) in listOf(1 to 1,17 to 31,640 to 310)) {
            val rgb=OcrPixels.resizeRgb(IntArray(w*h){0x1234ab},w,h)
            assertTrue(rgb.all { it==0x1234ab })
        }
    }
    @Test fun normalizationIsRgbChannelFirst() {
        val result=OcrPixels.normalize(intArrayOf(0xff0000,0x00ff00),.5f,.5f)
        assertEquals(1f,result[0],.00001f)
        assertEquals(-1f,result[1],.00001f)
        assertEquals(-1f,result[2],.00001f)
        assertEquals(1f,result[3],.00001f)
    }
    @Test fun preprocessingMatchesIndependentPillowGoldenDigests() {
        val text=javaClass.getResource("/pillow_bicubic_vectors.json")!!.readText()
        for(row in org.json.JSONArray(text).objects()) {
            val w=row.getInt("width"); val h=row.getInt("height")
            val source=IntArray(w*h) {
                val x=it%w; val y=it/w
                (((x*13+y*7)%256) shl 16) or (((x*3+y*29)%256) shl 8) or ((x*47+y*11)%256)
            }
            val rgb=OcrPixels.resizeRgb(source,w,h)
            val bytes=ByteArray(rgb.size*3) {
                ((rgb[it/3] ushr (16-(it%3)*8)) and 255).toByte()
            }
            val digest=java.security.MessageDigest.getInstance("SHA-256")
                .digest(bytes).joinToString(""){"%02x".format(it)}
            assertEquals("Pillow RGB bicubic "+w+"x"+h,row.getString("sha256"),digest)
        }
    }
    @Test fun verticalLinesReadRightToLeft() {
        val block=DetectedBlock(Box(0.0,0.0,100.0,100.0),true,
            mutableListOf(Box(10.0,10.0,20.0,90.0).quad(),Box(50.0,10.0,60.0,90.0).quad()))
        ComicGeometry.examine(block,100)
        assertTrue(block.vertical)
        assertEquals(50.0,block.lines.first().first().x,.001)
    }
    @Test fun horizontalLinesReadTopToBottom() {
        val block=DetectedBlock(Box(0.0,0.0,100.0,100.0),true,
            mutableListOf(Box(10.0,50.0,90.0,60.0).quad(),Box(10.0,10.0,90.0,20.0).quad()))
        ComicGeometry.examine(block,100)
        assertFalse(block.vertical)
        assertEquals(10.0,block.lines.first().first().y,.001)
    }
    @Test fun boxesWithoutTextMaskAreRejected() {
        assertTrue(ComicGeometry.group(listOf(DetectedBlock(Box(0.0,0.0,100.0,100.0))),
            emptyList(),100,100,{0.0}).isEmpty())
    }
    @Test fun scatteredTextSurvivesWithoutBlockDetection() {
        val result=ComicGeometry.group(emptyList(),listOf(Box(10.0,10.0,20.0,90.0).quad()),
            100,100,{1.0})
        assertEquals(1,result.size); assertEquals(1,result.single().lines.size)
    }
}
