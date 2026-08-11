package com.caelo.vpn.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ServerLogicTest {
    @Test
    fun `servers are sorted by badge priority then latency`() {
        val stableFast = server("Stable fast", ServerBadge.Stable)
        val mainSlow = server("Main slow", ServerBadge.Main)
        val mainFast = server("Main fast", ServerBadge.Main)
        val testing = server("Testing", ServerBadge.Testing)

        val sorted = sortServers(
            listOf(stableFast, mainSlow, testing, mainFast),
            mapOf("Stable fast" to 10, "Main slow" to 90, "Main fast" to 20, "Testing" to 1)
        )

        assertEquals(listOf(mainFast, mainSlow, stableFast, testing), sorted)
    }

    @Test
    fun `unreachable server is placed after reachable peers with same badge`() {
        val unreachable = server("A unreachable", ServerBadge.Stable)
        val reachable = server("Z reachable", ServerBadge.Stable)

        val sorted = sortServers(listOf(unreachable, reachable), mapOf(unreachable.name to null, reachable.name to 150))

        assertEquals(listOf(reachable, unreachable), sorted)
    }

    @Test
    fun `name provides deterministic order for equal badge and latency`() {
        val beta = server("Beta", ServerBadge.Main)
        val alpha = server("Alpha", ServerBadge.Main)

        assertEquals(listOf(alpha, beta), sortServers(listOf(beta, alpha), mapOf("Beta" to 20, "Alpha" to 20)))
    }

    private fun server(name: String, badge: ServerBadge) =
        Server(name, "description", "FI", 20, badge)
}
