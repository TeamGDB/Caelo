package com.caelo.vpn.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ScrollbarLogicTest {
    @Test
    fun `empty list fills track and starts at top`() {
        val metrics = calculateScrollbarMetrics(0, 50f, 5f, 200f, 0, 0)

        assertEquals(1f, metrics.thumbFraction, 0.0001f)
        assertEquals(0f, metrics.progress, 0.0001f)
    }

    @Test
    fun `thumb is proportional to viewport`() {
        val metrics = calculateScrollbarMetrics(10, 50f, 0f, 200f, 0, 0)

        assertEquals(.4f, metrics.thumbFraction, 0.0001f)
    }

    @Test
    fun `progress accounts for partial item offset`() {
        val metrics = calculateScrollbarMetrics(10, 50f, 0f, 200f, 2, 25)

        assertEquals(125f / 300f, metrics.progress, 0.0001f)
    }

    @Test
    fun `progress is clamped at list end`() {
        val metrics = calculateScrollbarMetrics(5, 50f, 5f, 100f, 99, 99)

        assertEquals(1f, metrics.progress, 0.0001f)
    }
}
