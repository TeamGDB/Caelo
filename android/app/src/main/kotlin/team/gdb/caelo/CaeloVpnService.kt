package team.gdb.caelo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * Owns the system side of the tunnel.
 *
 * Android does not allow an application to open a tun device itself. This asks
 * the system for one, configured with the addresses, routes, MTU and DNS the
 * core reported, and hands the descriptor back. Everything after that — the
 * handshake, the obfuscation, the traffic — happens in the Go core, which the
 * Dart side drives directly over FFI.
 *
 * The service deliberately does not know what AmneziaWG is. Its whole job is to
 * hold a descriptor and a notification, and to stop cleanly when the system
 * takes the tunnel away.
 */
class CaeloVpnService : VpnService() {

    companion object {
        private const val TAG = "CaeloVpnService"
        private const val CHANNEL_ID = "caelo.tunnel"
        private const val NOTIFICATION_ID = 1

        const val ACTION_STOP = "team.gdb.caelo.STOP"

        /**
         * Set while a tunnel is up so the Dart side can ask, and so the system
         * revoking the tunnel is visible rather than silent.
         */
        @Volatile
        var running: Boolean = false
            private set

        @Volatile
        private var instance: CaeloVpnService? = null

        fun current(): CaeloVpnService? = instance
    }

    private var descriptor: ParcelFileDescriptor? = null

    /** Handed to whoever binds, so the activity can drive this directly. */
    inner class LocalBinder : Binder() {
        val service: CaeloVpnService get() = this@CaeloVpnService
    }

    private val binder = LocalBinder()

    // VpnService.onBind answers the system's own VpnService intent, and that
    // answer must not be replaced. Anything else is our own binding.
    override fun onBind(intent: Intent?): IBinder? {
        if (intent?.action == SERVICE_INTERFACE) return super.onBind(intent)
        return binder
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            teardown()
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, notification())

        // Not sticky: if the system kills us, it must not silently bring the
        // service back without a tunnel behind it. A VPN that appears to be
        // running and is not is worse than one that is plainly off.
        return START_NOT_STICKY
    }

    /**
     * Asks the system for a tun device and returns its descriptor.
     *
     * The descriptor is detached: ownership passes to the caller, and from
     * there to the core, which closes it on disconnect. Closing it here as well
     * would shut a descriptor the core is still reading.
     */
    fun establish(
        addresses: List<String>,
        routes: List<String>,
        dns: List<String>,
        mtu: Int,
    ): Int {
        teardown()

        // Blocking mode is left alone. The core switches the descriptor to
        // non-blocking itself when it adopts it, and setting it from both sides
        // only creates a disagreement to debug later.
        val builder = Builder()
            .setSession("Caelo")
            .setMtu(mtu)

        for (address in addresses) {
            val (host, prefix) = splitPrefix(address, default = 32)
            builder.addAddress(host, prefix)
        }

        for (route in routes) {
            val (host, prefix) = splitPrefix(route, default = 0)
            // A v6 route with no v6 address inside the tunnel would black-hole
            // v6 traffic instead of carrying it. Skipping it lets the system
            // keep handling v6 the way it already was.
            if (host.contains(':') && addresses.none { it.contains(':') }) continue
            builder.addRoute(host, prefix)
        }

        for (server in dns) {
            builder.addDnsServer(server)
        }

        // Caelo must not tunnel its own traffic. Without this the app's own
        // requests would be routed into the tunnel it is trying to establish.
        try {
            builder.addDisallowedApplication(packageName)
        } catch (error: Exception) {
            Log.w(TAG, "could not exclude Caelo from its own tunnel", error)
        }

        builder.setConfigureIntent(
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        )

        val established = builder.establish()
            ?: throw IllegalStateException("the system refused to establish the tunnel")

        descriptor = established
        running = true

        val fd = established.detachFd()
        descriptor = null
        return fd
    }

    /** Excludes a socket from the tunnel's own routing. */
    fun protectSocket(fd: Int): Boolean = fd >= 0 && protect(fd)

    /**
     * Called when the system takes the tunnel away — another VPN started, or
     * the user revoked permission. The core keeps running on a descriptor that
     * no longer carries anything, so the Dart side has to be told.
     */
    override fun onRevoke() {
        Log.i(TAG, "the system revoked the tunnel")
        teardown()
        MainActivity.notifyRevoked()
        super.onRevoke()
    }

    override fun onDestroy() {
        teardown()
        instance = null
        super.onDestroy()
    }

    private fun teardown() {
        running = false
        descriptor?.close()
        descriptor = null
    }

    private fun notification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.tunnel_channel_name),
                    // Low: this notification exists because the system requires
                    // a foreground service to have one, not because there is
                    // anything to interrupt anyone about.
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }

        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.tunnel_notification_title))
            .setContentText(getString(R.string.tunnel_notification_text))
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    /** Splits `10.8.1.23/32` into its address and prefix length. */
    private fun splitPrefix(value: String, default: Int): Pair<String, Int> {
        val slash = value.indexOf('/')
        if (slash < 0) return value to default
        val prefix = value.substring(slash + 1).toIntOrNull() ?: default
        return value.substring(0, slash) to prefix
    }
}
