package com.devson.ragadl

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.os.Build
import android.view.WindowManager

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Disable hardware acceleration for certain problematic views if needed
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
        }
    }
}
