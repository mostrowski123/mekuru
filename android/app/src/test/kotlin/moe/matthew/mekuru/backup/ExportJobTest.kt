package moe.matthew.mekuru.backup

import java.io.File
import java.io.RandomAccessFile
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Every interruption the job can suffer must converge, on the next run, to
 * the same archive a one-shot export produces.
 */
class ExportJobTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private lateinit var sources: File
    private lateinit var support: File
    private lateinit var store: JobStore
    private lateinit var target: File
    private lateinit var plan: List<PlanEntry>
    private lateinit var spec: JobSpec

    @Before
    fun setUp() {
        sources = tmp.newFolder("sources")
        support = tmp.newFolder("support")
        store = JobStore.forRoot(support)
        target = File(tmp.newFolder("out"), "mekuru-full-backup.zip")
        plan = JobTestSupport.seedSources(sources)
        JobTestSupport.writePlan(store, plan)
        spec = JobTestSupport.exportSpec(target, plan)
    }

    private fun commit(io: JobIo = FileJobIo()): JobSpec {
        val created = io.createPartial(spec)
        store.writeSpec(created)
        return created
    }

    private fun run(
        io: JobIo = FileJobIo(),
        control: JobControl = JobControl(),
        checkpointBytes: Long = 1L,
    ): Map<String, Any?> = ExportJob(store, store.readSpec()!!, io, control, checkpointBytes = checkpointBytes).run()

    private fun expected(): Map<String, ByteArray> = plan.associate { it.name to File(it.path).readBytes() }

    private fun assertComplete(result: Map<String, Any?>) {
        assertEquals(JobStore.STATUS_DONE, result["status"])
        assertEquals(target.path, result["location"])
        assertEquals(plan.size, result["entries"])
        assertEquals(true, result["renamed"])
        val zip = JobTestSupport.readZip(target)
        assertEquals(plan.map { it.name }, zip.keys.toList())
        for ((name, bytes) in expected()) assertArrayEquals(name, bytes, zip[name])
        assertFalse(File(target.path + FileJobIo.PARTIAL_SUFFIX).exists())
        assertEquals(listOf("result.json"), store.dir.list()!!.toList())
    }

    private fun oneShotBytes(): ByteArray {
        val other = File(tmp.newFolder("oneshot"), "one.zip")
        val otherStore = JobStore(tmp.newFolder("store2"), tmp.newFolder("st2"))
        JobTestSupport.writePlan(otherStore, plan)
        val created = FileJobIo().createPartial(JobTestSupport.exportSpec(other, plan))
        otherStore.writeSpec(created)
        ExportJob(otherStore, created, FileJobIo(), JobControl(), checkpointBytes = Long.MAX_VALUE).run()
        return other.readBytes()
    }

    @Test
    fun writesACompleteArchiveAndItsResult() {
        commit()
        val result = run()
        assertComplete(result)
        assertEquals(target.length(), result["bytes"])
        assertEquals(0, result["skippedFiles"])
    }

    @Test
    fun abortThenResumeMatchesAOneShotExportByteForByte() {
        commit()
        val control = JobControl().apply { abortAfterBytes = 400 * 1024 }
        try {
            run(control = control)
            fail("expected the abort")
        } catch (_: AbortedForTestException) {
            // like a process death mid-entry
        }
        val partial = File(target.path + FileJobIo.PARTIAL_SUFFIX)
        assertTrue(partial.exists())
        assertTrue(store.specFile.exists())
        val state = ZipJournal(store.journalFile).parseExport()
        assertTrue("a checkpoint should exist", state.ckptOffset > 0)
        assertTrue(state.next in 1 until plan.size)

        val result = run()
        assertComplete(result)
        assertArrayEquals(oneShotBytes(), target.readBytes())
    }

    @Test
    fun aTornJournalBatchIsRedone() {
        commit()
        try {
            run(control = JobControl().apply { abortAfterBytes = 400 * 1024 })
            fail("expected the abort")
        } catch (_: AbortedForTestException) {
        }
        store.journalFile.appendText("{\"e\":9,\"n\":\"torn\",\"mt\":1,\"crc\":1,\"cs\":1")
        val result = run()
        assertComplete(result)
        assertArrayEquals(oneShotBytes(), target.readBytes())
    }

    @Test
    fun aPartialShorterThanTheCheckpointStartsOver() {
        commit()
        try {
            run(control = JobControl().apply { abortAfterBytes = 400 * 1024 })
            fail("expected the abort")
        } catch (_: AbortedForTestException) {
        }
        RandomAccessFile(File(target.path + FileJobIo.PARTIAL_SUFFIX), "rw").use { it.setLength(10) }
        val result = run()
        assertComplete(result)
        assertArrayEquals(oneShotBytes(), target.readBytes())
    }

    @Test
    fun aDeletedPartialIsRecreated() {
        commit()
        try {
            run(control = JobControl().apply { abortAfterBytes = 400 * 1024 })
            fail("expected the abort")
        } catch (_: AbortedForTestException) {
        }
        assertTrue(File(target.path + FileJobIo.PARTIAL_SUFFIX).delete())
        val result = run()
        assertComplete(result)
    }

    @Test
    fun aTargetThatCannotSeekStartsOverAndStillFinishes() {
        val io = FileJobIo(seekable = false)
        commit(io)
        try {
            run(io = io, control = JobControl().apply { abortAfterBytes = 400 * 1024 })
            fail("expected the abort")
        } catch (_: AbortedForTestException) {
        }
        val result = run(io = io)
        assertComplete(result)
        assertArrayEquals(oneShotBytes(), target.readBytes())
    }

    @Test
    fun aCrashAfterFinishingOnlyRenames() {
        commit()
        var renameCalls = 0
        val flakyRename = object : JobIo by FileJobIo() {
            override fun finalizePartial(spec: JobSpec): Finalized {
                if (renameCalls++ == 0) throw java.io.IOException("provider hiccup")
                return FileJobIo().finalizePartial(spec)
            }
        }
        try {
            run(io = flakyRename)
            fail("expected the rename failure")
        } catch (_: java.io.IOException) {
        }
        assertTrue(ZipJournal(store.journalFile).parseExport().finished)
        val partialBytes = File(target.path + FileJobIo.PARTIAL_SUFFIX).readBytes()

        val result = run(io = flakyRename)
        assertComplete(result)
        assertArrayEquals(partialBytes, target.readBytes())
        assertEquals(2, renameCalls)
    }

    @Test
    fun aCrashAfterTheRenameStillReportsSuccess() {
        commit()
        var calls = 0
        val crashAfterRename = object : JobIo by FileJobIo() {
            override fun finalizePartial(spec: JobSpec): Finalized {
                val finalized = FileJobIo().finalizePartial(spec)
                if (calls++ == 0) throw java.io.IOException("died after rename")
                return finalized
            }
        }
        try {
            run(io = crashAfterRename)
            fail("expected the crash")
        } catch (_: java.io.IOException) {
        }
        assertTrue(target.isFile)
        val result = run(io = crashAfterRename)
        assertComplete(result)
    }

    @Test
    fun aSourceFileThatVanishedIsSkippedNotFatal() {
        commit()
        assertTrue(File(plan[3].path).delete())
        val result = run()
        assertEquals(1, result["skippedFiles"])
        assertEquals(plan.size - 1, result["entries"])
        val zip = JobTestSupport.readZip(target)
        assertFalse(zip.containsKey(plan[3].name))
        assertArrayEquals(File(plan[4].path).readBytes(), zip[plan[4].name])
    }

    @Test
    fun cancelAndPauseSurfaceAsTheirExceptions() {
        commit()
        try {
            run(control = JobControl().apply { cancelled = true })
            fail("expected cancel")
        } catch (_: CancelledException) {
        }
        try {
            run(control = JobControl().apply { paused = true })
            fail("expected pause")
        } catch (_: PausedException) {
        }
        assertTrue(store.specFile.exists())
    }
}
