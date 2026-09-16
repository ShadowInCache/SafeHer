package io.github.akshayag.safeher.network

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lets Dart hold a [WifiManager.MulticastLock] while it runs an mDNS query.
 *
 * Android's Wi-Fi chip drops multicast packets that are not addressed to the
 * phone unless something holds this lock — a power optimisation that is
 * invisible from Dart. `multicast_dns` sends its query out fine and simply
 * never sees the answer, so `safeher-glasses.local` fails to resolve while
 * the very same phone streams video happily from the camera's raw IP. That is
 * the exact symptom this exists to fix, and no amount of Dart-side retrying
 * can fix it, because the reply never reaches the app.
 *
 * Reference counted, so overlapping resolves (pairing and the video stream
 * reconnecting at the same time) each acquire and release independently and
 * the lock is only truly dropped when the last one finishes. Holding it costs
 * battery — it defeats the optimisation above — so it is held only around a
 * query, never for the life of the app.
 *
 * Requires `CHANGE_WIFI_MULTICAST_STATE`, which is a normal permission: it is
 * granted at install and never prompts.
 */
class MulticastLockPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "io.github.akshayag.safeher/multicast"
        private const val LOCK_TAG = "SafeHerMdns"
    }

    private var channel: MethodChannel? = null
    private var wifiManager: WifiManager? = null
    private var lock: WifiManager.MulticastLock? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
        // The application context, not the activity: the lock outlives any one
        // screen, and holding an activity here would leak it.
        wifiManager = binding.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as? WifiManager
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        releaseAll()
        channel?.setMethodCallHandler(null)
        channel = null
        wifiManager = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> result.success(acquire())
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Returns whether the lock is now held. `false` is not an error the caller
     * should abandon the lookup over: some devices and emulators have no Wi-Fi
     * service at all, and on a network that does not filter multicast the
     * query works without it. Dart logs it and carries on.
     */
    private fun acquire(): Boolean {
        val existing = lock ?: wifiManager?.createMulticastLock(LOCK_TAG)?.also {
            it.setReferenceCounted(true)
            lock = it
        } ?: return false

        return try {
            existing.acquire()
            true
        } catch (error: SecurityException) {
            // CHANGE_WIFI_MULTICAST_STATE missing from the manifest.
            false
        } catch (error: UnsupportedOperationException) {
            false
        }
    }

    private fun release() {
        val held = lock ?: return
        // `isHeld` guards the reference count going negative, which throws.
        if (held.isHeld) {
            try {
                held.release()
            } catch (error: RuntimeException) {
                // Already fully released by a racing call; nothing to undo.
            }
        }
    }

    /** Unwinds every outstanding acquire when the engine goes away. */
    private fun releaseAll() {
        val held = lock ?: return
        while (held.isHeld) {
            try {
                held.release()
            } catch (error: RuntimeException) {
                break
            }
        }
        lock = null
    }
}
