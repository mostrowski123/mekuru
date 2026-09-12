package moe.matthew.mekuru.ocr

import org.junit.Assert.*
import org.junit.Test

class OcrRuntimeTest {
    @Test fun speedTestHoldsTheModelLease() {
        assertFalse(OcrRuntime.hasModelLease())
        OcrRuntime.benchmarking=true
        try { assertTrue(OcrRuntime.hasModelLease()) } finally { OcrRuntime.benchmarking=false }
        assertFalse(OcrRuntime.hasModelLease())
    }
}
