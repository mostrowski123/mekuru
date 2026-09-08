package moe.matthew.mekuru

import android.content.Context
import moe.matthew.mekuru.backup.FullBackupJobRunner
import moe.matthew.mekuru.backup.JobStore

/**
 * The one place that decides what to do with a job the process did not
 * finish: resume it, finish a cancel, fail a crash loop, or wipe leftovers.
 * Runs on every activity resume (cheap when there is nothing to do) and is
 * safe to run concurrently with the Dart boot hook: that hook acts only on
 * a staging dir carrying EXTRACTED or READY, which is never retired here.
 */
object FullBackupRecovery {
    fun run(context: Context) {
        val appContext = context.applicationContext
        Thread({
            val store = FullBackupJobService.storeFor(appContext)
            if (!FullBackupJobService.isRunning) {
                val runner = FullBackupJobRunner(store, SafJobIo(appContext.contentResolver))
                if (runner.recover() == JobStore.Recovery.Resume) FullBackupJobService.start(appContext)
            }
            JobStore.sweepTombstones(appContext.filesDir)
        }, "mekuru-full-backup-recovery").start()
    }
}
