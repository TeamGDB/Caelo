package com.caelo.vpn.ui

internal const val BUILT_IN_ADMIN_LOGIN = "admin"
internal const val BUILT_IN_ADMIN_PASSWORD = "admin"
internal const val ADMIN_INVITE_CODE = "ADMIN-777"
internal const val USER_INVITE_CODE = "USER-1234"

internal enum class AuthFailure {
    EmptyFields,
    PasswordMismatch,
    InvalidInvitation,
    InvalidCredentials
}

internal sealed interface LoginResult {
    data class Success(val role: String, val builtInAccount: Boolean = false) : LoginResult
    data class Failure(val reason: AuthFailure) : LoginResult
}

internal sealed interface RegistrationResult {
    data class Success(val login: String, val password: String, val role: String) : RegistrationResult
    data class Failure(val reason: AuthFailure) : RegistrationResult
}

internal fun authenticateAccount(
    login: String,
    password: String,
    savedLogin: String?,
    savedPassword: String?,
    savedRole: String?
): LoginResult = when {
    login == BUILT_IN_ADMIN_LOGIN && password == BUILT_IN_ADMIN_PASSWORD ->
        LoginResult.Success(role = "admin", builtInAccount = true)
    savedLogin != null && login == savedLogin && password == savedPassword ->
        LoginResult.Success(role = savedRole ?: "user")
    else -> LoginResult.Failure(AuthFailure.InvalidCredentials)
}

internal fun validateRegistration(
    login: String,
    password: String,
    repeatedPassword: String,
    invitationCode: String
): RegistrationResult {
    if (login.isBlank() || password.isBlank() || repeatedPassword.isBlank()) {
        return RegistrationResult.Failure(AuthFailure.EmptyFields)
    }
    if (password != repeatedPassword) {
        return RegistrationResult.Failure(AuthFailure.PasswordMismatch)
    }
    val normalizedCode = invitationCode.trim().uppercase()
    val role = when (normalizedCode) {
        ADMIN_INVITE_CODE -> "admin"
        USER_INVITE_CODE -> "user"
        else -> return RegistrationResult.Failure(AuthFailure.InvalidInvitation)
    }
    return RegistrationResult.Success(login.trim(), password, role)
}

internal fun validatePasswordChange(password: String, repeatedPassword: String): AuthFailure? = when {
    password.isBlank() || repeatedPassword.isBlank() -> AuthFailure.EmptyFields
    password != repeatedPassword -> AuthFailure.PasswordMismatch
    else -> null
}

internal fun sortServers(
    servers: List<Server>,
    latencies: Map<String, Int?>
): List<Server> = servers.sortedWith(
    compareBy<Server> { it.badge.ordinal }
        .thenBy { latencies[it.name] ?: Int.MAX_VALUE }
        .thenBy { it.name }
)

internal fun isCaeloAccountLink(value: String): Boolean =
    value.startsWith("caelo://account/link/")

internal data class ScrollbarMetrics(val thumbFraction: Float, val progress: Float)

internal fun calculateScrollbarMetrics(
    itemCount: Int,
    itemSizePx: Float,
    spacingPx: Float,
    viewportHeightPx: Float,
    firstVisibleItemIndex: Int,
    firstVisibleItemScrollOffsetPx: Int
): ScrollbarMetrics {
    if (itemCount <= 0 || itemSizePx <= 0f || viewportHeightPx <= 0f) {
        return ScrollbarMetrics(thumbFraction = 1f, progress = 0f)
    }
    val contentHeightPx = itemSizePx * itemCount + spacingPx.coerceAtLeast(0f) * (itemCount - 1)
    val maxScrollPx = (contentHeightPx - viewportHeightPx).coerceAtLeast(0f)
    val itemExtentPx = itemSizePx + spacingPx.coerceAtLeast(0f)
    val scrollPx = firstVisibleItemIndex.coerceAtLeast(0) * itemExtentPx +
        firstVisibleItemScrollOffsetPx.coerceAtLeast(0)
    return ScrollbarMetrics(
        thumbFraction = (viewportHeightPx / contentHeightPx).coerceIn(.12f, 1f),
        progress = if (maxScrollPx == 0f) 0f else (scrollPx / maxScrollPx).coerceIn(0f, 1f)
    )
}
