package com.devson.ragadl

import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class ImageViewerBridge(private val context: Context) {
    companion object {
        private const val CHANNEL = "com.devson.ragadl/image_viewer"
    }

    fun setupChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openImageViewer" -> {
                        try {
                            val imagePath = call.argument<String>("imagePath")
                            val imageList = call.argument<List<String>>("imageList")
                            val initialIndex = call.argument<Int>("initialIndex") ?: 0

                            if (imagePath != null && imageList != null) {
                                openImageViewer(imagePath, imageList, initialIndex)
                                result.success(true)
                            } else {
                                result.error("INVALID_ARGUMENT", "Image path or list is null", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    private fun openImageViewer(imagePath: String, imageList: List<String>, initialIndex: Int) {
        val intent = Intent(context, ImageViewerActivity::class.java).apply {
            putExtra("imagePath", imagePath)
            putStringArrayListExtra("imageList", ArrayList(imageList))
            putExtra("initialIndex", initialIndex)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}