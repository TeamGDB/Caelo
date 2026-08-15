package team.gdb.caelo

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.net.VpnService
import android.os.Build
import android.util.Log
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
        private const val TAG = "CaeloVpn"
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

        // Its own channel and its own object: handing a downloaded file to the
        // system installer has nothing to do with running a tunnel, and the
        // tunnel's handler is already the longest thing in this file.
        val installer = Installer(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, Installer.CHANNEL)
            .setMethodCallHandler { call, result -> installer.handle(call, result) }
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

            "establish" -> establish(call, result)

            // Advisory, and never fatal. Either descriptor may be absent on a
            // device without that address family, and protect can refuse for
            // reasons that do not stop the tunnel working -- the app already
            // excludes itself from its own routes, which is what actually
            // keeps the encrypted packets out of the tunnel they belong to.
            // The reference Android client ignores this result entirely.
            "protect" -> {
                val service = CaeloVpnService.current()
                val protectedCount = (call.arguments as? List<*> ?: emptyList<Any>())
                    .mapNotNull { it as? Int }
                    .filter { it >= 0 }
                    .count { service?.protectSocket(it) == true }

                if (service == null || protectedCount == 0) {
                    Log.w(TAG, "no tunnel socket was excluded from the tunnel's own routes")
                }
                result.success(protectedCount)
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
     * Starts the service and asks it for a descriptor once it is actually
     * there.
     *
     * The answer arrives through a binding rather than by waiting for one. A
     * service is created on the main thread, which is the thread this method
     * runs on, so blocking here to wait for it is waiting for something that
     * can only happen once this returns -- the service could never appear, and
     * every attempt reported that the service had failed to start.
     */
    private fun establish(call: MethodCall, result: MethodChannel.Result) {
        val intent = Intent(this, CaeloVpnService::class.java)
        startService(intent)

        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                // Unbound immediately: startService keeps the service alive, and
                // a binding held by an activity would take the tunnel down with
                // the screen.
                try {
                    val service = (binder as? CaeloVpnService.LocalBinder)?.service
                        ?: throw IllegalStateException("the tunnel service did not bind")

                    result.success(
                        service.establish(
                            addresses = call.argument<List<String>>("addresses").orEmpty(),
                            routes = call.argument<List<String>>("routes").orEmpty(),
                            dns = call.argument<List<String>>("dns").orEmpty(),
                            mtu = call.argument<Int>("mtu") ?: 1420,
                        )
                    )
                } catch (error: Exception) {
                    Log.e(TAG, "establish failed", error)
                    result.error("establish", error.message ?: error.toString(), null)
                } finally {
                    runCatching { unbindService(this) }
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) = Unit

            override fun onNullBinding(name: ComponentName?) {
                result.error("establish", "the tunnel service returned no binder", null)
                runCatching { unbindService(this) }
            }
        }

        if (!bindService(intent, connection, Context.BIND_AUTO_CREATE)) {
            result.error("establish", "could not bind to the tunnel service", null)
        }
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
