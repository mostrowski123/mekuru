package moe.matthew.mekuru.ocr

import org.json.JSONObject
import org.json.JSONArray
import org.junit.*
import org.junit.Assert.*
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class OcrStoreTest {
    private lateinit var root: File
    private lateinit var cache: File
    private lateinit var store: OcrStore
    @Before fun setup() {
        root=Files.createTempDirectory("ocr-store-test").toFile()
        cache=File(root,"pages_cache.json")
        cache.writeText(JSONObject().put("title","Test").put("imageDirPath",root.path)
            .put("ocrCompleted",false).put("pages",JSONArray((0..3).map {
                JSONObject().put("pageIndex",it).put("imageFileName","page-"+it+".png")
                    .put("imgWidth",100).put("imgHeight",100).put("blocks",JSONArray())
            })).toString())
        store=OcrStore(File(root,"jobs"))
    }
    @After fun cleanup() { root.deleteRecursively() }
    private fun create(replace: Boolean=false,pages: List<Int> = listOf(0,1,2,3)) =
        store.create(JSONObject().put("bookId",1).put("title","Test")
            .put("cachePath",cache.path).put("pages",JSONArray(pages)).put("replace",replace),"model-v1")
    private fun start(job: JSONObject): String {
        val id=job.getString("id"); store.transition(id,"preparing"); store.transition(id,"running"); return id
    }
    @Test fun regionProgressResetsForEachPageAndStopsAfterCancellation() {
        val id=start(create())
        store.phase(id,"detecting",0)
        store.regions(id,0,5); store.regions(id,2,5)
        assertEquals(2,store.read(id).getInt("regionsDone"))
        store.phase(id,"detecting",1)
        assertFalse(store.read(id).has("regionsDone"))
        store.transition(id,"cancelling")
        store.regions(id,3,5)
        assertFalse(store.read(id).has("regionsDone"))
    }
    @Test fun emptyRecognizedPageIsDurablyComplete() {
        val id=start(create())
        store.commit(id,0,JSONArray(),"hash")
        val book=JSONObject(cache.readText())
        assertTrue(OcrStore.pageComplete(book,book.getJSONArray("pages").getJSONObject(0)))
        assertFalse(OcrStore.pageComplete(book,book.getJSONArray("pages").getJSONObject(1)))
        assertFalse(book.getBoolean("ocrCompleted"))
        assertEquals("manga-ocr-1",book.getJSONArray("pages").getJSONObject(0).getJSONObject("ocr").getString("engineVersion"))
    }
    @Test fun legacyMokuroEmptyPagesArePreservedAsComplete() {
        val book=JSONObject(cache.readText()).put("ocrCompleted",true).put("ocrSource","mokuro")
        cache.writeText(book.toString())
        create(true)
        assertTrue(JSONObject(cache.readText()).getJSONArray("pages").objects().all {
            it.getJSONObject("ocr").getBoolean("completed")
        })
    }
    @Test fun crashBetweenPageAndJournalIsReconciled() {
        val id=start(create())
        try { store.commit(id,0,JSONArray(),"hash") { throw Error("process died") } } catch(_: Error) {}
        assertFalse(store.read(id).getJSONObject("outcomes").has("0"))
        store=OcrStore(File(root,"jobs")); store.recover()
        val recovered=store.read(id)
        assertEquals("paused",recovered.getString("status"))
        assertEquals("done",recovered.getJSONObject("outcomes").getString("0"))
    }
    @Test fun duplicatePageCommitDoesNotIncreaseRevision() {
        val id=start(create())
        repeat(2) { store.commit(id,0,JSONArray(),"hash") }
        val page=JSONObject(cache.readText()).getJSONArray("pages").getJSONObject(0)
        assertEquals(1,page.getJSONObject("ocr").getInt("revision"))
    }
    @Test fun cancelledJobCannotPublishLateResult() {
        val id=start(create())
        store.transition(id,"cancelling")
        assertThrows(IllegalStateException::class.java) { store.commit(id,0,JSONArray(),"late") }
        assertFalse(JSONObject(cache.readText()).getJSONArray("pages").getJSONObject(0).has("ocr"))
    }
    @Test fun deletionCannotBeRecreatedByLateResult() {
        val id=start(create()); cache.delete()
        assertThrows(IllegalStateException::class.java) { store.commit(id,0,JSONArray(),"late") }
        assertFalse(cache.exists())
    }
    @Test fun changedBookGenerationRejectsResult() {
        val id=start(create())
        cache.writeText(JSONObject(cache.readText()).put("ocrGeneration","different").toString())
        assertThrows(IllegalStateException::class.java) { store.commit(id,0,JSONArray(),"late") }
    }
    @Test fun onlyOneBackendCanOwnBook() {
        create()
        assertThrows(IllegalArgumentException::class.java) { create() }
    }
    @Test fun invalidPageSelectionDoesNotCreateJob() {
        assertThrows(IllegalArgumentException::class.java) { create(pages=listOf(100)) }
        assertTrue(store.all().isEmpty())
    }
    @Test fun replacementResumeKeepsOriginalTargets() {
        cache.writeText(JSONObject(cache.readText()).put("ocrCompleted",true).toString())
        val job=create(true); val id=start(job)
        store.commit(id,0,JSONArray(),"new")
        store.transition(id,"paused")
        store.resume(id,false)
        val called=mutableListOf<Int>()
        OcrRunner(store,id).run { _,page,_,_ ->
            called.add(page.getInt("pageIndex")); OcrPageOutput(JSONArray(),"next")
        }
        assertEquals(listOf(1,2,3),called)
        assertEquals("completed",store.read(id).getString("status"))
    }
    @Test fun threeConsecutiveFailuresStopAndCanRetry() {
        val id=create().getString("id")
        var calls=0
        OcrRunner(store,id).run { _,_,_,_ -> calls++; throw IllegalStateException("unreadable") }
        assertEquals(3,calls); assertEquals("failed",store.read(id).getString("status"))
        store.resume(id,true)
        OcrRunner(store,id).run { _,_,_,_ -> OcrPageOutput(JSONArray(),"ok") }
        assertEquals(4,store.read(id).getJSONObject("outcomes").length())
        assertEquals("completed",store.read(id).getString("status"))
    }
    @Test fun isolatedFailureDoesNotPretendFullCoverage() {
        val id=create().getString("id")
        OcrRunner(store,id).run { _,page,_,_ ->
            if(page.getInt("pageIndex")==1) throw IllegalStateException("bad page")
            OcrPageOutput(JSONArray(),"ok")
        }
        assertEquals("completedWithErrors",store.read(id).getString("status"))
        assertFalse(JSONObject(cache.readText()).getBoolean("ocrCompleted"))
    }
    @Test fun resourcePauseKeepsPendingPage() {
        val id=create().getString("id")
        OcrRunner(store,id).run({ throw OcrPause("low_battery") }) { _,_,_,_ ->
            fail("must not infer"); OcrPageOutput(JSONArray(),"")
        }
        assertEquals("paused",store.read(id).getString("status"))
        assertEquals("low_battery",store.read(id).getString("reason"))
        assertEquals(0,store.read(id).getJSONObject("outcomes").length())
    }
    @Test fun cancellationBetweenRecognitionAndCommitKeepsPageUntouched() {
        val id=create().getString("id")
        val ready=CountDownLatch(1); val release=CountDownLatch(1)
        val thread=Thread {
            OcrRunner(store,id).run { _,_,_,_ ->
                ready.countDown(); release.await(5,TimeUnit.SECONDS)
                OcrPageOutput(JSONArray(),"late")
            }
        }
        thread.start()
        assertTrue(ready.await(5,TimeUnit.SECONDS))
        store.transition(id,"cancelling")
        release.countDown(); thread.join(5000)
        assertFalse(thread.isAlive)
        assertEquals("cancelled",store.read(id).getString("status"))
        assertEquals(0,store.read(id).getJSONObject("outcomes").length())
    }
    @Test fun staleSegmentationCannotOverwriteNewOcrButCropCanMerge() {
        val id=start(create())
        val before=JSONObject(cache.readText())
        val after=before.cloneJson()
        after.getJSONArray("pages").getJSONObject(0)
            .put("blocks",JSONArray(listOf("stale words"))).put("contentBounds",JSONArray(listOf(0,0,80,80)))
        store.commit(id,0,JSONArray(),"new")
        val merged=MangaCacheMerge.merge(JSONObject(cache.readText()),before,after)
        val page=merged.getJSONArray("pages").getJSONObject(0)
        assertEquals(0,page.getJSONArray("blocks").length())
        assertEquals(80,page.getJSONArray("contentBounds").getInt(2))
        assertEquals(id,page.getJSONObject("ocr").getString("jobId"))
    }
    @Test fun invalidTransitionCannotRestartCancelledJob() {
        val id=create().getString("id"); store.transition(id,"cancelled")
        assertThrows(IllegalStateException::class.java) { store.transition(id,"running") }
        assertThrows(IllegalArgumentException::class.java) { store.resume(id,false) }
    }
    @Test fun diskFullAfterPageCommitRemainsResumableWithoutDuplicateReplacement() {
        var full=false
        store=OcrStore(File(root,"jobs")) { f,text ->
            if(full) throw java.io.IOException("disk full") else OcrWrites.atomic(f,text)
        }
        val id=start(create(true))
        full=true
        assertThrows(java.io.IOException::class.java) { store.commit(id,0,JSONArray(),"saved") }
        store.pauseAfterFailure(id,"storage_error")
        assertEquals("paused",store.read(id).getString("status"))
        assertEquals("done",store.read(id).getJSONObject("outcomes").getString("0"))
        full=false
        store.resume(id,false)
        OcrRunner(store,id).run { _,_,_,_ -> OcrPageOutput(JSONArray(),"next") }
        val page=JSONObject(cache.readText()).getJSONArray("pages").getJSONObject(0)
        assertEquals(1,page.getJSONObject("ocr").getInt("revision"))
    }
    @Test fun derivedMergeCannotBypassCancelledRecognitionCommit() {
        val id=start(create())
        val before=JSONObject(cache.readText())
        val after=before.cloneJson()
        after.getJSONArray("pages").getJSONObject(0).put("blocks",
            JSONArray(listOf(JSONObject().put("lines",JSONArray(listOf("late OCR"))).put("words",JSONArray()))))
        store.transition(id,"cancelled")
        val merged=MangaCacheMerge.merge(JSONObject(cache.readText()),before,after)
        assertEquals(0,merged.getJSONArray("pages").getJSONObject(0).getJSONArray("blocks").length())
    }
    @Test fun jsonEquivalenceIgnoresKeyOrderAndNumericRepresentation() {
        assertTrue(jsonEquivalent(JSONObject("""{"a":1,"b":[2]}"""),JSONObject("""{"b":[2.0],"a":1.0}""")))
        assertFalse(jsonEquivalent(JSONObject("""{"a":1}"""),JSONObject("""{"a":2}""")))
    }
    @Test fun cancellingRemoteDoesNotCancelPausedLocalJob() {
        val local=create()
        store.transition(local.getString("id"),"paused")
        val remote=store.create(local.cloneJson(),"remote","remote")
        store.cancelBook(1,"remote")
        assertEquals("paused",store.read(local.getString("id")).getString("status"))
        assertEquals("cancelled",store.read(remote.getString("id")).getString("status"))
    }
}
