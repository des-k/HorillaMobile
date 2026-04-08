package com.cybrosys.horilla_project

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "horilla/device_info",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getDeviceInfo") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val model = Build.MODEL?.trim().orEmpty()
            val manufacturer = Build.MANUFACTURER?.trim().orEmpty()
            val release = Build.VERSION.RELEASE?.trim().orEmpty()
            val osVersion = if (release.isEmpty()) {
                "Android"
            } else {
                "Android $release"
            }

            result.success(
                mapOf(
                    "manufacturer" to manufacturer,
                    "model" to model,
                    "osVersion" to osVersion,
                    "device" to (Build.DEVICE?.trim().orEmpty()),
                    "product" to (Build.PRODUCT?.trim().orEmpty()),
                )
            )
        }
    }
}
