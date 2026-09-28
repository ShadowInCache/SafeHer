package io.github.akshayag.safeher

import io.github.akshayag.safeher.hardware.SafeHerHardwarePlugin
import io.github.akshayag.safeher.network.MulticastLockPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity, not FlutterActivity: `local_auth` shows the
// AndroidX BiometricPrompt, which is a Fragment and therefore needs a
// FragmentActivity to attach to. Under a plain FlutterActivity the plugin
// throws PlatformException(no_fragment_activity) on every call, which the
// app could only report as "Authentication failed or was cancelled" -- the
// fingerprint sheet never appeared at all.
class MainActivity : FlutterFragmentActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		flutterEngine.plugins.add(SafeHerHardwarePlugin())
		// Without this, mDNS replies are filtered by the Wi-Fi chip and
		// safeher-glasses.local never resolves on Android. See the plugin.
		flutterEngine.plugins.add(MulticastLockPlugin())
	}
}
