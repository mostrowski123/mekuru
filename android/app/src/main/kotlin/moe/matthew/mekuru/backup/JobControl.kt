package moe.matthew.mekuru.backup

/** The user cancelled; the caller deletes whatever the job produced. */
class CancelledException : Exception("Job cancelled")

/** The job must stop now but keep its files; it resumes on the next launch. */
class PausedException : Exception("Job paused")

/** Test seam: behaves like a process death mid-entry (no cleanup). */
class AbortedForTestException : Exception("Job aborted for test")

/** A failure with a stable code for the UI; the job dir is cleaned up. */
class JobFailedException(val code: String) : Exception(code)

/**
 * Shared, thread-safe view of a running job: the service reads it for the
 * notification and the method channel, the job writes it and consults the
 * flags at every buffer through [gate].
 */
class JobControl {
    @Volatile var cancelled = false
    @Volatile var paused = false

    /** Test seam: throw [AbortedForTestException] once [done] reaches this. */
    @Volatile var abortAfterBytes = -1L

    @Volatile var phase = PHASE_PREPARING
    @Volatile var done = 0L
    @Volatile var total = 0L

    /**
     * Held while a restore writes its EXTRACTED marker and while cancel
     * decides whether it is still allowed, so the two can never interleave.
     */
    val commitLock = Any()

    fun gate() {
        if (cancelled) throw CancelledException()
        if (paused) throw PausedException()
        val abortAt = abortAfterBytes
        if (abortAt >= 0 && done >= abortAt) throw AbortedForTestException()
    }

    companion object {
        const val PHASE_PREPARING = "preparing"
        const val PHASE_WRITING = "writing"
        const val PHASE_CHECKING = "checking"
        const val PHASE_EXTRACTING = "extracting"
        const val PHASE_FINISHING = "finishing"
    }
}
