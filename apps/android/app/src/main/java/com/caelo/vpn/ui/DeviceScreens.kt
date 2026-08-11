package com.caelo.vpn.ui

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.foundation.Image
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.caelo.vpn.ui.theme.*
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate.InstallState.STATE_CANCELED
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate.InstallState.STATE_COMPLETED
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate.InstallState.STATE_FAILED
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import java.util.UUID

internal data class DeviceSession(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val description: String,
    val current: Boolean = false
)

internal fun launchQrScanner(context: Context, onSuccess: (String) -> Unit, onError: (String) -> Unit) {
    val options = GmsBarcodeScannerOptions.Builder()
        .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
        .enableAutoZoom()
        .build()
    val scanner = GmsBarcodeScanning.getClient(context, options)
    val moduleClient = ModuleInstall.getClient(context)
    var scannerStarted = false
    fun startScanner() {
        if (scannerStarted) return
        scannerStarted = true
        scanner.startScan()
            .addOnSuccessListener { barcode ->
                barcode.rawValue?.let(onSuccess) ?: onError("empty_qr")
            }
            .addOnFailureListener { onError("scan_failed") }
    }
    moduleClient.areModulesAvailable(scanner)
        .addOnSuccessListener { availability ->
            if (availability.areModulesAvailable()) {
                startScanner()
            } else {
                lateinit var listener: InstallStatusListener
                listener = InstallStatusListener { update ->
                    when (update.installState) {
                        STATE_COMPLETED -> {
                            moduleClient.unregisterListener(listener)
                            startScanner()
                        }
                        STATE_CANCELED, STATE_FAILED -> {
                            moduleClient.unregisterListener(listener)
                            onError("module_failed")
                        }
                    }
                }
                val request = ModuleInstallRequest.newBuilder()
                    .addApi(scanner)
                    .setListener(listener)
                    .build()
                moduleClient.installModules(request)
                    .addOnSuccessListener { response ->
                        if (response.areModulesAlreadyInstalled()) {
                            moduleClient.unregisterListener(listener)
                            startScanner()
                        }
                    }
                    .addOnFailureListener {
                        moduleClient.unregisterListener(listener)
                        onError("module_failed")
                    }
            }
        }
        .addOnFailureListener { onError("module_failed") }
}

private fun qrBitmap(value: String, size: Int = 720): Bitmap {
    val matrix = QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, size, size)
    return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { bitmap ->
        for (y in 0 until size) for (x in 0 until size) {
            bitmap.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.rgb(7, 63, 60) else android.graphics.Color.WHITE)
        }
    }
}

@Composable
private fun DeviceHeader(title: String, onBack: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(76.dp).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = onBack, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Outlined.ArrowBack, null, tint = Ink, modifier = Modifier.size(28.dp))
        }
        Spacer(Modifier.width(4.dp))
        Text(title, color = Ink, fontSize = 27.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
internal fun ConnectDeviceScreen(onBack: () -> Unit, onConnected: (DeviceSession) -> Unit) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val context = androidx.compose.ui.platform.LocalContext.current
    val prefs = remember { context.getSharedPreferences("caelo_prefs", Context.MODE_PRIVATE) }
    val token = remember { "caelo://account/link/${UUID.randomUUID()}?user=${prefs.getString("account_login", "user")}" }
    val qr = remember(token) { qrBitmap(token) }
    var message by remember { mutableStateOf<String?>(null) }

    Column(Modifier.fillMaxSize().background(Cloud).statusBarsPadding().navigationBarsPadding()) {
        DeviceHeader(l("Подключить устройство", "Connect device"), onBack)
        Column(
            Modifier.fillMaxSize().padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                l("Покажите этот QR-код другому устройству", "Show this QR code to another device"),
                color = Ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(8.dp))
            Text(
                l("Код одноразовый и действует 5 минут", "The code is single-use and valid for 5 minutes"),
                color = Mist, fontSize = 16.sp, textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(22.dp))
            Surface(shape = RoundedCornerShape(26.dp), color = Color.White, shadowElevation = 3.dp) {
                Image(qr.asImageBitmap(), null, modifier = Modifier.padding(16.dp).size(248.dp))
            }
            Spacer(Modifier.height(26.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                HorizontalDivider(Modifier.weight(1f), color = MaterialTheme.colorScheme.outline.copy(alpha = .25f))
                Text(l("или", "or"), color = Mist, fontSize = 16.sp, modifier = Modifier.padding(horizontal = 14.dp))
                HorizontalDivider(Modifier.weight(1f), color = MaterialTheme.colorScheme.outline.copy(alpha = .25f))
            }
            Spacer(Modifier.height(22.dp))
            OutlinedButton(
                onClick = {
                    launchQrScanner(context, {
                        onConnected(DeviceSession(name = l("Новое устройство", "New device"), description = l("Подключено по QR только что", "Connected by QR just now")))
                        message = l("Устройство подключено", "Device connected")
                    }, {
                        message = l(
                            "Не удалось запустить сканер. Проверьте интернет и сервисы Google Play.",
                            "Could not start the scanner. Check your internet connection and Google Play services."
                        )
                    })
                },
                modifier = Modifier.fillMaxWidth().height(62.dp),
                shape = RoundedCornerShape(18.dp),
                border = androidx.compose.foundation.BorderStroke(1.5.dp, Mint)
            ) {
                Icon(Icons.Outlined.QrCodeScanner, null, tint = Mint, modifier = Modifier.size(27.dp))
                Spacer(Modifier.width(10.dp))
                Text(l("Сканировать QR-код", "Scan QR code"), color = Ink, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
            Box(Modifier.fillMaxWidth().height(54.dp), contentAlignment = Alignment.Center) {
                message?.let { Text(it, color = Mint, fontSize = 16.sp, textAlign = TextAlign.Center) }
            }
        }
    }
}

@Composable
internal fun DevicesScreen(
    devices: List<DeviceSession>,
    onBack: () -> Unit,
    onRemove: (DeviceSession) -> Unit
) {
    val language = LocalAppLanguage.current
    fun l(ru: String, en: String) = uiText(language, ru, en)
    val context = androidx.compose.ui.platform.LocalContext.current
    val prefs = remember { context.getSharedPreferences("caelo_prefs", Context.MODE_PRIVATE) }
    var selected by remember { mutableStateOf<DeviceSession?>(null) }

    Column(Modifier.fillMaxSize().background(Cloud).statusBarsPadding().navigationBarsPadding()) {
        DeviceHeader(l("Устройства", "Devices"), onBack)
        Text(
            l("Активные сеансы аккаунта", "Active account sessions"),
            color = Mist, fontSize = 16.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp)
        )
        LazyColumn(
            Modifier.fillMaxSize().padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(start = 0.dp, top = 8.dp, end = 0.dp, bottom = 24.dp)
        ) {
            items(devices, key = { it.id }) { device ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Panel)
                        .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = .18f), RoundedCornerShape(20.dp))
                        .padding(15.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(Modifier.size(48.dp).clip(CircleShape).background(Mint.copy(alpha = .14f)), contentAlignment = Alignment.Center) {
                        Icon(if (device.current) Icons.Outlined.PhoneAndroid else Icons.Outlined.Computer, null, tint = Mint, modifier = Modifier.size(27.dp))
                    }
                    Spacer(Modifier.width(13.dp))
                    Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(device.name, color = Ink, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                            if (device.current) {
                                Spacer(Modifier.width(8.dp))
                                Text(l("Это устройство", "This device"), color = Mint, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                        Spacer(Modifier.height(3.dp))
                        Text(device.description, color = Mist, fontSize = 14.sp)
                    }
                    if (!device.current) IconButton(onClick = { selected = device }) {
                        Icon(Icons.Outlined.Logout, l("Завершить сеанс", "Sign out"), tint = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }

    selected?.let { device ->
        var password by remember(device.id) { mutableStateOf("") }
        var error by remember(device.id) { mutableStateOf<String?>(null) }
        Dialog(onDismissRequest = { selected = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Surface(Modifier.fillMaxWidth(.92f), shape = RoundedCornerShape(28.dp), color = Panel, tonalElevation = 6.dp) {
                Column(Modifier.padding(24.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Logout, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(31.dp))
                        Spacer(Modifier.width(12.dp))
                        Text(l("Отключить устройство?", "Disconnect device?"), color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(12.dp))
                    Text(device.name, color = Mist, fontSize = 17.sp)
                    Spacer(Modifier.height(18.dp))
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it; error = null },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(l("Пароль аккаунта", "Account password")) },
                        leadingIcon = { Icon(Icons.Outlined.Lock, null) },
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                        shape = RoundedCornerShape(16.dp)
                    )
                    Box(Modifier.fillMaxWidth().height(42.dp), contentAlignment = Alignment.CenterStart) {
                        error?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 15.sp) }
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(onClick = { selected = null }, Modifier.weight(1f).height(52.dp), shape = RoundedCornerShape(14.dp)) {
                            Text(l("Отмена", "Cancel"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Button(
                            onClick = {
                                if (password == prefs.getString("account_password", null)) {
                                    onRemove(device); selected = null
                                } else error = l("Неверный пароль", "Incorrect password")
                            },
                            modifier = Modifier.weight(1f).height(52.dp),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                        ) { Text(l("Отключить", "Disconnect"), fontSize = 16.sp, fontWeight = FontWeight.Bold) }
                    }
                }
            }
        }
    }
}
