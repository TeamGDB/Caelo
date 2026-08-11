package com.caelo.vpn.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthLogicTest {
    @Test
    fun `built-in admin credentials grant admin role`() {
        val result = authenticateAccount("admin", "admin", null, null, null)

        assertEquals(LoginResult.Success("admin", builtInAccount = true), result)
    }

    @Test
    fun `saved credentials preserve saved role`() {
        val result = authenticateAccount("alice", "secret", "alice", "secret", "user")

        assertEquals(LoginResult.Success("user"), result)
    }

    @Test
    fun `wrong credentials are rejected`() {
        val result = authenticateAccount("alice", "wrong", "alice", "secret", "admin")

        assertEquals(LoginResult.Failure(AuthFailure.InvalidCredentials), result)
    }

    @Test
    fun `registration trims login and normalizes admin invitation`() {
        val result = validateRegistration("  alice  ", "pw", "pw", " admin-777 ")

        assertEquals(RegistrationResult.Success("alice", "pw", "admin"), result)
    }

    @Test
    fun `user invitation creates user role`() {
        val result = validateRegistration("alice", "pw", "pw", "USER-1234")

        assertEquals(RegistrationResult.Success("alice", "pw", "user"), result)
    }

    @Test
    fun `registration requires all account fields`() {
        val result = validateRegistration("", "pw", "pw", USER_INVITE_CODE)

        assertEquals(RegistrationResult.Failure(AuthFailure.EmptyFields), result)
    }

    @Test
    fun `registration rejects mismatched passwords before invitation`() {
        val result = validateRegistration("alice", "one", "two", "bad-code")

        assertEquals(RegistrationResult.Failure(AuthFailure.PasswordMismatch), result)
    }

    @Test
    fun `registration rejects unknown invitation`() {
        val result = validateRegistration("alice", "pw", "pw", "unknown")

        assertEquals(RegistrationResult.Failure(AuthFailure.InvalidInvitation), result)
    }

    @Test
    fun `password change validation is stable`() {
        assertEquals(AuthFailure.EmptyFields, validatePasswordChange("", ""))
        assertEquals(AuthFailure.PasswordMismatch, validatePasswordChange("one", "two"))
        assertEquals(null, validatePasswordChange("same", "same"))
    }

    @Test
    fun `only account-link QR values are accepted`() {
        assertTrue(isCaeloAccountLink("caelo://account/link/token-1"))
        assertFalse(isCaeloAccountLink("https://example.com"))
        assertFalse(isCaeloAccountLink("caelo://server/link/token-1"))
    }
}
