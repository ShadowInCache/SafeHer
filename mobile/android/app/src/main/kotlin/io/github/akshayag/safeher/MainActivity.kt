package io.github.akshayag.safeher

import io.github.akshayag.safeher.hardware.SafeHerHardwarePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		flutterEngine.plugins.add(SafeHerHardwarePlugin())
	}
}
