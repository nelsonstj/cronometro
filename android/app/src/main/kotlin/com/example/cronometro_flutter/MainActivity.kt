package com.example.cronometro_flutter

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app_channel"
    private val OVERLAY_PERMISSION_REQUEST_CODE = 1234

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val hasPermission = Settings.canDrawOverlays(this)
                        android.util.Log.d("OVERLAY_DEBUG", "canDrawOverlays: $hasPermission")
                        if (!hasPermission) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST_CODE)
                            result.success(false)
                            return@setMethodCallHandler
                        }
                    }
                    result.success(true)
                }
                "canDrawOverlays" -> {
                    val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    android.util.Log.d("OVERLAY_DEBUG", "canDrawOverlays result: $canDraw")
                    result.success(canDraw)
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("OPEN_SETTINGS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try {
            stopService(Intent(this, OverlayService::class.java))
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    override fun onStop() {
        if (isFinishing) {
            try {
                stopService(Intent(this, OverlayService::class.java))
            } catch (_: Exception) {
            }
        }
        super.onStop()
    }
}
