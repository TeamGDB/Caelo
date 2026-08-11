package com.caelo.vpn.ui

import android.content.Intent
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideOutHorizontally
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.caelo.vpn.ui.theme.*
import com.caelo.vpn.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

internal enum class UserRole { User, Admin }
internal data class UserAccount(
    val name: String,
    val role: UserRole,
    val serverNames: Set<String>,
    val inviteCode: String = "CAELO-${UUID.randomUUID().toString().take(6).uppercase()}",
    val createdAt: Long = System.currentTimeMillis(),
    val lastConnectedAt: Long? = null,
    val recoveryCode: String? = null,
    val pendingInvitation: Boolean = false
)

private enum class UserSort { Newest, Oldest, NameAsc, NameDesc, RecentActivity, MostServers }

@Composable
internal fun SettingsScreen(
    onBack: () -> Unit,
    isAdmin: Boolean,
    onOpenAbout: () -> Unit,
    onOpenAdmin: () -> Unit,
    onConnectDevice: () -> Unit,
    onOpenDevices: () -> Unit,
    themeMode: ThemeMode,
    onThemeChange: (ThemeMode) -> Unit,
    language: AppLanguage,
    onLanguageChange: (AppLanguage) -> Unit,
    onLogout: () -> Unit
) {
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("caelo_prefs", android.content.Context.MODE_PRIVATE) }
    val username = remember(language) { prefs.getString("account_login", null)?.takeIf { it.isNotBlank() } ?: l("Пользователь", "User") }
    var passkeyEnabled by remember { mutableStateOf(prefs.getBoolean("biometric_enabled", false)) }
    var showPasswordDialog by remember { mutableStateOf(false) }
    var showDeletePasskeyDialog by remember { mutableStateOf(false) }
    var showThemeDialog by remember { mutableStateOf(false) }
    var showLanguageDialog by remember { mutableStateOf(false) }
    var accountMessage by remember { mutableStateOf<String?>(null) }

    fun addPasskey() {
        val activity = context as? FragmentActivity
        val available = BiometricManager.from(context).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
            BiometricManager.BIOMETRIC_SUCCESS
        if (activity == null || !available) {
            accountMessage = l("Сначала настройте отпечаток или распознавание лица на телефоне", "First set up fingerprint or face recognition on your phone")
            return
        }
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(context),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    prefs.edit().putBoolean("biometric_enabled", true).apply()
                    passkeyEnabled = true
                    accountMessage = l("Passkey добавлен", "Passkey added")
                }
                override fun onAuthenticationFailed() { accountMessage = l("Не удалось подтвердить личность", "Unable to verify your identity") }
            }
        )
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle(l("Добавление Passkey", "Add Passkey"))
                .setSubtitle(l("Подтвердите личность", "Verify your identity"))
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
                .setNegativeButtonText(l("Отмена", "Cancel"))
                .build()
        )
    }

    fun openBiometricSettings() {
        val intent = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> Intent(Settings.ACTION_BIOMETRIC_ENROLL).apply {
                putExtra(
                    Settings.EXTRA_BIOMETRIC_AUTHENTICATORS_ALLOWED,
                    BiometricManager.Authenticators.BIOMETRIC_WEAK
                )
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P -> Intent(Settings.ACTION_FINGERPRINT_ENROLL)
            else -> Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        runCatching { context.startActivity(intent) }
            .onFailure { context.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS)) }
    }

    Column(Modifier.fillMaxSize().background(Cloud).statusBarsPadding().navigationBarsPadding()) {
        ScreenHeader(l("Настройки", "Settings"), onBack)
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(Panel).padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier.size(54.dp).clip(CircleShape)
                        .background(if (isAdmin) Violet.copy(alpha = .15f) else Mint.copy(alpha = .18f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        if (isAdmin) Icons.Outlined.AdminPanelSettings else Icons.Outlined.Person,
                        null,
                        tint = if (isAdmin) Violet else Mint,
                        modifier = Modifier.size(29.dp)
                    )
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        if (isAdmin) l("Администратор", "Administrator") else l("Пользователь", "User"),
                        color = Mist,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                    Text(username, color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                }
                Spacer(Modifier.width(10.dp))
                OutlinedButton(
                    onClick = onLogout,
                    modifier = Modifier.height(48.dp),
                    shape = RoundedCornerShape(14.dp),
                    contentPadding = PaddingValues(horizontal = 14.dp),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.error.copy(alpha = .55f))
                ) {
                    Icon(Icons.Outlined.Logout, null, modifier = Modifier.size(19.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(l("Выйти", "Sign out"), fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(l("Аккаунт", "Account"), color = Mist, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            SettingsLink(Icons.Outlined.Password, l("Сменить пароль", "Change password"), l("Обновить пароль аккаунта", "Update your account password")) {
                showPasswordDialog = true
                accountMessage = null
            }
            SettingsLink(
                Icons.Outlined.Fingerprint,
                if (passkeyEnabled) l("Удалить Passkey", "Remove Passkey") else l("Добавить Passkey", "Add Passkey"),
                if (passkeyEnabled) l("Отключить быстрый вход", "Disable quick sign-in") else l("Вход без ввода пароля", "Sign in without entering a password")
            ) {
                accountMessage = null
                if (passkeyEnabled) showDeletePasskeyDialog = true else addPasskey()
            }
            SettingsLink(
                Icons.Outlined.QrCode,
                l("Подключить устройство", "Connect device"),
                l("Показать или отсканировать QR-код", "Show or scan a QR code"),
                onConnectDevice
            )
            SettingsLink(
                Icons.Outlined.Devices,
                l("Устройства", "Devices"),
                l("Активные сеансы аккаунта", "Active account sessions"),
                onOpenDevices
            )
            Spacer(Modifier.height(8.dp))
            Text(l("Оформление", "Appearance"), color = Mist, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            SettingsLink(
                Icons.Outlined.Palette,
                l("Тема", "Theme"),
                when (themeMode) {
                    ThemeMode.System -> l("Как в системе", "System default")
                    ThemeMode.Light -> l("Светлая", "Light")
                    ThemeMode.Dark -> l("Тёмная", "Dark")
                }
            ) { showThemeDialog = true }
            SettingsLink(
                Icons.Outlined.Language,
                l("Язык", "Language"),
                if (language == AppLanguage.Russian) "Русский" else "English"
            ) { showLanguageDialog = true }
            if (isAdmin) {
                Spacer(Modifier.height(8.dp))
                Text(l("Управление", "Management"), color = Mist, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                SettingsLink(
                    Icons.Outlined.AdminPanelSettings,
                    l("Администрирование", "Administration"),
                    l("Серверы и пользователи", "Servers and users"),
                    onOpenAdmin
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(l("Приложение", "Application"), color = Mist, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            SettingsLink(Icons.Outlined.Info, l("О приложении", "About"), l("Версия и обновления", "Version and updates"), onOpenAbout)
            Spacer(Modifier.height(8.dp))
        }
    }

    if (showDeletePasskeyDialog) {
        Dialog(
            onDismissRequest = { showDeletePasskeyDialog = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(.92f),
                shape = RoundedCornerShape(28.dp),
                color = Panel,
                tonalElevation = 6.dp
            ) {
                Column(Modifier.padding(24.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Outlined.Fingerprint,
                            null,
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(32.dp)
                        )
                        Spacer(Modifier.width(12.dp))
                        Text(l("Удалить Passkey?", "Remove Passkey?"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(18.dp))
                    Text(
                        l("Быстрый вход будет отключён. Войти можно будет по логину и паролю.", "Quick sign-in will be disabled. You can still sign in with your username and password."),
                        color = Mist,
                        fontSize = 18.sp,
                        lineHeight = 25.sp
                    )
                    Spacer(Modifier.height(24.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(
                            onClick = { showDeletePasskeyDialog = false },
                            modifier = Modifier.weight(1f).height(52.dp),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink)
                        ) { Text(l("Отмена", "Cancel"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
                        OutlinedButton(
                            onClick = {
                                prefs.edit().putBoolean("biometric_enabled", false).apply()
                                passkeyEnabled = false
                                showDeletePasskeyDialog = false
                                accountMessage = l("Passkey удалён", "Passkey removed")
                            },
                            modifier = Modifier.weight(1f).height(52.dp),
                            shape = RoundedCornerShape(14.dp),
                            border = androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.error),
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)
                        ) { Text(l("Удалить", "Remove"), fontSize = 16.sp, fontWeight = FontWeight.Bold) }
                    }
                }
            }
        }
    }

    if (showThemeDialog) {
        Dialog(
            onDismissRequest = { showThemeDialog = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(.92f),
                shape = RoundedCornerShape(28.dp),
                color = Panel,
                tonalElevation = 6.dp
            ) {
                Column(Modifier.padding(24.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.DarkMode, null, tint = Mint, modifier = Modifier.size(32.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(l("Выберите тему", "Choose theme"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(20.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    listOf(
                        ThemeMode.System to l("Системная", "System default"),
                        ThemeMode.Light to l("Светлая", "Light"),
                        ThemeMode.Dark to l("Тёмная", "Dark")
                    ).forEach { (mode, label) ->
                        val selected = themeMode == mode
                        Row(
                            Modifier.fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(if (selected) Mint.copy(alpha = .16f) else Color.Transparent)
                                .clickable {
                                    onThemeChange(mode)
                                    showThemeDialog = false
                                }
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = selected, onClick = null)
                            Spacer(Modifier.width(8.dp))
                            Text(label, fontSize = 18.sp, fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium, color = Ink)
                        }
                    }
                    }
                }
            }
        }
    }

    if (showLanguageDialog) {
        Dialog(
            onDismissRequest = { showLanguageDialog = false },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(.92f),
                shape = RoundedCornerShape(28.dp),
                color = Panel,
                tonalElevation = 6.dp
            ) {
                Column(Modifier.padding(24.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Language, null, tint = Mint, modifier = Modifier.size(32.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(l("Выберите язык", "Choose language"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(20.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        listOf(
                            AppLanguage.Russian to "Русский",
                            AppLanguage.English to "English"
                        ).forEach { (item, label) ->
                            val selected = language == item
                            Row(
                                Modifier.fillMaxWidth()
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(if (selected) Mint.copy(alpha = .16f) else Color.Transparent)
                                    .clickable {
                                        onLanguageChange(item)
                                        showLanguageDialog = false
                                    }
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                RadioButton(selected = selected, onClick = null)
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    label,
                                    color = Ink,
                                    fontSize = 18.sp,
                                    fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showPasswordDialog) ChangePasswordDialog(
        onDismiss = { showPasswordDialog = false },
        onSave = { newPassword ->
            prefs.edit().putString("account_password", newPassword).apply()
            showPasswordDialog = false
            accountMessage = l("Пароль изменён", "Password changed")
        }
    )

    accountMessage?.let { message ->
        val success = message.contains("добавлен") || message.contains("изменён") || message.contains("удалён") ||
            message.contains("added", ignoreCase = true) || message.contains("changed", ignoreCase = true) || message.contains("removed", ignoreCase = true)
        val needsBiometricSetup = message.startsWith("Сначала настройте") || message.startsWith("First set up")
        Dialog(
            onDismissRequest = { accountMessage = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(.92f),
                shape = RoundedCornerShape(28.dp),
                color = Panel,
                tonalElevation = 6.dp
            ) {
                Column(Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        if (success) Icons.Outlined.CheckCircle else Icons.Outlined.Info,
                        null,
                        tint = if (success) Mint else Ink,
                        modifier = Modifier.size(32.dp)
                    )
                    Spacer(Modifier.width(12.dp))
                    Text(
                        if (success) l("Готово", "Done") else l("Быстрый вход недоступен", "Quick sign-in unavailable"),
                        fontSize = 22.sp,
                        lineHeight = 27.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Spacer(Modifier.height(18.dp))
                Text(message, fontSize = 18.sp, lineHeight = 25.sp)
                Spacer(Modifier.height(24.dp))
                if (needsBiometricSetup) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OutlinedButton(
                            onClick = { accountMessage = null },
                            modifier = Modifier.weight(1f).height(52.dp),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink)
                        ) {
                            Text(l("Отмена", "Cancel"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        }
                        OutlinedButton(
                            onClick = {
                                accountMessage = null
                                openBiometricSettings()
                            },
                            modifier = Modifier.weight(1f).height(52.dp),
                            shape = RoundedCornerShape(14.dp),
                            border = androidx.compose.foundation.BorderStroke(1.5.dp, Mint),
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = Mint)
                        ) {
                            Text(l("Настроить", "Set up"), fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                        }
                    }
                } else {
                    Button(
                        onClick = { accountMessage = null },
                        modifier = Modifier.align(Alignment.End),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Mint)
                    ) {
                        Text(l("Понятно", "OK"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                }
            }
        }
    }
}

@Composable
private fun ChangePasswordDialog(onDismiss: () -> Unit, onSave: (String) -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    var newPassword by remember { mutableStateOf("") }
    var repeated by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth(.92f),
            shape = RoundedCornerShape(28.dp),
            color = Panel,
            tonalElevation = 6.dp
        ) {
            Column(
                Modifier.padding(24.dp)
                    .verticalScroll(rememberScrollState())
                    .imePadding()
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Lock, null, tint = Mint, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(l("Смена пароля", "Change password"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(20.dp))
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        newPassword,
                        { newPassword = it; error = null },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(l("Новый пароль", "New password"), fontSize = 16.sp) },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        shape = RoundedCornerShape(16.dp)
                    )
                    OutlinedTextField(
                        repeated,
                        { repeated = it; error = null },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(l("Повторите новый пароль", "Repeat new password"), fontSize = 16.sp) },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        shape = RoundedCornerShape(16.dp)
                    )
                }
                Spacer(Modifier.height(8.dp))
                Box(Modifier.fillMaxWidth().height(42.dp), contentAlignment = Alignment.TopStart) {
                    error?.let {
                        Text(it, color = MaterialTheme.colorScheme.error, fontSize = 16.sp, lineHeight = 21.sp)
                    }
                }
                Spacer(Modifier.height(6.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink)
                    ) {
                        Text(l("Отмена", "Cancel"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    }
                    OutlinedButton(
                        onClick = {
                            when {
                                newPassword.isBlank() -> error = l("Введите новый пароль", "Enter a new password")
                                newPassword != repeated -> error = l("Пароли не совпадают", "Passwords do not match")
                                else -> onSave(newPassword)
                            }
                        },
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        border = androidx.compose.foundation.BorderStroke(1.5.dp, Mint),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Mint)
                    ) {
                        Text(l("Сохранить", "Save"), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
internal fun AboutScreen(onBack: () -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val context = LocalContext.current
    val version = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "1.0"
    }
    var checking by remember { mutableStateOf(false) }
    var updateStatus by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(checking) {
        if (checking) {
            delay(1_400)
            checking = false
            updateStatus = l("Установлена актуальная версия", "You’re using the latest version")
        }
    }

    Column(Modifier.fillMaxSize().background(Cloud).statusBarsPadding().navigationBarsPadding()) {
        ScreenHeader(l("О приложении", "About"), onBack)
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(26.dp))
            Image(
                painter = painterResource(R.drawable.caelo_logo),
                contentDescription = l("Иконка Caelo", "Caelo icon"),
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(108.dp).clip(RoundedCornerShape(30.dp))
            )
            Spacer(Modifier.height(20.dp))
            Text("Caelo", color = Ink, fontSize = 30.sp, fontWeight = FontWeight.Bold)
            Text(l("Простое управление защищённым подключением", "Simple control of a secure connection"), color = Mist, fontSize = 16.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Spacer(Modifier.height(26.dp))
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(Panel).padding(18.dp)
            ) {
                Text(l("О Caelo", "About Caelo"), color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(
                    l("Caelo помогает выбрать доступный сервер и управлять подключением в понятном интерфейсе без сложных настроек.", "Caelo helps you choose an available server and manage your connection through a clear interface without complicated settings."),
                    color = Mist,
                    fontSize = 17.sp,
                    lineHeight = 24.sp
                )
                Spacer(Modifier.height(18.dp))
                Text(l("Возможности", "Features"), color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(
                    l("• Быстрое подключение в одно касание\n• Выбор доступных серверов\n• Вход по паролю или Passkey\n• Светлая и тёмная темы", "• One-tap connection\n• Choice of available servers\n• Password or Passkey sign-in\n• Light and dark themes"),
                    color = Mist,
                    fontSize = 17.sp,
                    lineHeight = 27.sp
                )
            }
            Spacer(Modifier.height(20.dp))
            Button(
                onClick = { checking = true; updateStatus = null },
                enabled = !checking,
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Mint)
            ) {
                if (checking) {
                    CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                }
                Text(if (checking) l("Проверяем…", "Checking…") else l("Проверить обновления", "Check for updates"), fontSize = 17.sp)
            }
            updateStatus?.let {
                Spacer(Modifier.height(14.dp))
                Text(it, color = Mint, fontSize = 16.sp, fontWeight = FontWeight.Medium)
            }
            Spacer(Modifier.height(28.dp))
            Text("${l("Версия", "Version")} $version · Android 8–16", color = Mist, fontSize = 15.sp)
            Spacer(Modifier.height(8.dp))
            Text("© 2026 Caelo", color = Mist.copy(alpha = .75f), fontSize = 14.sp)
            Spacer(Modifier.height(22.dp))
        }
    }
}

@Composable
internal fun AdminScreen(
    servers: MutableList<Server>,
    liveLatencies: androidx.compose.runtime.snapshots.SnapshotStateMap<String, Int?>,
    users: MutableList<UserAccount>,
    onBack: () -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val darkInterface = MaterialTheme.colorScheme.surface.luminance() < .5f
    val menuBackground = if (darkInterface) Panel else Color.White
    val menuTextColor = if (darkInterface) Ink else Color(0xFF183D37)
    var showAddDialog by remember { mutableStateOf(false) }
    var showAddUserDialog by remember { mutableStateOf(false) }
    var editingServer by remember { mutableStateOf<Server?>(null) }
    var deletingServer by remember { mutableStateOf<Server?>(null) }
    var serverSettings by remember { mutableStateOf<Server?>(null) }
    var removingServerName by remember { mutableStateOf<String?>(null) }
    var selectedTab by remember { mutableIntStateOf(0) }
    var userSearch by remember { mutableStateOf("") }
    var roleFilter by remember { mutableStateOf<UserRole?>(null) }
    var userSort by remember { mutableStateOf(UserSort.Newest) }
    var showRoleFilterMenu by remember { mutableStateOf(false) }
    var showUserSortMenu by remember { mutableStateOf(false) }
    var userToDelete by remember { mutableStateOf<UserAccount?>(null) }
    var userToToggleAdmin by remember { mutableStateOf<UserAccount?>(null) }
    var userToEditServers by remember { mutableStateOf<UserAccount?>(null) }
    var recoveryCodeUser by remember { mutableStateOf<UserAccount?>(null) }
    var userSettings by remember { mutableStateOf<UserAccount?>(null) }
    var createdInvitation by remember { mutableStateOf<UserAccount?>(null) }
    var invitationToRevoke by remember { mutableStateOf<UserAccount?>(null) }
    val scope = rememberCoroutineScope()
    val sortedServers = servers.sortedWith(
        compareBy<Server> { it.badge.ordinal }
            .thenBy { liveLatencies[it.name] ?: Int.MAX_VALUE }
    )
    val visibleUsers = users.asSequence()
        .filter { it.name.contains(userSearch.trim(), ignoreCase = true) }
        .filter { roleFilter == null || it.role == roleFilter }
        .let { sequence ->
            when (userSort) {
                UserSort.Newest -> sequence.sortedByDescending { it.createdAt }
                UserSort.Oldest -> sequence.sortedBy { it.createdAt }
                UserSort.NameAsc -> sequence.sortedBy { it.name.lowercase() }
                UserSort.NameDesc -> sequence.sortedByDescending { it.name.lowercase() }
                UserSort.RecentActivity -> sequence.sortedByDescending { it.lastConnectedAt ?: Long.MIN_VALUE }
                UserSort.MostServers -> sequence.sortedByDescending { it.serverNames.size }
            }
        }.toList()

    Column(Modifier.fillMaxSize().background(Cloud).statusBarsPadding()) {
        ScreenHeader(l("Админ-панель", "Admin panel"), onBack)
        TabRow(
            selectedTabIndex = selectedTab,
            containerColor = Color.Transparent,
            contentColor = Ink,
            modifier = Modifier.padding(horizontal = 20.dp)
        ) {
            Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 }, text = { Text(l("Серверы", "Servers")) })
            Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 }, text = { Text(l("Пользователи", "Users")) })
        }
        Spacer(Modifier.height(16.dp))
        if (selectedTab == 0) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(l("Серверы", "Servers"), color = Ink, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                            Text("${servers.size} ${l("активных конфигураций", "active configurations")}", color = Mist, fontSize = 14.sp)
                        }
                        FilledIconButton(
                            onClick = { showAddDialog = true },
                            modifier = Modifier.size(50.dp),
                            shape = RoundedCornerShape(16.dp),
                            colors = IconButtonDefaults.filledIconButtonColors(containerColor = Mint, contentColor = Color.White)
                        ) {
                            Icon(Icons.Outlined.Add, l("Добавить сервер", "Add server"), modifier = Modifier.size(25.dp))
                        }
                    }
                }
                items(sortedServers, key = { it.name }) { server ->
                    AnimatedVisibility(
                        visible = removingServerName != server.name,
                        exit = slideOutHorizontally(targetOffsetX = { it }) + fadeOut()
                    ) {
                        AdminServerRow(
                            server.copy(latency = liveLatencies[server.name]),
                            onSettings = { serverSettings = server }
                        )
                    }
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(l("Пользователи", "Users"), color = Ink, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                            Text("${users.size} ${l("учётных записи", "accounts")}", color = Mist, fontSize = 14.sp)
                        }
                        FilledIconButton(
                            onClick = { showAddUserDialog = true },
                            modifier = Modifier.size(50.dp),
                            shape = RoundedCornerShape(16.dp),
                            colors = IconButtonDefaults.filledIconButtonColors(containerColor = Mint, contentColor = Color.White)
                        ) {
                            Icon(Icons.Outlined.PersonAdd, l("Создать пользователя", "Create user"), modifier = Modifier.size(24.dp))
                        }
                    }
                }
                item {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OutlinedTextField(
                            value = userSearch,
                            onValueChange = { userSearch = it },
                            modifier = Modifier.weight(1f),
                            placeholder = { Text(l("Поиск по имени", "Search by name"), fontSize = 15.sp) },
                            leadingIcon = { Icon(Icons.Outlined.Search, null) },
                            singleLine = true,
                            shape = RoundedCornerShape(16.dp)
                        )
                        Box {
                            FilledTonalIconButton(
                                onClick = { showUserSortMenu = true },
                                modifier = Modifier.size(52.dp).shadow(2.dp, RoundedCornerShape(16.dp)),
                                shape = RoundedCornerShape(16.dp),
                                colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = Panel, contentColor = Ink)
                            ) {
                                Icon(Icons.Outlined.SwapVert, l("Сортировка", "Sort"), tint = Mint)
                            }
                            DropdownMenu(
                                expanded = showUserSortMenu,
                                onDismissRequest = { showUserSortMenu = false },
                                modifier = Modifier.width(270.dp).border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = .35f), RoundedCornerShape(18.dp)),
                                shape = RoundedCornerShape(18.dp),
                                containerColor = menuBackground,
                                tonalElevation = 8.dp
                            ) {
                                listOf(
                                    UserSort.Newest to l("Сначала новые", "Newest first"),
                                    UserSort.Oldest to l("Сначала старые", "Oldest first"),
                                    UserSort.NameAsc to l("Имя А–Я", "Name A–Z"),
                                    UserSort.NameDesc to l("Имя Я–А", "Name Z–A"),
                                    UserSort.RecentActivity to l("Недавняя активность", "Recent activity"),
                                    UserSort.MostServers to l("Больше серверов", "Most servers")
                                ).forEach { (sort, label) ->
                                    DropdownMenuItem(
                                        modifier = Modifier.background(if (userSort == sort) Mint.copy(alpha = .13f) else Color.Transparent),
                                        text = { Text(label, color = menuTextColor) },
                                        leadingIcon = { if (userSort == sort) Icon(Icons.Outlined.Check, null, tint = Mint) },
                                        onClick = { userSort = sort; showUserSortMenu = false }
                                    )
                                }
                            }
                        }
                        Box {
                            FilledTonalIconButton(
                                onClick = { showRoleFilterMenu = true },
                                modifier = Modifier.size(52.dp).shadow(2.dp, RoundedCornerShape(16.dp)),
                                shape = RoundedCornerShape(16.dp),
                                colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = Panel, contentColor = Ink)
                            ) {
                                Icon(Icons.Outlined.FilterAlt, l("Фильтр", "Filter"), tint = if (roleFilter == null) Mist else Mint)
                            }
                            DropdownMenu(
                                expanded = showRoleFilterMenu,
                                onDismissRequest = { showRoleFilterMenu = false },
                                modifier = Modifier.width(250.dp).border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = .35f), RoundedCornerShape(18.dp)),
                                shape = RoundedCornerShape(18.dp),
                                containerColor = menuBackground,
                                tonalElevation = 8.dp
                            ) {
                                listOf(
                                    null to l("Все роли", "All roles"),
                                    UserRole.User to l("Пользователи", "Users"),
                                    UserRole.Admin to l("Администраторы", "Administrators")
                                ).forEach { (role, label) ->
                                    DropdownMenuItem(
                                        modifier = Modifier.background(if (roleFilter == role) Mint.copy(alpha = .13f) else Color.Transparent),
                                        text = { Text(label, color = menuTextColor) },
                                        leadingIcon = { if (roleFilter == role) Icon(Icons.Outlined.Check, null, tint = Mint) },
                                        onClick = { roleFilter = role; showRoleFilterMenu = false }
                                    )
                                }
                            }
                        }
                    }
                }
                item {
                    Text(
                        "${l("Найдено", "Found")}: ${visibleUsers.size}",
                        color = Mist,
                        fontSize = 14.sp
                    )
                }
                items(visibleUsers, key = { it.inviteCode }) { user ->
                    UserRow(user = user, onSettings = { userSettings = user })
                }
            }
        }
    }

    if (showAddDialog) AddServerDialog(
        onDismiss = { showAddDialog = false },
        onAdd = { name, description, country, badge, rootConfig, adminOnly ->
            servers.add(Server(name, description, country, 50, badge, rootConfig, adminOnly))
            liveLatencies[name] = 50
            showAddDialog = false
        }
    )
    serverSettings?.let { server ->
        ServerSettingsDialog(
            server = server,
            onDismiss = { serverSettings = null },
            onEdit = { serverSettings = null; editingServer = server },
            onDelete = { serverSettings = null; deletingServer = server }
        )
    }
    editingServer?.let { original ->
        AddServerDialog(
            initialServer = original,
            onDismiss = { editingServer = null },
            onAdd = { name, description, country, badge, rootConfig, adminOnly ->
                val index = servers.indexOf(original)
                if (index >= 0) {
                    if (rootConfig != original.rootConfig) File(original.rootConfig).takeIf { original.rootConfig.isNotBlank() }?.delete()
                    servers[index] = original.copy(
                        name = name,
                        description = description,
                        flag = country,
                        badge = badge,
                        rootConfig = rootConfig,
                        adminOnly = adminOnly
                    )
                    if (name != original.name) {
                        liveLatencies.remove(original.name)
                        liveLatencies[name] = original.latency
                    }
                }
                editingServer = null
            }
        )
    }
    deletingServer?.let { server ->
        DeleteServerDialog(
            serverName = server.name,
            onDismiss = { deletingServer = null },
            onConfirm = {
                deletingServer = null
                removingServerName = server.name
                scope.launch {
                    delay(420)
                    servers.remove(server)
                    liveLatencies.remove(server.name)
                    if (server.rootConfig.isNotBlank()) File(server.rootConfig).delete()
                    removingServerName = null
                }
            }
        )
    }
    if (showAddUserDialog) AddUserDialog(
        servers = servers,
        onDismiss = { showAddUserDialog = false },
        onAdd = { user ->
            users.add(user)
            showAddUserDialog = false
            createdInvitation = user
        }
    )
    userToDelete?.let { user ->
        DeleteUserDialog(
            userName = user.name,
            onDismiss = { userToDelete = null },
            onConfirm = {
                users.removeAll { it.inviteCode == user.inviteCode }
                userToDelete = null
            }
        )
    }
    userToToggleAdmin?.let { user ->
        ChangeUserRoleDialog(
            user = user,
            onDismiss = { userToToggleAdmin = null },
            onConfirm = {
                val index = users.indexOfFirst { it.inviteCode == user.inviteCode }
                if (index >= 0) users[index] = users[index].copy(
                    role = if (user.role == UserRole.Admin) UserRole.User else UserRole.Admin
                )
                userToToggleAdmin = null
            }
        )
    }
    userToEditServers?.let { user ->
        EditUserServersDialog(
            user = user,
            servers = servers.filter { !it.adminOnly || user.role == UserRole.Admin },
            onDismiss = { userToEditServers = null },
            onSave = { selected ->
                val index = users.indexOfFirst { it.inviteCode == user.inviteCode }
                if (index >= 0) users[index] = users[index].copy(serverNames = selected)
                userToEditServers = null
            }
        )
    }
    recoveryCodeUser?.let { user ->
        RecoveryCodeDialog(user, onDismiss = { recoveryCodeUser = null })
    }
    userSettings?.let { user ->
        if (user.pendingInvitation) {
            InvitationSettingsDialog(
                invitation = user,
                onDismiss = { userSettings = null },
                onRevoke = { userSettings = null; invitationToRevoke = user }
            )
        } else {
            UserSettingsDialog(
                user = user,
                onDismiss = { userSettings = null },
                onServers = { userSettings = null; userToEditServers = user },
                onRole = { userSettings = null; userToToggleAdmin = user },
                onRecovery = {
                    val index = users.indexOfFirst { it.inviteCode == user.inviteCode }
                    if (index >= 0) {
                        val updated = users[index].copy(recoveryCode = "RECOVERY-${UUID.randomUUID().toString().take(8).uppercase()}")
                        users[index] = updated
                        recoveryCodeUser = updated
                    }
                    userSettings = null
                },
                onDelete = { userSettings = null; userToDelete = user }
            )
        }
    }
    createdInvitation?.let { invitation ->
        InvitationCodeDialog(invitation, onDismiss = { createdInvitation = null })
    }
    invitationToRevoke?.let { invitation ->
        UserActionDialog(
            icon = Icons.Outlined.LinkOff,
            iconColor = MaterialTheme.colorScheme.error,
            title = l("Отозвать приглашение?", "Revoke invitation?"),
            message = l("Код доступа перестанет работать.", "The access code will stop working."),
            confirmText = l("Отозвать", "Revoke"),
            confirmColor = MaterialTheme.colorScheme.error,
            onDismiss = { invitationToRevoke = null },
            onConfirm = {
                users.removeAll { it.inviteCode == invitation.inviteCode }
                invitationToRevoke = null
            }
        )
    }
}

@Composable
private fun ScreenHeader(title: String, onBack: () -> Unit) {
    val language = LocalAppLanguage.current
    Row(
        Modifier.fillMaxWidth().height(72.dp).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = onBack) { Icon(Icons.Outlined.ArrowBack, uiText(language, "Назад", "Back"), tint = Ink) }
        Text(title, color = Ink, fontWeight = FontWeight.Bold, fontSize = 25.sp)
    }
}

@Composable
private fun SettingsLink(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    description: String,
    onClick: () -> Unit
) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Panel)
            .clickable(onClick = onClick).padding(17.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = Mint, modifier = Modifier.size(27.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = Ink, fontWeight = FontWeight.Bold, fontSize = 19.sp)
            Text(description, color = Mist, fontSize = 16.sp, lineHeight = 21.sp)
        }
        Icon(Icons.Outlined.ChevronRight, null, tint = Mist)
    }
}

@Composable
private fun AdminServerRow(server: Server, onSettings: () -> Unit) {
    val latency = server.latency
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val badgeColor = when (server.badge) {
        ServerBadge.Main -> Color(0xFF3B82F6)
        ServerBadge.Stable -> Color(0xFF2FA982)
        ServerBadge.Testing -> Color(0xFFE5A819)
        ServerBadge.Offline -> Color(0xFFE05252)
    }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(badgeColor.copy(alpha = .11f))
            .border(1.dp, badgeColor.copy(alpha = .30f), RoundedCornerShape(18.dp))
            .padding(15.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        FlagBadge(server.flag, width = 46, height = 29)
        Spacer(Modifier.width(13.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(server.name, color = Ink, fontWeight = FontWeight.Bold, fontSize = 16.sp, maxLines = 1)
                Spacer(Modifier.width(5.dp))
                ServerStatusBadge(server.badge)
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                Text(
                    if (latency == null) l("Нет связи", "No connection") else "$latency ${l("мс", "ms")}",
                    color = if (latency == null) Color(0xFFE05252) else Mint,
                    fontSize = 13.sp
                )
            }
            Text(serverDescription(language, server.description), color = Mist, fontSize = 13.sp, lineHeight = 17.sp, maxLines = 3, modifier = Modifier.fillMaxWidth())
            if (server.adminOnly) {
                Text(
                    l("Админам", "Admins"),
                    color = Violet,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        Spacer(Modifier.width(6.dp))
        IconButton(
            onClick = onSettings,
            modifier = Modifier.size(46.dp)
        ) {
            Icon(
                Icons.Outlined.Settings,
                l("Настройки сервера", "Server settings"),
                tint = badgeColor,
                modifier = Modifier.size(29.dp)
            )
        }
    }
}

@Composable
private fun UserRow(
    user: UserAccount,
    onSettings: () -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(42.dp).clip(RoundedCornerShape(13.dp))
                    .background(if (user.role == UserRole.Admin) Violet.copy(alpha = .13f) else Mint.copy(alpha = .13f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    if (user.role == UserRole.Admin) Icons.Outlined.AdminPanelSettings else Icons.Outlined.Person,
                    null,
                    tint = if (user.role == UserRole.Admin) Violet else Mint
                )
            }
            Spacer(Modifier.width(13.dp))
            Column(Modifier.weight(1f)) {
                Text(user.name, color = Ink, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                Text(if (user.role == UserRole.Admin) l("Администратор", "Administrator") else l("Пользователь", "User"), color = Mist, fontSize = 13.sp)
            }
            FilledTonalIconButton(
                onClick = onSettings,
                modifier = Modifier.size(42.dp),
                shape = RoundedCornerShape(13.dp),
                colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Icon(Icons.Outlined.Settings, l("Настройки пользователя", "User settings"), tint = Ink, modifier = Modifier.size(21.dp))
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Schedule, null, tint = Mist, modifier = Modifier.size(17.dp))
            Spacer(Modifier.width(7.dp))
            Text(
                user.lastConnectedAt?.let {
                    val formatted = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault()).format(Date(it))
                    "${l("Последний коннект", "Last connection")}: $formatted"
                } ?: l("Подключений ещё не было", "No connections yet"),
                color = Mist,
                fontSize = 13.sp
            )
        }
        Spacer(Modifier.height(8.dp))
        Text("${l("Доступно серверов", "Available servers")}: ${user.serverNames.size}", color = Mist, fontSize = 13.sp)
    }
}

@Composable
private fun UserSettingsDialog(
    user: UserAccount,
    onDismiss: () -> Unit,
    onServers: () -> Unit,
    onRole: () -> Unit,
    onRecovery: () -> Unit,
    onDelete: () -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Settings, null, tint = Mint, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(l("Настройки пользователя", "User settings"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        Text(user.name, color = Mist, fontSize = 15.sp)
                    }
                }
                Spacer(Modifier.height(20.dp))
                UserSettingsAction(Icons.Outlined.Dns, l("Доступные серверы", "Available servers"), l("Выбрать конфигурации", "Choose configurations"), Mint, onServers)
                Spacer(Modifier.height(8.dp))
                UserSettingsAction(
                    if (user.role == UserRole.Admin) Icons.Outlined.PersonRemove else Icons.Outlined.AdminPanelSettings,
                    if (user.role == UserRole.Admin) l("Снять права", "Remove admin rights") else l("Назначить администратором", "Make administrator"),
                    l("Изменить роль пользователя", "Change user role"),
                    Violet,
                    onRole
                )
                Spacer(Modifier.height(8.dp))
                UserSettingsAction(Icons.Outlined.RestartAlt, l("Код восстановления", "Recovery code"), l("Создать новый код", "Generate a new code"), Mint, onRecovery)
                Spacer(Modifier.height(8.dp))
                UserSettingsAction(Icons.Outlined.DeleteOutline, l("Удалить пользователя", "Delete user"), l("Действие нельзя отменить", "This action cannot be undone"), MaterialTheme.colorScheme.error, onDelete)
            }
        }
    }
}

@Composable
private fun InvitationSettingsDialog(
    invitation: UserAccount,
    onDismiss: () -> Unit,
    onRevoke: () -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Key, null, tint = Mint, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(l("Настройки приглашения", "Invitation settings"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(20.dp))
                Text(l("Код доступа", "Access code"), color = Mist, fontSize = 15.sp)
                Spacer(Modifier.height(7.dp))
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .border(1.dp, Mint.copy(alpha = .38f), RoundedCornerShape(14.dp))
                        .padding(start = 14.dp, top = 7.dp, bottom = 7.dp, end = 5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(invitation.inviteCode, color = Ink, fontSize = 18.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, modifier = Modifier.weight(1f))
                    IconButton(
                        onClick = { clipboard.setText(AnnotatedString(invitation.inviteCode)); copied = true },
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(
                            if (copied) Icons.Outlined.CheckCircle else Icons.Outlined.ContentCopy,
                            if (copied) l("Скопировано", "Copied") else l("Копировать", "Copy"),
                            tint = Mint
                        )
                    }
                }
                Spacer(Modifier.height(18.dp))
                OutlinedButton(
                    onClick = onRevoke,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    shape = RoundedCornerShape(14.dp),
                    border = androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.error),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) {
                    Icon(Icons.Outlined.LinkOff, null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(l("Отозвать приглашение", "Revoke invitation"), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun UserSettingsAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    description: String,
    color: Color,
    onClick: () -> Unit
) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .7f))
            .clickable(onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, tint = color, modifier = Modifier.size(25.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(description, color = Mist, fontSize = 14.sp)
        }
        Icon(Icons.Outlined.ChevronRight, null, tint = Mist)
    }
}

@Composable
private fun DeleteUserDialog(userName: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    UserActionDialog(
        icon = Icons.Outlined.DeleteOutline,
        iconColor = MaterialTheme.colorScheme.error,
        title = l("Удалить пользователя?", "Delete user?"),
        message = if (language == AppLanguage.Russian) "Пользователь «$userName» будет удалён." else "User “$userName” will be deleted.",
        confirmText = l("Удалить", "Delete"),
        confirmColor = MaterialTheme.colorScheme.error,
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}

@Composable
private fun ChangeUserRoleDialog(user: UserAccount, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val granting = user.role != UserRole.Admin
    UserActionDialog(
        icon = if (granting) Icons.Outlined.AdminPanelSettings else Icons.Outlined.PersonRemove,
        iconColor = if (granting) Mint else MaterialTheme.colorScheme.error,
        title = if (granting) l("Назначить администратором?", "Make administrator?") else l("Снять права администратора?", "Remove administrator rights?"),
        message = if (granting) {
            if (language == AppLanguage.Russian) "«${user.name}» получит доступ к функциям администратора." else "“${user.name}” will get access to administrator features."
        } else {
            if (language == AppLanguage.Russian) "«${user.name}» потеряет доступ к функциям администратора." else "“${user.name}” will lose access to administrator features."
        },
        confirmText = if (granting) l("Назначить", "Confirm") else l("Снять права", "Remove rights"),
        confirmColor = if (granting) Mint else MaterialTheme.colorScheme.error,
        onDismiss = onDismiss,
        onConfirm = onConfirm
    )
}

@Composable
private fun UserActionDialog(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconColor: Color,
    title: String,
    message: String,
    confirmText: String,
    confirmColor: Color,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val language = LocalAppLanguage.current
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(icon, null, tint = iconColor, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(title, color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold, lineHeight = 27.sp)
                }
                Spacer(Modifier.height(18.dp))
                Text(message, color = Mist, fontSize = 18.sp, lineHeight = 25.sp)
                Spacer(Modifier.height(24.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f).height(52.dp), shape = RoundedCornerShape(14.dp)) {
                        Text(uiText(language, "Отмена", "Cancel"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    }
                    OutlinedButton(
                        onClick = onConfirm,
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        border = androidx.compose.foundation.BorderStroke(1.5.dp, confirmColor),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = confirmColor)
                    ) { Text(confirmText, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1) }
                }
            }
        }
    }
}

@Composable
private fun EditUserServersDialog(
    user: UserAccount,
    servers: List<Server>,
    onDismiss: () -> Unit,
    onSave: (Set<String>) -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val selected = remember(user) { mutableStateListOf<String>().apply { addAll(user.serverNames) } }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Dns, null, tint = Mint, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(l("Доступные серверы", "Available servers"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(16.dp))
            LazyColumn(Modifier.heightIn(max = 390.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(servers, key = { it.name }) { server ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp))
                            .background(if (server.name in selected) Mint.copy(alpha = .10f) else Color.Transparent)
                            .clickable {
                            if (server.name in selected) selected.remove(server.name) else selected.add(server.name)
                        }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(checked = server.name in selected, onCheckedChange = null)
                        FlagBadge(server.flag, width = 38, height = 26)
                        Spacer(Modifier.width(8.dp))
                        Text(server.name, color = Ink, fontSize = 17.sp, modifier = Modifier.weight(1f))
                        ServerStatusBadge(server.badge)
                    }
                }
            }
                Spacer(Modifier.height(20.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f).height(52.dp), shape = RoundedCornerShape(14.dp)) {
                        Text(l("Отмена", "Cancel"), fontSize = 16.sp)
                    }
                    OutlinedButton(
                        onClick = { onSave(selected.toSet()) },
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        border = androidx.compose.foundation.BorderStroke(1.5.dp, Mint),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Mint)
                    ) { Text(l("Сохранить", "Save"), fontSize = 16.sp, fontWeight = FontWeight.Bold) }
                }
            }
        }
    }
}

@Composable
private fun RecoveryCodeDialog(user: UserAccount, onDismiss: () -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.RestartAlt, null, tint = Mint, modifier = Modifier.size(36.dp))
                Spacer(Modifier.height(12.dp))
                Text(l("Код восстановления", "Recovery code"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(user.name, color = Mist, fontSize = 16.sp)
                Spacer(Modifier.height(18.dp))
                Row(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .border(1.dp, Mint.copy(alpha = .38f), RoundedCornerShape(14.dp))
                        .padding(start = 14.dp, top = 7.dp, bottom = 7.dp, end = 5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        user.recoveryCode.orEmpty(),
                        color = Ink,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = .7.sp,
                        modifier = Modifier.weight(1f),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                    IconButton(
                        onClick = {
                            clipboard.setText(AnnotatedString(user.recoveryCode.orEmpty()))
                            copied = true
                        },
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(
                            if (copied) Icons.Outlined.CheckCircle else Icons.Outlined.ContentCopy,
                            if (copied) l("Скопировано", "Copied") else l("Копировать", "Copy"),
                            tint = Mint
                        )
                    }
                }
                Spacer(Modifier.height(20.dp))
                Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth().height(50.dp), shape = RoundedCornerShape(14.dp)) {
                    Text(l("Готово", "Done"), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun InvitationCodeDialog(invitation: UserAccount, onDismiss: () -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.Key, null, tint = Mint, modifier = Modifier.size(36.dp))
                Spacer(Modifier.height(12.dp))
                Text(l("Приглашение создано", "Invitation created"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(
                    l("Передайте этот код пользователю", "Send this code to the user"),
                    color = Mist,
                    fontSize = 16.sp,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
                Spacer(Modifier.height(18.dp))
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .border(1.dp, Mint.copy(alpha = .38f), RoundedCornerShape(14.dp))
                        .padding(start = 14.dp, top = 7.dp, bottom = 7.dp, end = 5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        invitation.inviteCode,
                        color = Ink,
                        fontSize = 19.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp,
                        modifier = Modifier.weight(1f),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                    IconButton(
                        onClick = {
                            clipboard.setText(AnnotatedString(invitation.inviteCode))
                            copied = true
                        },
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(
                            if (copied) Icons.Outlined.CheckCircle else Icons.Outlined.ContentCopy,
                            if (copied) l("Скопировано", "Copied") else l("Копировать", "Copy"),
                            tint = Mint
                        )
                    }
                }
                Spacer(Modifier.height(20.dp))
                Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth().height(50.dp), shape = RoundedCornerShape(14.dp)) {
                    Text(l("Готово", "Done"), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun AddUserDialog(servers: List<Server>, onDismiss: () -> Unit, onAdd: (UserAccount) -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    var role by remember { mutableStateOf(UserRole.User) }
    val selectedServers = remember { mutableStateListOf<String>() }
    val serverListState = rememberLazyListState()
    val accessCode = remember { "CAELO-${UUID.randomUUID().toString().take(6).uppercase()}" }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp).imePadding()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.PersonAdd, null, tint = Mint, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(l("Создать приглашение", "Create invitation"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(10.dp))
                Text(
                    l("Код доступа будет создан автоматически", "An access code will be generated automatically"),
                    color = Mist,
                    fontSize = 16.sp,
                    lineHeight = 22.sp
                )
                Spacer(Modifier.height(18.dp))
                Text(l("Роль", "Role"), color = Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    listOf(
                        UserRole.User to "User",
                        UserRole.Admin to "Admin"
                    ).forEach { (item, label) ->
                        val selected = role == item
                        Row(
                            Modifier.weight(1f).clip(RoundedCornerShape(14.dp))
                                .background(if (selected) Mint.copy(alpha = .15f) else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .55f))
                                .clickable {
                                    role = item
                                    if (item == UserRole.Admin) {
                                        selectedServers.clear()
                                        selectedServers.addAll(servers.map { it.name })
                                    }
                                }.padding(horizontal = 8.dp, vertical = 9.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = selected, onClick = null, modifier = Modifier.size(36.dp))
                            Spacer(Modifier.width(4.dp))
                            Text(label, color = Ink, fontSize = 15.sp, fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium, maxLines = 1)
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
                Text(l("Доступные серверы", "Available servers"), color = Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(8.dp))
                Box(
                    Modifier.fillMaxWidth().height(if (servers.size > 4) 245.dp else (servers.size * 57).dp)
                ) {
                    LazyColumn(
                        Modifier.fillMaxSize().padding(end = if (servers.size > 4) 18.dp else 0.dp),
                        state = serverListState,
                        verticalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        items(servers, key = { it.name }) { server ->
                            val selected = server.name in selectedServers
                            Row(
                                Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp))
                                    .background(if (selected) Mint.copy(alpha = .10f) else Color.Transparent)
                                    .clickable {
                                        if (selected) selectedServers.remove(server.name) else selectedServers.add(server.name)
                                    }.padding(horizontal = 6.dp, vertical = 7.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(checked = selected, onCheckedChange = null)
                                FlagBadge(server.flag, width = 38, height = 26)
                                Spacer(Modifier.width(8.dp))
                                Text(server.name, color = Ink, fontSize = 16.sp, modifier = Modifier.weight(1f))
                                ServerStatusBadge(server.badge)
                            }
                        }
                    }
                    if (servers.size > 4) {
                        val layoutInfo = serverListState.layoutInfo
                        val density = LocalDensity.current
                        val spacingPx = with(density) { 5.dp.toPx() }
                        val itemSizePx = layoutInfo.visibleItemsInfo.firstOrNull()?.size?.toFloat()
                            ?: with(density) { 57.dp.toPx() }
                        val viewportHeightPx = (layoutInfo.viewportEndOffset - layoutInfo.viewportStartOffset)
                            .toFloat().coerceAtLeast(1f)
                        val metrics = calculateScrollbarMetrics(
                            itemCount = servers.size,
                            itemSizePx = itemSizePx,
                            spacingPx = spacingPx,
                            viewportHeightPx = viewportHeightPx,
                            firstVisibleItemIndex = serverListState.firstVisibleItemIndex,
                            firstVisibleItemScrollOffsetPx = serverListState.firstVisibleItemScrollOffset
                        )
                        val trackHeight = 237.dp
                        val thumbHeight = trackHeight * metrics.thumbFraction
                        Box(
                            Modifier.align(Alignment.CenterEnd).width(12.dp).height(trackHeight)
                                .clip(RoundedCornerShape(6.dp))
                                .background(Color(0xFFE1E7E5))
                                .border(
                                    1.dp,
                                    MaterialTheme.colorScheme.outline.copy(alpha = .55f),
                                    RoundedCornerShape(6.dp)
                                )
                        )
                        Box(
                            Modifier.align(Alignment.TopEnd)
                                .offset(y = 7.dp + (trackHeight - thumbHeight - 6.dp) * metrics.progress)
                                .padding(end = 3.dp)
                                .width(6.dp).height(thumbHeight).clip(RoundedCornerShape(3.dp))
                                .background(Mint)
                        )
                    }
                }
                Spacer(Modifier.height(22.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f).height(52.dp), shape = RoundedCornerShape(14.dp)) {
                        Text(l("Отмена", "Cancel"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    }
                    OutlinedButton(
                        onClick = {
                            onAdd(
                                UserAccount(
                                    name = l("Ожидает регистрации", "Pending registration"),
                                    role = role,
                                    serverNames = selectedServers.toSet(),
                                    inviteCode = accessCode,
                                    pendingInvitation = true
                                )
                            )
                        },
                        enabled = selectedServers.isNotEmpty(),
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        border = androidx.compose.foundation.BorderStroke(1.5.dp, Mint),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Mint)
                    ) {
                        Text(l("Создать", "Create"), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
private fun DeleteServerDialog(
    serverName: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth(.92f),
            shape = RoundedCornerShape(28.dp),
            color = Panel,
            tonalElevation = 6.dp
        ) {
            Column(Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.DeleteOutline, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(l("Удалить сервер?", "Delete server?"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(18.dp))
                Text(
                    if (language == AppLanguage.Russian) "Сервер «$serverName» и его конфиг будут удалены." else "Server “$serverName” and its config file will be deleted.",
                    color = Mist,
                    fontSize = 18.sp,
                    lineHeight = 25.sp
                )
                Spacer(Modifier.height(24.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink)
                    ) { Text(l("Отмена", "Cancel"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
                    OutlinedButton(
                        onClick = onConfirm,
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        border = androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.error),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)
                    ) { Text(l("Удалить", "Delete"), fontSize = 16.sp, fontWeight = FontWeight.Bold) }
                }
            }
        }
    }
}

@Composable
private fun ServerSettingsDialog(
    server: Server,
    onDismiss: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Settings, null, tint = Mint, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(l("Настройки сервера", "Server settings"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        Text(server.name, color = Mist, fontSize = 15.sp)
                    }
                }
                Spacer(Modifier.height(20.dp))
                UserSettingsAction(
                    Icons.Outlined.Edit,
                    l("Редактировать", "Edit"),
                    l("Параметры, статус и конфиг", "Details, status and config"),
                    Mint,
                    onEdit
                )
                Spacer(Modifier.height(8.dp))
                UserSettingsAction(
                    Icons.Outlined.DeleteOutline,
                    l("Удалить сервер", "Delete server"),
                    l("Удалить сервер и его конфиг", "Delete the server and its config"),
                    MaterialTheme.colorScheme.error,
                    onDelete
                )
            }
        }
    }
}

@Composable
private fun AddServerDialog(
    initialServer: Server? = null,
    onDismiss: () -> Unit,
    onAdd: (String, String, String, ServerBadge, String, Boolean) -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    var name by remember(initialServer) { mutableStateOf(initialServer?.name.orEmpty()) }
    var description by remember(initialServer) { mutableStateOf(initialServer?.description.orEmpty()) }
    var flagEmoji by remember(initialServer) { mutableStateOf(initialServer?.flag ?: "🇫🇮") }
    var badge by remember(initialServer) { mutableStateOf(initialServer?.badge ?: ServerBadge.Main) }
    var adminOnly by remember(initialServer) { mutableStateOf(initialServer?.adminOnly ?: false) }
    var rootConfigPath by remember(initialServer) { mutableStateOf(initialServer?.rootConfig.orEmpty()) }
    var rootConfigName by remember(initialServer) {
        mutableStateOf(
            initialServer?.rootConfig?.takeIf { it.isNotBlank() }?.let { File(it).name.replace(Regex("^[0-9a-fA-F-]{36}-"), "") }.orEmpty()
        )
    }
    val context = LocalContext.current
    fun dismissAndCleanTemporaryFile() {
        if (rootConfigPath.isNotBlank() && rootConfigPath != initialServer?.rootConfig) File(rootConfigPath).delete()
        onDismiss()
    }
    val configPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val displayName = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME)) else null
                } ?: uri.lastPathSegment.orEmpty()
            runCatching {
                val configDirectory = File(context.filesDir, "root_configs").apply { mkdirs() }
                val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "config.conf" }
                val target = File(configDirectory, "${UUID.randomUUID()}-$safeName")
                context.contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                } ?: error("Unable to open selected file")
                rootConfigPath.takeIf { it.isNotEmpty() && it != initialServer?.rootConfig }?.let { File(it).delete() }
                rootConfigPath = target.absolutePath
                rootConfigName = displayName
            }
        }
    }

    Dialog(
        onDismissRequest = ::dismissAndCleanTemporaryFile,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth(.92f),
            shape = RoundedCornerShape(28.dp),
            color = Panel,
            tonalElevation = 6.dp
        ) {
            Column(
                Modifier.padding(24.dp)
                    .verticalScroll(rememberScrollState())
                    .imePadding()
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Dns, null, tint = Mint, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(
                        if (initialServer == null) l("Новый сервер", "New server") else l("Редактирование сервера", "Edit server"),
                        color = Ink,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Spacer(Modifier.height(20.dp))
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    name,
                    { name = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(l("Название", "Name"), fontSize = 16.sp) },
                    singleLine = true,
                    shape = RoundedCornerShape(16.dp)
                )
                OutlinedTextField(
                    description,
                    { description = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(l("Описание", "Description"), fontSize = 16.sp) },
                    singleLine = true,
                    shape = RoundedCornerShape(16.dp)
                )
                OutlinedTextField(
                    value = flagEmoji,
                    onValueChange = { flagEmoji = it.take(8) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(l("Эмодзи флага", "Flag emoji"), fontSize = 16.sp) },
                    placeholder = { Text(l("Например, 🇫🇮", "For example, 🇫🇮")) },
                    singleLine = true,
                    shape = RoundedCornerShape(16.dp)
                )
                Text(
                    if (initialServer == null) l("Root-конфиг", "Root config")
                    else l("Root-конфиг · необязательно", "Root config · optional"),
                    color = Ink,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Row(
                    modifier = Modifier.fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .border(1.dp, if (rootConfigPath.isNotEmpty()) Mint else MaterialTheme.colorScheme.outline, RoundedCornerShape(16.dp))
                        .clickable { configPicker.launch(arrayOf("*/*")) }
                        .padding(start = 15.dp, top = 12.dp, bottom = 12.dp, end = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        if (rootConfigPath.isNotEmpty()) Icons.Outlined.Description else Icons.Outlined.AttachFile,
                        null,
                        tint = if (rootConfigPath.isNotEmpty()) Mint else Mist,
                        modifier = Modifier.size(25.dp)
                    )
                    Spacer(Modifier.width(11.dp))
                    Text(
                        if (rootConfigPath.isNotEmpty()) rootConfigName else l("Прикрепить файл", "Attach file"),
                        color = if (rootConfigPath.isNotEmpty()) Ink else Mist,
                        fontSize = 16.sp,
                        fontWeight = if (rootConfigPath.isNotEmpty()) FontWeight.SemiBold else FontWeight.Normal,
                        maxLines = 1,
                        modifier = Modifier.weight(1f)
                    )
                    if (rootConfigPath.isNotEmpty()) {
                        IconButton(
                            onClick = {
                                if (rootConfigPath != initialServer?.rootConfig) File(rootConfigPath).delete()
                                rootConfigPath = ""
                                rootConfigName = ""
                            },
                            modifier = Modifier.size(38.dp)
                        ) {
                            Icon(Icons.Outlined.Close, l("Удалить файл", "Remove file"), tint = MaterialTheme.colorScheme.error)
                        }
                    }
                }
                }
                Spacer(Modifier.height(18.dp))
                Text(l("Статус", "Status"), color = Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(8.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    items(ServerBadge.entries) { item ->
                        val selected = badge == item
                        Row(
                            modifier = Modifier.clip(RoundedCornerShape(10.dp))
                                .clickable { badge = item }
                                .padding(horizontal = 5.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(
                                Modifier.graphicsLayer {
                                    scaleX = if (selected) 1.14f else 1f
                                    scaleY = if (selected) 1.14f else 1f
                                    alpha = if (selected) 1f else .58f
                                }
                            ) {
                                ServerStatusBadge(item)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(18.dp))
                Text(l("Доступен", "Available to"), color = Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    listOf(
                        false to l("Всем", "Everyone"),
                        true to l("Админам", "Admins")
                    ).forEach { (value, label) ->
                        val selected = adminOnly == value
                        Row(
                            modifier = Modifier.weight(1f)
                                .clip(RoundedCornerShape(14.dp))
                                .background(if (selected) Mint.copy(alpha = .16f) else Color.Transparent)
                                .clickable { adminOnly = value }
                                .padding(horizontal = 8.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = selected, onClick = null, modifier = Modifier.size(36.dp))
                            Spacer(Modifier.width(4.dp))
                            Text(
                                label,
                                color = Ink,
                                fontSize = 15.sp,
                                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                                maxLines = 1
                            )
                        }
                    }
                }
                Spacer(Modifier.height(24.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(
                        onClick = ::dismissAndCleanTemporaryFile,
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink)
                    ) {
                        Text(l("Отмена", "Cancel"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    }
                    OutlinedButton(
                        onClick = { onAdd(name.trim(), description.trim(), flagEmoji.trim(), badge, rootConfigPath, adminOnly) },
                        enabled = name.isNotBlank() && description.isNotBlank() && flagEmoji.isNotBlank() &&
                            (initialServer != null || rootConfigPath.isNotBlank()),
                        modifier = Modifier.weight(1f).height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        border = androidx.compose.foundation.BorderStroke(1.5.dp, Mint),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Mint)
                    ) {
                        Text(
                            if (initialServer == null) l("Добавить", "Add") else l("Сохранить", "Save"),
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}
