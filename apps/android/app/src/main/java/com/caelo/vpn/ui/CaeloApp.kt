package com.caelo.vpn.ui

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.RepeatMode
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.caelo.vpn.ui.theme.*
import com.caelo.vpn.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

internal enum class AppLanguage { Russian, English }
internal val LocalAppLanguage = staticCompositionLocalOf { AppLanguage.Russian }
internal fun uiText(language: AppLanguage, russian: String, english: String) =
    if (language == AppLanguage.Russian) russian else english
internal fun serverDescription(language: AppLanguage, value: String) = if (language == AppLanguage.Russian) value else when (value) {
    "Самый быстрый сервер" -> "Fastest server"
    "Стабильное соединение" -> "Stable connection"
    "Оптимален для видео" -> "Best for video"
    "Низкая нагрузка" -> "Low load"
    "Нестабильное соединение" -> "Unstable connection"
    "Временно недоступен" -> "Temporarily unavailable"
    else -> value
}

internal enum class ServerBadge(val label: String) {
    Main("Main"), Stable("Stable"), Testing("Testing"), Offline("Offline")
}
internal data class Server(
    val name: String,
    val description: String,
    val flag: String,
    val latency: Int?,
    val badge: ServerBadge = ServerBadge.Main,
    val rootConfig: String = "",
    val adminOnly: Boolean = false
)

private enum class ConnectionState { Disconnected, Connecting, Connected, Disconnecting }

private val initialServers = listOf(
    Server("Aurora", "Самый быстрый сервер", "FI", 24, ServerBadge.Main),
    Server("Nord", "Стабильное соединение", "SE", 36, ServerBadge.Stable),
    Server("Rhein", "Оптимален для видео", "DE", 48, ServerBadge.Stable),
    Server("Tulip", "Низкая нагрузка", "NL", 57, ServerBadge.Testing),
    Server("Vistula", "Нестабильное соединение", "PL", 140, ServerBadge.Testing),
    Server("Liberty", "Временно недоступен", "US", null, ServerBadge.Offline)
)

private enum class AppScreen { Home, Settings, About, Admin, ConnectDevice, Devices }
private enum class AuthMode { Welcome, Login, Register, Recovery, QuickLogin }

@Composable
fun CaeloApp(themeMode: ThemeMode, onThemeChange: (ThemeMode) -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("caelo_prefs", Context.MODE_PRIVATE) }
    var launchComplete by remember { mutableStateOf(false) }
    var accessGranted by remember { mutableStateOf(prefs.getBoolean("access_granted", false)) }
    var screen by remember { mutableStateOf(AppScreen.Home) }
    var currentRole by remember { mutableStateOf(prefs.getString("user_role", "admin") ?: "admin") }
    var language by remember {
        mutableStateOf(
            runCatching { AppLanguage.valueOf(prefs.getString("app_language", AppLanguage.Russian.name)!!) }
                .getOrDefault(AppLanguage.Russian)
        )
    }
    val servers = remember { mutableStateListOf<Server>().apply { addAll(initialServers) } }
    val liveLatencies = remember {
        mutableStateMapOf<String, Int?>().apply { servers.forEach { put(it.name, it.latency) } }
    }
    val users = remember {
        mutableStateListOf(
            UserAccount(
                "Владелец",
                UserRole.Admin,
                initialServers.map { it.name }.toSet(),
                lastConnectedAt = System.currentTimeMillis() - 12 * 60_000
            ),
            UserAccount(
                "Основной клиент",
                UserRole.User,
                setOf("Aurora", "Nord"),
                lastConnectedAt = System.currentTimeMillis() - 26 * 60 * 60_000
            )
        )
    }
    val devices = remember {
        mutableStateListOf(
            DeviceSession(name = "Android", description = "Сейчас · это устройство", current = true),
            DeviceSession(name = "Windows PC", description = "Москва · 10 августа, 21:42")
        )
    }

    LaunchedEffect("launch_animation") {
        delay(1_800)
        launchComplete = true
    }

    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            servers.forEach { server ->
                liveLatencies[server.name] = when {
                    server.badge == ServerBadge.Offline -> null
                    server.name == "Vistula" && Random.nextInt(100) < 30 -> null
                    server.name == "Vistula" -> Random.nextInt(110, 451)
                    else -> ((liveLatencies[server.name] ?: server.latency ?: 50) + Random.nextInt(-6, 7))
                        .coerceIn(12, 180)
                }
            }
        }
    }

    CompositionLocalProvider(LocalAppLanguage provides language) {
    Surface(Modifier.fillMaxSize(), color = Cloud) {
        AnimatedContent(launchComplete, label = "launch_screen") { ready ->
        if (!ready) {
            LaunchScreen()
        } else {
        AnimatedContent(accessGranted, label = "app_screen") { granted ->
            if (granted) {
                Box(Modifier.fillMaxSize()) {
                    HomeScreen(
                        servers.filter {
                            it.badge != ServerBadge.Offline && (!it.adminOnly || currentRole == "admin")
                        },
                        liveLatencies,
                        onOpenSettings = { screen = AppScreen.Settings }
                    )
                    AnimatedContent(screen, modifier = Modifier.fillMaxSize(), label = "navigation_overlay") { currentScreen ->
                        when (currentScreen) {
                            AppScreen.Home -> Box(Modifier.fillMaxSize())
                            AppScreen.Settings -> SettingsScreen(
                                onBack = { screen = AppScreen.Home },
                                isAdmin = currentRole == "admin",
                                onOpenAbout = { screen = AppScreen.About },
                                onOpenAdmin = { screen = AppScreen.Admin },
                                onConnectDevice = { screen = AppScreen.ConnectDevice },
                                onOpenDevices = { screen = AppScreen.Devices },
                                themeMode = themeMode,
                                onThemeChange = onThemeChange,
                                language = language,
                                onLanguageChange = {
                                    language = it
                                    prefs.edit().putString("app_language", it.name).apply()
                                },
                                onLogout = {
                                    prefs.edit().remove("access_granted").remove("user_role").remove("app_language").apply()
                                    onThemeChange(ThemeMode.System)
                                    language = AppLanguage.Russian
                                    currentRole = "user"
                                    screen = AppScreen.Home
                                    accessGranted = false
                                }
                            )
                            AppScreen.About -> AboutScreen(onBack = { screen = AppScreen.Settings })
                            AppScreen.Admin -> AdminScreen(
                                servers = servers,
                                liveLatencies = liveLatencies,
                                users = users,
                                onBack = { screen = AppScreen.Settings }
                            )
                            AppScreen.ConnectDevice -> ConnectDeviceScreen(
                                onBack = { screen = AppScreen.Settings },
                                onConnected = { device ->
                                    devices.add(device)
                                    screen = AppScreen.Devices
                                }
                            )
                            AppScreen.Devices -> DevicesScreen(
                                devices = devices,
                                onBack = { screen = AppScreen.Settings },
                                onRemove = { devices.remove(it) }
                            )
                        }
                    }
                }
            }
            else AccessScreen(prefs) { role ->
                currentRole = role
                prefs.edit().putString("user_role", currentRole).apply()
                prefs.edit().putBoolean("access_granted", true).apply()
                accessGranted = true
            }
        }
        }
        }
    }
    }
}

@Composable
private fun LaunchScreen() {
    val transition = rememberInfiniteTransition(label = "launch_cloud")
    val scale by transition.animateFloat(
        initialValue = .94f,
        targetValue = 1.04f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "cloud_scale"
    )
    val rotation by transition.animateFloat(
        initialValue = -2.5f,
        targetValue = 2.5f,
        animationSpec = infiniteRepeatable(tween(1_300), RepeatMode.Reverse),
        label = "cloud_rotation"
    )
    Box(
        Modifier.fillMaxSize().background(
            Brush.radialGradient(
                listOf(MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.surfaceVariant, Cloud),
                center = Offset(540f, 760f),
                radius = 1_500f
            )
        ),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Image(
                painter = painterResource(R.drawable.caelo_logo),
                contentDescription = "Caelo",
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(142.dp)
                    .graphicsLayer {
                        scaleX = scale
                        scaleY = scale
                        rotationZ = rotation
                    }
                    .shadow(20.dp, RoundedCornerShape(41.dp))
                    .clip(RoundedCornerShape(41.dp))
            )
            Spacer(Modifier.height(34.dp))
            CircularProgressIndicator(
                modifier = Modifier.size(34.dp),
                color = Mint,
                strokeWidth = 3.dp,
                trackColor = Mint.copy(alpha = .16f)
            )
        }
    }
}

@Composable
private fun AccessScreen(
    prefs: android.content.SharedPreferences,
    onContinue: (String) -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    fun authError(reason: AuthFailure): String = when (reason) {
        AuthFailure.EmptyFields -> l("Заполните все поля", "Complete all fields")
        AuthFailure.PasswordMismatch -> l("Пароли не совпадают", "Passwords do not match")
        AuthFailure.InvalidInvitation -> l("Неверный код приглашения", "Invalid invitation code")
        AuthFailure.InvalidCredentials -> l("Неверный логин или пароль", "Incorrect username or password")
    }
    var mode by remember { mutableStateOf(AuthMode.Welcome) }
    var login by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var repeatPassword by remember { mutableStateOf("") }
    var inviteCode by remember { mutableStateOf("") }
    var recoveryCode by remember { mutableStateOf("") }
    var recoveryPassword by remember { mutableStateOf("") }
    var repeatRecoveryPassword by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var scannerMessage by remember { mutableStateOf<String?>(null) }
    var pendingRole by remember { mutableStateOf("user") }
    val context = LocalContext.current
    val activity = context as? FragmentActivity
    val biometricAvailable = remember(context) {
        BiometricManager.from(context).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
            BiometricManager.BIOMETRIC_SUCCESS
    }

    fun authenticateWithBiometrics(isSetup: Boolean = false, onSuccess: () -> Unit) {
        if (activity == null || !biometricAvailable) {
            error = l("Биометрический вход недоступен на этом устройстве", "Biometric sign-in is unavailable on this device")
            return
        }
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(context),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    onSuccess()
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (errorCode != BiometricPrompt.ERROR_NEGATIVE_BUTTON &&
                        errorCode != BiometricPrompt.ERROR_USER_CANCELED &&
                        errorCode != BiometricPrompt.ERROR_CANCELED
                    ) error = errString.toString()
                }

                override fun onAuthenticationFailed() {
                    error = l("Отпечаток не распознан. Попробуйте ещё раз", "Fingerprint not recognized. Try again")
                }
            }
        )
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(if (isSetup) l("Настройка быстрого входа", "Set up quick sign-in") else l("Вход в Caelo", "Sign in to Caelo"))
            .setSubtitle(if (isSetup) l("Подтвердите отпечаток пальца", "Confirm your fingerprint") else l("Подтвердите личность отпечатком пальца", "Confirm your identity with your fingerprint"))
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
            .setNegativeButtonText(if (isSetup) l("Не сейчас", "Not now") else l("Ввести пароль", "Use password"))
            .build()
        prompt.authenticate(promptInfo)
    }

    fun authenticate() {
        val savedLogin = prefs.getString("account_login", null)
        val savedPassword = prefs.getString("account_password", null)
        when (val result = authenticateAccount(
            login, password, savedLogin, savedPassword, prefs.getString("account_role", "user")
        )) {
            is LoginResult.Success -> {
                if (result.builtInAccount) {
                    prefs.edit()
                        .putString("account_login", BUILT_IN_ADMIN_LOGIN)
                        .putString("account_password", BUILT_IN_ADMIN_PASSWORD)
                        .putString("account_role", result.role)
                        .apply()
                }
                onContinue(result.role)
            }
            is LoginResult.Failure -> error = authError(result.reason)
        }
    }

    fun register() {
        when (val result = validateRegistration(login, password, repeatPassword, inviteCode)) {
            is RegistrationResult.Failure -> error = authError(result.reason)
            is RegistrationResult.Success -> {
                prefs.edit()
                    .putString("account_login", result.login)
                    .putString("account_password", result.password)
                    .putString("account_role", result.role)
                    .putBoolean("biometric_enabled", false)
                    .apply()
                pendingRole = result.role
                error = null
                mode = AuthMode.QuickLogin
            }
        }
    }

    fun resetAuthInputs() {
        login = ""
        password = ""
        repeatPassword = ""
        inviteCode = ""
        recoveryCode = ""
        recoveryPassword = ""
        repeatRecoveryPassword = ""
        error = null
    }

    BackHandler(enabled = mode != AuthMode.Welcome && mode != AuthMode.QuickLogin) {
        resetAuthInputs()
        mode = AuthMode.Welcome
    }

    Box(
        Modifier.fillMaxSize().background(
            Brush.radialGradient(
                listOf(MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.surfaceVariant, Cloud),
                center = androidx.compose.ui.geometry.Offset(240f, 180f),
                radius = 1450f
            )
        )
    ) {
        Column(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (mode != AuthMode.Welcome && mode != AuthMode.QuickLogin) {
                IconButton(
                    onClick = {
                        resetAuthInputs()
                        mode = AuthMode.Welcome
                    },
                    modifier = Modifier.align(Alignment.Start)
                ) {
                    Icon(Icons.Outlined.ArrowBack, l("Назад", "Back"), tint = Ink)
                }
            }
            Spacer(Modifier.weight(if (mode == AuthMode.Welcome) .55f else .18f))
            BrandMark()
            Spacer(Modifier.height(if (mode == AuthMode.Welcome) 32.dp else 20.dp))
            Text(
                when (mode) {
                    AuthMode.Welcome -> l("Добро пожаловать", "Welcome")
                    AuthMode.Login -> l("Вход", "Sign in")
                    AuthMode.Register -> l("Регистрация", "Create account")
                    AuthMode.Recovery -> l("Восстановление доступа", "Restore access")
                    AuthMode.QuickLogin -> l("Быстрый вход", "Quick sign-in")
                },
                style = MaterialTheme.typography.headlineLarge,
                color = Ice
            )
            if (mode == AuthMode.Welcome) {
                Spacer(Modifier.height(14.dp))
                Text(
                    l("Войдите или создайте аккаунт", "Sign in or create an account"),
                    color = Mist,
                    fontSize = 17.sp,
                    textAlign = TextAlign.Center
                )
            }
            Spacer(Modifier.height(24.dp))

            if (mode == AuthMode.Welcome) {
                Button(
                    onClick = { mode = AuthMode.Register },
                    modifier = Modifier.fillMaxWidth().height(64.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Mint)
                ) { Text(l("Регистрация", "Create account"), fontWeight = FontWeight.Bold, fontSize = 19.sp) }
                Spacer(Modifier.height(14.dp))
                OutlinedButton(
                    onClick = { mode = AuthMode.Login },
                    modifier = Modifier.fillMaxWidth().height(64.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink)
                ) { Text(l("Вход", "Sign in"), fontWeight = FontWeight.Bold, fontSize = 19.sp) }
            } else if (mode == AuthMode.QuickLogin) {
                Icon(Icons.Outlined.Fingerprint, null, tint = Mint, modifier = Modifier.size(68.dp))
                Spacer(Modifier.height(18.dp))
                Text(
                    l("Входите быстрее с помощью отпечатка пальца", "Sign in faster with your fingerprint"),
                    color = Ink,
                    fontSize = 20.sp,
                    lineHeight = 27.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    l("Пароль останется запасным способом входа", "Your password remains a backup sign-in method"),
                    color = Mist,
                    fontSize = 16.sp,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(26.dp))
                Button(
                    onClick = {
                        authenticateWithBiometrics(isSetup = true) {
                            prefs.edit().putBoolean("biometric_enabled", true).apply()
                            onContinue(pendingRole)
                        }
                    },
                    enabled = biometricAvailable,
                    modifier = Modifier.fillMaxWidth().height(64.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Mint)
                ) {
                    Icon(Icons.Outlined.Fingerprint, null, modifier = Modifier.size(26.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(l("Включить по отпечатку", "Enable fingerprint sign-in"), fontWeight = FontWeight.Bold, fontSize = 18.sp)
                }
                if (!biometricAvailable) {
                    Spacer(Modifier.height(8.dp))
                    Text(l("На устройстве не настроен отпечаток", "No fingerprint is set up on this device"), color = Mist, fontSize = 15.sp)
                }
                Spacer(Modifier.height(12.dp))
                TextButton(onClick = { onContinue(pendingRole) }) {
                    Text(l("Не сейчас", "Not now"), color = Mist, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                }
            } else if (mode == AuthMode.Recovery) {
                Text(
                    l(
                        "Введите код восстановления, полученный от администратора",
                        "Enter the recovery code provided by your administrator"
                    ),
                    color = Mist,
                    fontSize = 16.sp,
                    lineHeight = 22.sp,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(18.dp))
                AuthField(
                    recoveryCode,
                    { recoveryCode = it.uppercase(); error = null },
                    l("Код восстановления", "Recovery code"),
                    Icons.Outlined.Key
                )
                Spacer(Modifier.height(12.dp))
                AuthField(
                    recoveryPassword,
                    { recoveryPassword = it; error = null },
                    l("Новый пароль", "New password"),
                    Icons.Outlined.Lock,
                    password = true
                )
                Spacer(Modifier.height(12.dp))
                AuthField(
                    repeatRecoveryPassword,
                    { repeatRecoveryPassword = it; error = null },
                    l("Повторите пароль", "Repeat password"),
                    Icons.Outlined.Lock,
                    password = true
                )
                Box(Modifier.fillMaxWidth().height(42.dp), contentAlignment = Alignment.CenterStart) {
                    error?.let {
                        Text(it, color = MaterialTheme.colorScheme.error, fontSize = 16.sp)
                    }
                }
                Button(
                    onClick = {
                        val validationError = if (recoveryCode.isBlank()) AuthFailure.EmptyFields
                            else validatePasswordChange(recoveryPassword, repeatRecoveryPassword)
                        if (validationError != null) {
                            error = authError(validationError)
                        } else {
                                prefs.edit().putString("account_password", recoveryPassword).apply()
                                login = prefs.getString("account_login", "").orEmpty()
                                password = ""
                                recoveryCode = ""
                                recoveryPassword = ""
                                repeatRecoveryPassword = ""
                                error = null
                                mode = AuthMode.Login
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(62.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Mint)
                ) {
                    Text(l("Сменить пароль", "Change password"), fontWeight = FontWeight.Bold, fontSize = 19.sp)
                }
            } else {
                AuthField(login, { login = it; error = null }, l("Логин", "Username"), Icons.Outlined.Person)
                Spacer(Modifier.height(12.dp))
                AuthField(password, { password = it; error = null }, l("Пароль", "Password"), Icons.Outlined.Lock, password = true)
                if (mode == AuthMode.Register) {
                    Spacer(Modifier.height(12.dp))
                    AuthField(repeatPassword, { repeatPassword = it; error = null }, l("Повторите пароль", "Repeat password"), Icons.Outlined.Lock, password = true)
                    Spacer(Modifier.height(12.dp))
                    AuthField(inviteCode, { inviteCode = it.uppercase(); error = null }, l("Код приглашения", "Invitation code"), Icons.Outlined.Key)
                }
                if (mode == AuthMode.Login) {
                    TextButton(
                        onClick = { error = null; mode = AuthMode.Recovery },
                        modifier = Modifier.align(Alignment.End)
                    ) {
                        Text(
                            l("Восстановить доступ", "Restore access"),
                            color = Mint,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
                Box(Modifier.fillMaxWidth().height(42.dp), contentAlignment = Alignment.CenterStart) {
                    error?.let {
                        Text(it, color = MaterialTheme.colorScheme.error, fontSize = 16.sp)
                    }
                }
                Button(
                    onClick = { if (mode == AuthMode.Login) authenticate() else register() },
                    modifier = Modifier.fillMaxWidth().height(62.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Mint)
                ) {
                    Text(if (mode == AuthMode.Login) l("Войти", "Sign in") else l("Зарегистрироваться", "Create account"), fontWeight = FontWeight.Bold, fontSize = 19.sp)
                }
                if (mode == AuthMode.Login) {
                    Spacer(Modifier.height(12.dp))
                    OutlinedButton(
                        onClick = {
                            authenticateWithBiometrics(isSetup = false) {
                                prefs.edit().putBoolean("biometric_enabled", true).apply()
                                onContinue(prefs.getString("account_role", "user") ?: "user")
                            }
                        },
                        modifier = Modifier.fillMaxWidth().height(62.dp),
                        enabled = biometricAvailable,
                        shape = RoundedCornerShape(20.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink)
                    ) {
                        Icon(Icons.Outlined.Fingerprint, null, modifier = Modifier.size(27.dp))
                        Spacer(Modifier.width(10.dp))
                        Text(
                            l("Войти с Passkey", "Sign in with Passkey"),
                            fontWeight = FontWeight.Bold,
                            fontSize = 18.sp
                        )
                    }
                    if (!biometricAvailable) {
                        Text(
                            l("Добавьте отпечаток в настройках телефона", "Add a fingerprint in your phone settings"),
                            color = Mist,
                            fontSize = 15.sp,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                    Spacer(Modifier.height(10.dp))
                    TextButton(
                        onClick = {
                            launchQrScanner(
                                context,
                                onSuccess = { value ->
                                    if (isCaeloAccountLink(value)) {
                                        onContinue(prefs.getString("account_role", "user") ?: "user")
                                    } else {
                                        error = l("Это не QR-код Caelo", "This is not a Caelo QR code")
                                    }
                                },
                                onError = {
                                    scannerMessage = l(
                                        "Не удалось запустить сканер. Проверьте интернет и обновление сервисов Google Play.",
                                        "Could not start the scanner. Check your internet connection and Google Play services updates."
                                    )
                                }
                            )
                        },
                        modifier = Modifier.fillMaxWidth().height(52.dp)
                    ) {
                        Icon(Icons.Outlined.QrCodeScanner, null, tint = Mint, modifier = Modifier.size(25.dp))
                        Spacer(Modifier.width(9.dp))
                        Text(
                            l("Войти по QR-коду", "Sign in with QR code"),
                            color = Mint,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.height(18.dp))
        }
        scannerMessage?.let { message ->
            Dialog(
                onDismissRequest = { scannerMessage = null },
                properties = DialogProperties(usePlatformDefaultWidth = false)
            ) {
                Surface(
                    Modifier.fillMaxWidth(.90f),
                    shape = RoundedCornerShape(28.dp),
                    color = Panel,
                    tonalElevation = 6.dp
                ) {
                    Column(Modifier.padding(24.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.QrCodeScanner, null, tint = Mint, modifier = Modifier.size(31.dp))
                            Spacer(Modifier.width(12.dp))
                            Text(l("Сканер QR-кода", "QR code scanner"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.height(16.dp))
                        Text(message, color = Mist, fontSize = 17.sp, lineHeight = 24.sp)
                        Spacer(Modifier.height(22.dp))
                        OutlinedButton(
                            onClick = { scannerMessage = null },
                            modifier = Modifier.fillMaxWidth().height(52.dp),
                            shape = RoundedCornerShape(14.dp),
                            border = androidx.compose.foundation.BorderStroke(1.dp, Mint)
                        ) {
                            Text(l("Понятно", "Got it"), color = Ink, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AuthField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    password: Boolean = false
) {
    var passwordVisible by remember { mutableStateOf(false) }
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        label = {
            Text(
                label,
                fontSize = 16.sp
            )
        },
        leadingIcon = { Icon(icon, null) },
        trailingIcon = if (password) {
            {
                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                    Icon(
                        if (passwordVisible) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                        if (passwordVisible) "Скрыть пароль" else "Показать пароль"
                    )
                }
            }
        } else null,
        singleLine = true,
        visualTransformation = if (password && !passwordVisible) PasswordVisualTransformation()
            else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (password) KeyboardType.Password else KeyboardType.Text),
        shape = RoundedCornerShape(18.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Mint,
            focusedContainerColor = MaterialTheme.colorScheme.surface,
            unfocusedContainerColor = MaterialTheme.colorScheme.surface,
            disabledContainerColor = MaterialTheme.colorScheme.surface,
            errorContainerColor = MaterialTheme.colorScheme.surface
        )
    )
}

@Composable
private fun BrandMark() {
    Image(
        painter = painterResource(R.drawable.caelo_logo),
        contentDescription = "Caelo",
        contentScale = ContentScale.Crop,
        modifier = Modifier.size(108.dp).shadow(14.dp, RoundedCornerShape(31.dp)).clip(RoundedCornerShape(31.dp))
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScreen(
    servers: List<Server>,
    liveLatencies: androidx.compose.runtime.snapshots.SnapshotStateMap<String, Int?>,
    onOpenSettings: () -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val sortedServers = sortServers(servers, liveLatencies)
    var selected by remember(servers) { mutableStateOf(servers.first()) }
    var connectionState by remember { mutableStateOf(ConnectionState.Disconnected) }
    var showOfflineWarning by remember { mutableStateOf(false) }
    var offlineConnectionAttempt by remember { mutableStateOf(false) }
    var showConnectionLost by remember { mutableStateOf(false) }
    var connectionLostNoticeVersion by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val bottomSheetState = rememberStandardBottomSheetState(
        initialValue = SheetValue.PartiallyExpanded,
        skipHiddenState = true
    )
    val scaffoldState = rememberBottomSheetScaffoldState(bottomSheetState = bottomSheetState)
    val sheetOutlineColor = MaterialTheme.colorScheme.outline.copy(alpha = .42f)

    LaunchedEffect(connectionState, selected.name, liveLatencies[selected.name]) {
        if (connectionState == ConnectionState.Connected && liveLatencies[selected.name] == null) {
            connectionLostNoticeVersion++
            showConnectionLost = true
            connectionState = ConnectionState.Connecting
        }
    }

    LaunchedEffect(connectionLostNoticeVersion) {
        if (connectionLostNoticeVersion > 0) {
            delay(4_000)
            showConnectionLost = false
        }
    }

    LaunchedEffect(connectionState) {
        if (connectionState != ConnectionState.Disconnected) bottomSheetState.partialExpand()
        when (connectionState) {
            ConnectionState.Connecting -> {
                delay(
                    when (selected.badge) {
                        ServerBadge.Main -> 3_000
                        ServerBadge.Stable -> 7_000
                        ServerBadge.Testing -> 12_000
                        ServerBadge.Offline -> 30_000
                    }
                )
                if (offlineConnectionAttempt) {
                    connectionState = ConnectionState.Disconnected
                    offlineConnectionAttempt = false
                    showOfflineWarning = true
                } else {
                    while (liveLatencies[selected.name] == null) delay(1_000)
                    connectionState = ConnectionState.Connected
                }
            }
            ConnectionState.Disconnecting -> {
                delay(1_200)
                connectionState = ConnectionState.Disconnected
            }
            else -> Unit
        }
    }

    BottomSheetScaffold(
        scaffoldState = scaffoldState,
        sheetPeekHeight = 152.dp,
        sheetShape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp),
        sheetContainerColor = Panel,
        sheetContentColor = Ink,
        sheetDragHandle = null,
        sheetSwipeEnabled = connectionState == ConnectionState.Disconnected,
        sheetContent = {
            Box(Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth()) {
            ServerBar(
                selected.copy(latency = liveLatencies[selected.name]),
                serverSelectionEnabled = connectionState == ConnectionState.Disconnected,
                onSelectServer = { scope.launch { bottomSheetState.expand() } }
            )
            Text(l("Выберите сервер", "Choose a server"), fontSize = 25.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 22.dp, vertical = 8.dp))
            Text(l("Автоматически предложим самый быстрый", "We’ll suggest the fastest one"), color = Mist, fontSize = 16.sp, modifier = Modifier.padding(horizontal = 22.dp))
            LazyColumn(
                modifier = Modifier.fillMaxWidth().heightIn(max = 500.dp),
                contentPadding = PaddingValues(horizontal = 4.dp, vertical = 14.dp)
            ) {
                items(sortedServers, key = { it.name }) { server ->
                    ServerRow(
                        server.copy(latency = liveLatencies[server.name]),
                        server.name == selected.name
                    ) {
                        selected = server
                        scope.launch { bottomSheetState.partialExpand() }
                    }
                }
            }
            }
            Canvas(Modifier.fillMaxWidth().height(31.dp)) {
                val radius = 30.dp.toPx()
                val outline = Path().apply {
                    moveTo(0f, radius)
                    quadraticBezierTo(0f, 0f, radius, 0f)
                    lineTo(size.width - radius, 0f)
                    quadraticBezierTo(size.width, 0f, size.width, radius)
                }
                drawPath(outline, color = sheetOutlineColor, style = Stroke(width = 1.dp.toPx()))
            }
            }
        }
    ) {
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(listOf(Cloud, MaterialTheme.colorScheme.surfaceVariant, Cloud))
            )
        ) {
            IconButton(
                onClick = onOpenSettings,
                modifier = Modifier.statusBarsPadding().padding(top = 10.dp, end = 14.dp)
                    .align(Alignment.TopEnd).size(48.dp)
                    .clip(CircleShape).background(Panel.copy(alpha = .78f))
            ) {
                Icon(Icons.Outlined.Settings, l("Настройки", "Settings"), tint = Ink, modifier = Modifier.size(25.dp))
            }
            Box(
                modifier = Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 20.dp, vertical = 28.dp),
                contentAlignment = Alignment.Center
            ) {
                AnimatedVisibility(
                    visible = showConnectionLost,
                    modifier = Modifier.align(Alignment.Center).offset(y = (-180).dp),
                    enter = fadeIn(tween(180)) + scaleIn(tween(180), initialScale = .94f),
                    exit = fadeOut(tween(220)) + scaleOut(tween(220), targetScale = .96f)
                ) {
                    Row(
                        modifier = Modifier.shadow(8.dp, RoundedCornerShape(18.dp))
                            .clip(RoundedCornerShape(18.dp))
                            .background(Color(0xFFE05252))
                            .padding(horizontal = 18.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Outlined.WifiOff, null, tint = Color.White, modifier = Modifier.size(23.dp))
                        Spacer(Modifier.width(9.dp))
                        Text(
                            l("Пропало соединение", "Connection lost"),
                            color = Color.White,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
                ConnectButton(connectionState) {
                    if (selected.badge == ServerBadge.Offline && connectionState == ConnectionState.Disconnected) {
                        offlineConnectionAttempt = true
                        connectionState = ConnectionState.Connecting
                    } else {
                        offlineConnectionAttempt = false
                        connectionState = when (connectionState) {
                            ConnectionState.Disconnected -> ConnectionState.Connecting
                            ConnectionState.Connecting -> ConnectionState.Disconnected
                            ConnectionState.Connected -> ConnectionState.Disconnecting
                            ConnectionState.Disconnecting -> ConnectionState.Disconnecting
                        }
                    }
                }
            }
        }
    }

    if (showOfflineWarning) {
        Dialog(
            onDismissRequest = { showOfflineWarning = false },
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
                        Icon(Icons.Outlined.CloudOff, null, tint = Color(0xFFE05252), modifier = Modifier.size(32.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(l("Не удалось подключиться", "Unable to connect"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(18.dp))
                    Text(
                        l("Сервер не отвечает. Проверьте подключение к интернету или выберите другой сервер.", "The server is not responding. Check your internet connection or choose another server."),
                        color = Mist,
                        fontSize = 18.sp,
                        lineHeight = 25.sp
                    )
                    Spacer(Modifier.height(24.dp))
                    Button(
                        onClick = {
                            showOfflineWarning = false
                            scope.launch { bottomSheetState.expand() }
                        },
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Mint)
                    ) { Text(l("Выбрать другой", "Choose another"), fontSize = 17.sp, fontWeight = FontWeight.Bold) }
                }
            }
        }
    }
}

@Composable
private fun ConnectButton(state: ConnectionState, onClick: () -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val connected = state == ConnectionState.Connected
    val inProgress = state == ConnectionState.Connecting || state == ConnectionState.Disconnecting
    val transition = rememberInfiniteTransition(label = "pulse")
    val pulse by transition.animateFloat(1f, if (connected) 1.08f else 1f, infiniteRepeatable(tween(1800), RepeatMode.Reverse), label = "pulse_value")
    val color by animateColorAsState(if (connected || inProgress) Mint else Cyan, label = "button_color")
    val contentColor by animateColorAsState(if (connected) Color.White else Ink, label = "button_content")
    Box(contentAlignment = Alignment.Center) {
        if (connected) Box(
            Modifier.size(282.dp).graphicsLayer { scaleX = pulse; scaleY = pulse }
                .alpha(.18f).clip(CircleShape).background(Mint)
        )
        Box(
            Modifier.size(252.dp).shadow(
                if (connected) 22.dp else 10.dp,
                CircleShape,
                ambientColor = color.copy(alpha = if (connected) .34f else .12f),
                spotColor = color.copy(alpha = if (connected) .28f else .10f)
            )
                .clip(CircleShape)
                .background(
                    if (connected) {
                        Brush.radialGradient(listOf(Color(0xFF43BC94), Color(0xFF238966)))
                    } else if (inProgress) {
                        Brush.radialGradient(listOf(MaterialTheme.colorScheme.surfaceVariant, MaterialTheme.colorScheme.surface))
                    } else {
                        Brush.radialGradient(listOf(MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.surfaceVariant))
                    }
                )
                .border(if (connected || inProgress) 0.dp else 3.dp, color.copy(alpha = .72f), CircleShape)
                .clickable(enabled = state != ConnectionState.Disconnecting, onClick = onClick),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Outlined.PowerSettingsNew,
                    null,
                    tint = if (connected) Color.White else color,
                    modifier = Modifier.size(72.dp)
                )
                Spacer(Modifier.height(18.dp))
                Text(
                    when (state) {
                        ConnectionState.Disconnected -> l("Подключить", "Connect")
                        ConnectionState.Connecting -> l("Подключение…", "Connecting…")
                        ConnectionState.Connected -> l("Подключено", "Connected")
                        ConnectionState.Disconnecting -> l("Отключение…", "Disconnecting…")
                    },
                    color = contentColor,
                    fontWeight = FontWeight.Bold,
                    fontSize = 26.sp
                )
            }
        }
        if (inProgress) {
            CircularProgressIndicator(
                modifier = Modifier.size(252.dp),
                color = Mint,
                trackColor = Mint.copy(alpha = .14f),
                strokeWidth = 6.dp
            )
        }
    }
}

@Composable
private fun ServerBar(
    server: Server,
    serverSelectionEnabled: Boolean,
    onSelectServer: () -> Unit
) {
    val latency = server.latency
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    Column(
        Modifier.fillMaxWidth()
            .navigationBarsPadding()
            .padding(start = 4.dp, end = 26.dp, top = 12.dp, bottom = 18.dp)
    ) {
        Box(
            Modifier.width(34.dp).height(4.dp).clip(CircleShape).background(Color(0xFF9AB8AF))
                .align(Alignment.CenterHorizontally)
        )
        Spacer(Modifier.height(11.dp))
        Text(
            l("Текущий сервер", "Current server"),
            color = Mist,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            letterSpacing = .2.sp,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        )
        Spacer(Modifier.height(11.dp))
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                .clickable(enabled = serverSelectionEnabled, onClick = onSelectServer)
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            FlagBadge(server.flag, width = 66, height = 44)
            Spacer(Modifier.width(7.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(server.name, color = Ink, fontWeight = FontWeight.Bold, fontSize = 23.sp, lineHeight = 29.sp, maxLines = 1)
                    Spacer(Modifier.width(5.dp))
                    ServerStatusBadge(server.badge)
                    Spacer(Modifier.weight(1f))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        if (latency == null) l("Нет связи", "No connection") else "$latency ${l("мс", "ms")}",
                        color = if (latency == null) Color(0xFFE05252) else if (latency < 60) Mint else Cyan,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 16.sp
                    )
                    Spacer(Modifier.width(7.dp))
                    Icon(
                        if (serverSelectionEnabled) Icons.Outlined.KeyboardArrowDown else Icons.Outlined.Lock,
                        if (serverSelectionEnabled) l("Выбрать сервер", "Choose server") else l("Сервер заблокирован при подключении", "Server is locked while connected"),
                        tint = Mist,
                        modifier = Modifier.size(26.dp)
                    )
                }
                Text(serverDescription(language, server.description), color = Mist, fontSize = 17.sp, lineHeight = 23.sp, maxLines = 3, modifier = Modifier.fillMaxWidth())
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun ServerRow(server: Server, selected: Boolean, onClick: () -> Unit) {
    val latency = server.latency
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(if (selected) Mint.copy(alpha = .24f) else Color.Transparent)
            .border(
                width = if (selected) 1.5.dp else 0.dp,
                color = if (selected) Mint.copy(alpha = .72f) else Color.Transparent,
                shape = RoundedCornerShape(18.dp)
            )
            .clickable(onClick = onClick)
            .padding(start = 6.dp, top = 12.dp, end = 14.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        FlagBadge(server.flag, width = 66, height = 44); Spacer(Modifier.width(5.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(server.name, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, maxLines = 1)
                Spacer(Modifier.width(5.dp))
                ServerStatusBadge(server.badge)
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.width(7.dp))
                Text(
                    if (latency == null) l("Нет связи", "No connection") else "$latency ${l("мс", "ms")}",
                    color = if (latency == null) Color(0xFFE05252) else if (latency < 60) Mint else Mist,
                    fontSize = 15.sp
                )
            }
            Text(serverDescription(language, server.description), color = Mist, fontSize = 16.sp, lineHeight = 22.sp, maxLines = 3, modifier = Modifier.fillMaxWidth())
        }
        Spacer(Modifier.width(10.dp))
        if (selected) {
            Icon(Icons.Outlined.CheckCircle, l("Выбран", "Selected"), tint = Mint, modifier = Modifier.size(27.dp))
        } else {
            Spacer(Modifier.width(27.dp))
        }
    }
}

@Composable
internal fun ServerStatusBadge(badge: ServerBadge) {
    val color = when (badge) {
        ServerBadge.Main -> Color(0xFF3B82F6)
        ServerBadge.Stable -> Color(0xFF2FA982)
        ServerBadge.Testing -> Color(0xFFE5A819)
        ServerBadge.Offline -> Color(0xFFE05252)
    }
    Text(
        badge.label,
        color = color,
        fontSize = 13.sp,
        fontWeight = FontWeight.Bold,
        maxLines = 1,
        modifier = Modifier.clip(RoundedCornerShape(7.dp))
            .background(color.copy(alpha = .15f))
            .border(1.dp, color.copy(alpha = .48f), RoundedCornerShape(7.dp))
            .padding(horizontal = 5.dp, vertical = 2.dp)
    )
}

@Composable
internal fun FlagBadge(code: String, width: Int = 54, height: Int = 34) {
    val emoji = when (code) {
        "FI" -> "🇫🇮"
        "SE" -> "🇸🇪"
        "DE" -> "🇩🇪"
        "NL" -> "🇳🇱"
        "PL" -> "🇵🇱"
        "US" -> "🇺🇸"
        else -> code
    }
    Box(
        Modifier.size(width = width.dp, height = height.dp)
            .clip(RoundedCornerShape(2.dp)),
        contentAlignment = Alignment.Center
    ) {
        Text(emoji, fontSize = (height * .82f).sp, maxLines = 1)
    }
}
