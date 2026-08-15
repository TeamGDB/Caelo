package team.gdb.caelo

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands a downloaded update to the system installer.
 *
 * Only that. The file was fetched and its signature checked in Dart before this
 * is called, and the order is not an implementation detail: a file given to the
 * installer is a file that may already be running, so nothing may reach here
 * that has not been proven ours.
 *
 * Android will refuse it anyway if it was signed with a different key than the
 * installed copy — that is the platform's own protection and it is welcome, but
 * it arrives as an unhelpful error after the download, which is why we check
 * first and say something useful.
 */
class Installer(private val context: Context) {
    companion object {
        const val CHANNEL = "team.gdb.caelo/installer"
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Since Android 8 the permission is per-app and granted in Settings
            // rather than at install time, so it has to be asked about rather
            // than declared and assumed.
            "canInstall" -> result.success(context.packageManager.canRequestPackageInstalls())

            "requestPermission" -> {
                // Opens the one screen that grants it. Sending someone to the
                // top of Settings and describing where to go from there is how
                // people give up.
                val intent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.success(null)
            }

            "install" -> {
                val path = call.arguments as? String
                if (path == null) {
                    result.error("install", "no file", null)
                    return
                }

                val file = File(path)
                if (!file.exists()) {
                    result.error("install", "the download is no longer there", null)
                    return
                }

                try {
                    // A content:// URI rather than file://, which Android has
                    // refused to hand to another process since 7.0. The read
                    // permission is granted to whoever the installer turns out
                    // to be, for this URI only, and expires with the task.
                    val uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.updates",
                        file,
                    )
                    val intent = Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("install", error.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }
}
