package com.caelo.vpn.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

enum class ThemeMode { System, Light, Dark }

val Ink: Color @Composable get() = MaterialTheme.colorScheme.onBackground
val Panel: Color @Composable get() = MaterialTheme.colorScheme.surface
val Mist: Color @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
val Ice: Color @Composable get() = MaterialTheme.colorScheme.onBackground
val Cyan: Color @Composable get() = MaterialTheme.colorScheme.primary
val Mint: Color @Composable get() = MaterialTheme.colorScheme.secondary
val Cloud: Color @Composable get() = MaterialTheme.colorScheme.background
val Violet: Color @Composable get() = MaterialTheme.colorScheme.tertiary

private val typography = Typography(
    headlineLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 30.sp,
        lineHeight = 36.sp,
        letterSpacing = (-0.4).sp
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 21.sp,
        lineHeight = 28.sp,
        letterSpacing = 0.sp
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 17.sp,
        lineHeight = 25.sp
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 22.sp
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 20.sp
    )
)

private val lightColors = lightColorScheme(
    primary = Color(0xFF3697B8),
    secondary = Color(0xFF2FA982),
    tertiary = Color(0xFF6652C9),
    background = Color(0xFFD7E7E1),
    surface = Color(0xFFF7F8F6),
    surfaceVariant = Color(0xFFE3EFEB),
    onPrimary = Color.White,
    onBackground = Color(0xFF0A3735),
    onSurface = Color(0xFF0A3735),
    onSurfaceVariant = Color(0xFF496964)
)

private val darkColors = darkColorScheme(
    primary = Color(0xFF72B9D6),
    secondary = Color(0xFF54C69A),
    tertiary = Color(0xFFA99DEB),
    background = Color(0xFF090B0E),
    surface = Color(0xFF13161B),
    surfaceVariant = Color(0xFF1C2026),
    onPrimary = Color(0xFF071C24),
    onBackground = Color(0xFFF0F2F4),
    onSurface = Color(0xFFF0F2F4),
    onSurfaceVariant = Color(0xFFAEB4BD),
    outline = Color(0xFF3D434D),
    error = Color(0xFFFFB4AB)
)

@Composable
fun CaeloTheme(mode: ThemeMode = ThemeMode.System, content: @Composable () -> Unit) {
    val dark = when (mode) {
        ThemeMode.System -> androidx.compose.foundation.isSystemInDarkTheme()
        ThemeMode.Light -> false
        ThemeMode.Dark -> true
    }
    MaterialTheme(colorScheme = if (dark) darkColors else lightColors, typography = typography, content = content)
}
