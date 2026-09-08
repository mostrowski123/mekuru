package moe.matthew.mekuru.backup

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class JobStoreTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private lateinit var root: File
    private lateinit var store: JobStore

    private fun setUp() {
        root = tmp.newFolder("support")
        store = JobStore.forRoot(root)
    }

    private val exportSpec = JobSpec(JobSpec.KIND_EXPORT, displayName = "a.zip", targetPath = "/x/a.zip", totalBytes = 500)

    @Test
    fun statusFollowsTheFilesOnDisk() {
        setUp()
        assertEquals(JobStore.STATUS_NONE, store.status(null)["status"])

        val live = JobStore.Live(JobSpec.KIND_EXPORT, JobControl.PHASE_WRITING, 10, 100)
        assertEquals(mapOf("status" to "running", "kind" to "export", "phase" to "writing", "done" to 10L, "total" to 100L), store.status(live))

        store.writeSpec(exportSpec)
        ZipJournal(store.journalFile).append(listOf(ZipJournal.ckptLine(90L, 1, 42L)))
        val paused = store.status(null)
        assertEquals(JobStore.STATUS_PAUSED, paused["status"])
        assertEquals(42L, paused["done"])
        assertEquals(500L, paused["total"])
        assertNull(paused["error"])

        store.writeLastError("IOException")
        assertEquals("IOException", store.status(null)["error"])

        store.markCancelled()
        assertEquals(JobStore.STATUS_CANCELLED, store.status(null)["status"])

        store.writeResult(JobStore.resultDone(JobSpec.KIND_EXPORT, mapOf("bytes" to 7L)))
        val result = store.status(null)
        assertEquals(JobStore.STATUS_DONE, result["status"])
        assertEquals(7, result["bytes"])

        store.clearJobFiles()
        assertTrue(store.resultFile.exists())
        assertFalse(store.specFile.exists())
        assertEquals(JobStore.STATUS_DONE, store.consumeResult()!!["status"])
        assertNull(store.readResult())

        store.extractedMarker.parentFile?.mkdirs()
        store.extractedMarker.writeText("{}")
        assertEquals(mapOf("status" to "done", "kind" to "restore"), store.status(null))
    }

    @Test
    fun recoveryDecisionTable() {
        setUp()
        assertEquals(JobStore.Recovery.Nothing, store.recoveryAction(running = true))
        assertEquals(JobStore.Recovery.Wipe, store.recoveryAction(running = false))

        store.writeSpec(exportSpec)
        assertEquals(JobStore.Recovery.Resume, store.recoveryAction(running = false))

        val journal = ZipJournal(store.journalFile)
        repeat(JobStore.MAX_RESUMES_WITHOUT_PROGRESS) { journal.append(listOf(ZipJournal.resumeLine())) }
        assertEquals(JobStore.Recovery.Cleanup(JobStore.REASON_CRASH_LOOP), store.recoveryAction(running = false))

        journal.append(listOf(ZipJournal.ckptLine(1L, 1, 1L)))
        assertEquals(JobStore.Recovery.Resume, store.recoveryAction(running = false))

        store.markCancelled()
        assertEquals(JobStore.Recovery.Cleanup(JobStore.REASON_CANCELLED), store.recoveryAction(running = false))
    }

    @Test
    fun stagingIsStaleOnlyWithoutMarkersOrAJob() {
        setUp()
        assertFalse(store.stagingIsStale())
        store.stagingDir.mkdirs()
        assertTrue(store.stagingIsStale())
        store.writeSpec(exportSpec)
        assertFalse(store.stagingIsStale())
        store.clearJobFiles()
        store.extractedMarker.writeText("{}")
        assertFalse(store.stagingIsStale())
    }

    @Test
    fun retireMovesADirectoryAsideAndSweepDeletesIt() {
        setUp()
        val staging = store.stagingDir
        File(staging, "books/x").mkdirs()
        File(staging, "books/x/a.txt").writeText("a")

        assertTrue(JobStore.retire(staging))
        assertFalse(staging.exists())
        val tombstones = root.listFiles()!!.filter { it.name.endsWith(JobStore.TOMBSTONE_SUFFIX) }
        assertEquals(1, tombstones.size)
        assertTrue(File(tombstones.single(), "books/x/a.txt").isFile)

        JobStore.sweepTombstones(root)
        assertTrue(root.listFiles()!!.none { it.name.endsWith(JobStore.TOMBSTONE_SUFFIX) })
        assertFalse(JobStore.retire(staging))
    }

    @Test
    fun specAndPlanRoundTrip() {
        setUp()
        val spec = JobSpec(
            kind = JobSpec.KIND_RESTORE,
            sourceUri = "file:///tmp/a.zip",
            stagingPath = "/data/restore_staging",
            totalBytes = 99,
            folders = mapOf("Books/メロス/" to "book_1_abcdef12"),
            manifestJson = "{\"format\":1}",
        )
        store.writeSpec(spec)
        assertEquals(spec, store.readSpec())

        JobTestSupport.writePlan(store, listOf(PlanEntry("/a/b", "Books/x/b", 5, 0)))
        assertEquals(listOf(PlanEntry("/a/b", "Books/x/b", 5, 0)), store.readPlan())
    }

    @Test
    fun jsonNullsAndMissingKeysReadAsAbsent() {
        val fromDart = JSONObject(mapOf("kind" to "export", "displayName" to "a.zip", "targetPath" to "/x/a.zip", "treeUri" to null, "totalBytes" to 5L))
        val spec = JobSpec.fromJson(fromDart)
        assertNull(spec.treeUri)
        assertNull(spec.docUri)
        assertEquals("/x/a.zip", spec.targetPath)
        assertNull(JobSpec.fromJson(JSONObject("{\"kind\":\"restore\",\"sourceUri\":null}")).sourceUri)
    }

    @Test
    fun plainMapConversionHandlesNesting() {
        val json = JSONObject("{\"a\":1,\"b\":{\"c\":[1,\"x\",null]},\"d\":null}")
        with(JobStore.Companion) {
            assertEquals(mapOf("a" to 1, "b" to mapOf("c" to listOf(1, "x", null)), "d" to null), json.toPlainMap())
        }
    }
}
