package moe.matthew.mekuru.backup

import java.io.File
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** What happens to the files after each way a job can end. */
class FullBackupJobRunnerTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private lateinit var support: File
    private lateinit var store: JobStore
    private lateinit var target: File
    private lateinit var plan: List<PlanEntry>

    @Before
    fun setUp() {
        support = tmp.newFolder("support")
        store = JobStore.forRoot(support)
        target = File(tmp.newFolder("out"), "a.zip")
        plan = JobTestSupport.seedSources(tmp.newFolder("sources"))
        JobTestSupport.writePlan(store, plan)
    }

    private fun committedExport(io: JobIo = FileJobIo()): JobSpec {
        val spec = io.createPartial(JobTestSupport.exportSpec(target, plan))
        store.writeSpec(spec)
        return spec
    }

    @Test
    fun doneWritesTheResultAndClearsTheJob() {
        val spec = committedExport()
        val outcome = FullBackupJobRunner(store, FileJobIo()).run(spec)
        assertEquals(FullBackupJobRunner.Outcome.Done, outcome)
        assertEquals(JobStore.STATUS_DONE, store.readResult()!!["status"])
        assertFalse(store.specFile.exists())
        assertTrue(target.isFile)
    }

    @Test
    fun cancelDeletesThePartialAndReportsCancelled() {
        val spec = committedExport()
        val runner = FullBackupJobRunner(store, FileJobIo())
        assertTrue(runner.requestCancel())
        assertEquals(FullBackupJobRunner.Outcome.Cancelled, runner.run(spec))
        assertFalse(File(target.path + FileJobIo.PARTIAL_SUFFIX).exists())
        assertFalse(target.exists())
        assertEquals(JobStore.STATUS_CANCELLED, store.readResult()!!["status"])
        assertEquals(listOf("result.json"), store.dir.list()!!.toList())
    }

    @Test
    fun aDefinitiveFailureCleansUpAndReportsTheCode() {
        val staging = store.stagingDir.apply { mkdirs() }
        File(staging, "half.bin").writeText("x")
        val spec = JobSpec(
            kind = JobSpec.KIND_RESTORE,
            sourceUri = File(tmp.root, "gone.zip").toURI().toString(),
            stagingPath = staging.path,
        )
        store.writeSpec(spec)

        val outcome = FullBackupJobRunner(store, FileJobIo()).run(spec)
        assertEquals(FullBackupJobRunner.Outcome.Failed("source_missing"), outcome)
        assertFalse(staging.exists())
        assertEquals("source_missing", store.readResult()!!["error"])
        assertFalse(store.specFile.exists())
    }

    @Test
    fun aTransientFailureLeavesTheJobPausedWithItsReason() {
        val spec = committedExport()
        val brokenIo = object : JobIo by FileJobIo() {
            override fun openSink(spec: JobSpec): Sink? = throw IOException("disk went away")
        }
        assertEquals(FullBackupJobRunner.Outcome.Paused, FullBackupJobRunner(store, brokenIo).run(spec))
        assertTrue(store.specFile.exists())
        assertNull(store.readResult())
        val status = store.status(null)
        assertEquals(JobStore.STATUS_PAUSED, status["status"])
        assertEquals("IOException", status["error"])
    }

    @Test
    fun cancelIsRefusedOnceARestoreHasCommitted() {
        store.stagingDir.mkdirs()
        store.extractedMarker.writeText("{}")
        val runner = FullBackupJobRunner(store, FileJobIo())
        assertFalse(runner.requestCancel())
        assertFalse(store.isCancelled())
    }

    @Test
    fun recoverFinishesACancelThatDiedMidCleanup() {
        val spec = committedExport()
        store.markCancelled()
        val runner = FullBackupJobRunner(store, FileJobIo())
        assertEquals(JobStore.Recovery.Cleanup(JobStore.REASON_CANCELLED), runner.recover())
        assertFalse(File(target.path + FileJobIo.PARTIAL_SUFFIX).exists())
        assertEquals(JobStore.STATUS_CANCELLED, store.readResult()!!["status"])
        assertEquals(spec.kind, store.readResult()!!["kind"])
    }

    @Test
    fun recoverFailsACrashLoop() {
        committedExport()
        val journal = ZipJournal(store.journalFile)
        repeat(JobStore.MAX_RESUMES_WITHOUT_PROGRESS) { journal.append(listOf(ZipJournal.resumeLine())) }
        val runner = FullBackupJobRunner(store, FileJobIo())
        assertEquals(JobStore.Recovery.Cleanup(JobStore.REASON_CRASH_LOOP), runner.recover())
        assertEquals(JobStore.REASON_CRASH_LOOP, store.readResult()!!["error"])
        assertFalse(store.specFile.exists())
    }

    @Test
    fun recoverRecordsAResumeAndLeavesTheJobToTheService() {
        committedExport()
        val runner = FullBackupJobRunner(store, FileJobIo())
        assertEquals(JobStore.Recovery.Resume, runner.recover())
        assertEquals(1, ZipJournal(store.journalFile).resumesSinceCheckpoint())
        assertTrue(store.specFile.exists())
    }

    @Test
    fun recoverWipesLeftoversButNeverAMarkedStaging() {
        File(store.dir, "mekuru_db.sqlite").apply { parentFile?.mkdirs() }.writeText("snapshot")
        store.writeResult(JobStore.resultDone(JobSpec.KIND_EXPORT))
        store.stagingDir.mkdirs()
        File(store.stagingDir, "half.bin").writeText("x")

        assertEquals(JobStore.Recovery.Wipe, FullBackupJobRunner(store, FileJobIo()).recover())
        assertEquals(listOf("result.json"), store.dir.list()!!.toList())
        assertFalse(store.stagingDir.exists())

        store.stagingDir.mkdirs()
        store.extractedMarker.writeText("{}")
        assertEquals(JobStore.Recovery.Wipe, FullBackupJobRunner(store, FileJobIo()).recover())
        assertTrue(store.extractedMarker.exists())
    }
}
