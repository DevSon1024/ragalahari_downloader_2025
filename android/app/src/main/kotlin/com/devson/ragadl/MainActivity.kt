package com.devson.ragadl

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var imageViewerBridge: ImageViewerBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        imageViewerBridge = ImageViewerBridge(this)
        imageViewerBridge.setupChannel(flutterEngine)
    }
}