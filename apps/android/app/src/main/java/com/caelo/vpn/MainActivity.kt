package com.caelo.vpn

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import com.caelo.vpn.ui.CaeloApp
import com.caelo.vpn.ui.theme.CaeloTheme
import com.caelo.vpn.ui.theme.ThemeMode
import androidx.compose.runtime.*

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(0xFFD7E7E1.toInt(), 0xFFD7E7E1.toInt())
        )
        setContent {
            val prefs = remember { getSharedPreferences("caelo_prefs", MODE_PRIVATE) }
            var themeMode by remember {
                mutableStateOf(runCatching { ThemeMode.valueOf(prefs.getString("theme_mode", ThemeMode.System.name)!!) }.getOrDefault(ThemeMode.System))
            }
            val dark = when (themeMode) {
                ThemeMode.System -> androidx.compose.foundation.isSystemInDarkTheme()
                ThemeMode.Light -> false
                ThemeMode.Dark -> true
            }
            SideEffect {
                enableEdgeToEdge(
                    statusBarStyle = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                    else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
                    navigationBarStyle = if (dark) SystemBarStyle.dark(0xFF090B0E.toInt())
                    else SystemBarStyle.light(0xFFD7E7E1.toInt(), 0xFFD7E7E1.toInt())
                )
            }
            CaeloTheme(themeMode) {
                CaeloApp(themeMode) { selected ->
                    themeMode = selected
                    prefs.edit().putString("theme_mode", selected.name).apply()
                }
            }
        }
    }
}
