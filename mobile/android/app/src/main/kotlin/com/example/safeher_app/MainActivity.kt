package com.example.safeher_app

import com.example.safeher_app.hardware.SafeHerHardwarePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		flutterEngine.plugins.add(SafeHerHardwarePlugin())
	}
}
