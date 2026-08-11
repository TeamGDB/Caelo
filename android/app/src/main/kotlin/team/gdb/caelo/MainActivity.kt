package team.gdb.caelo

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The platform half of the Android tunnel.
 *
 * It does the things Dart cannot: ask the user for VPN permission, start the
 * service, obtain a tun descriptor, and exclude the tunnel's own sockets from
 * its routing. The descriptor then goes to Dart, which hands it to the Go core.
 *
 * The tunnel itself lives in the core. Nothing in this file knows what
 * AmneziaWG is, and it should stay that way: two implementations of the same
 * decision eventually disagree, and the one written in Kotlin is the one nobody
 * tests.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "team.gdb.caelo/vpn"
        private const val REQUEST_PREPARE = 8801

        @Volatile
        private var channel: MethodChannel? = null

        /**
         * Tells Dart the system took the tunnel away. Without this the app goes
         * on showing a connection that stopped carrying traffic some time ago.
         */
        fun notifyRevoked() {
            channel?.let { active ->
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    active.invokeMethod("revoked", null)
                }
            }
        }
    }

    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val methods = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methods
        methods.setMethodCallHandler { call, result -> handle(call, result) }
    }

    override fun onDestroy() {
        channel = null
        super.onDestroy()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Returns true when permission is already granted. Otherwise the
            // system's own consent dialog is shown and the answer arrives in
            // onActivityResult — permission is the user's to give, and it is
            // deliberately not something the app can grant itself.
            "prepare" -> {
                val intent = VpnService.prepare(this)
                if (intent == null) {
                    result.success(true)
                    return
                }
                if (pendingPermission != null) {
                    result.error("busy", "a permission request is already open", null)
                    return
                }
                pendingPermission = result
                startActivityForResult(intent, REQUEST_PREPARE)
            }

            "establish" -> {
                try {
                    startService(Intent(this, CaeloVpnService::class.java))

                    val service = awaitService()
                        ?: return result.error("unavailable", "the tunnel service did not start", null)

                    val fd = service.establish(
                        addresses = call.argument<List<String>>("addresses").orEmpty(),
                        routes = call.argument<List<String>>("routes").orEmpty(),
                        dns = call.argument<List<String>>("dns").orEmpty(),
                        mtu = call.argument<Int>("mtu") ?: 1420,
                    )
                    result.success(fd)
                } catch (error: Exception) {
                    result.error("establish", error.message, null)
                }
            }

            // Both descriptors are offered; either may be absent on a device
            // without that address family, and that is not a failure.
            "protect" -> {
                val service = CaeloVpnService.current()
                    ?: return result.error("unavailable", "no tunnel service is running", null)

                val fds = call.arguments as? List<*> ?: emptyList<Any>()
                val protectedAny = fds
                    .mapNotNull { it as? Int }
                    .filter { it >= 0 }
                    .map { service.protectSocket(it) }
                    .any { it }

                if (protectedAny) result.success(true)
                else result.error("protect", "no socket could be excluded from the tunnel", null)
            }

            "stop" -> {
                startService(
                    Intent(this, CaeloVpnService::class.java)
                        .setAction(CaeloVpnService.ACTION_STOP)
                )
                result.success(null)
            }

            "isRunning" -> result.success(CaeloVpnService.running)

            else -> result.notImplemented()
        }
    }

    /**
     * Waits briefly for the service to come up.
     *
     * startService is asynchronous, so the instance is not there the moment it
     * returns. Polling is unlovely, and it is a great deal less machinery than
     * a binding for a service this activity already owns the lifetime of.
     */
    private fun awaitService(): CaeloVpnService? {
        repeat(40) {
            CaeloVpnService.current()?.let { return it }
            Thread.sleep(25)
        }
        return CaeloVpnService.current()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PREPARE) {
            val waiting = pendingPermission
            pendingPermission = null
            waiting?.success(resultCode == Activity.RESULT_OK)
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    @Suppress("unused")
    private fun apiAtLeast(level: Int) = Build.VERSION.SDK_INT >= level
}
