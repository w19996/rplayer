package com.example.player_flutter

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.BatteryManager
import android.provider.Settings
import android.view.OrientationEventListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var orientationListener: OrientationEventListener? = null
    private var playbackOrientationMode: String = "off"
    private var currentRequestedOrientation: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rplayer/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "appFilesDir" -> result.success(filesDir.absolutePath)
                "playerStatus" -> result.success(playerStatus())
                "adjustPlaybackControl" -> {
                    val kind = call.argument<String>("kind") ?: ""
                    val delta = (call.argument<Double>("delta") ?: 0.0).toFloat()
                    result.success(adjustPlaybackControl(kind, delta))
                }
                "setPlaybackOrientationMode" -> {
                    val mode = call.argument<String>("mode") ?: "off"
                    setPlaybackOrientationMode(mode)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopPlaybackOrientationSensor()
        super.onDestroy()
    }

    override fun onPause() {
        stopPlaybackOrientationSensor()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (playbackOrientationMode == "landscape") {
            startPlaybackOrientationSensor()
        }
    }

    private fun playerStatus(): Map<String, Any> {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val manager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val propertyLevel = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val batteryPercent = when {
            level >= 0 && scale > 0 -> (level * 100 / scale)
            propertyLevel in 0..100 -> propertyLevel
            else -> -1
        }
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val network = when {
            capabilities == null -> "OFF"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WiFi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "4G"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "LAN"
            else -> "NET"
        }

        return mapOf(
            "battery" to batteryPercent,
            "charging" to charging,
            "network" to network,
            "rxBytes" to TrafficStats.getTotalRxBytes()
        )
    }

    private fun adjustPlaybackControl(kind: String, delta: Float): Map<String, Any> {
        return when (kind) {
            "brightness" -> adjustBrightness(delta)
            else -> mapOf("kind" to kind, "value" to 0.0)
        }
    }

    private fun adjustBrightness(delta: Float): Map<String, Any> {
        val attributes = window.attributes
        val current = if (attributes.screenBrightness >= 0.0f) {
            attributes.screenBrightness
        } else {
            val systemBrightness = Settings.System.getInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                128
            )
            systemBrightness.toFloat() / 255.0f
        }
        val target = (current + delta).coerceIn(0.02f, 1.0f)
        attributes.screenBrightness = target
        window.attributes = attributes
        return mapOf(
            "kind" to "brightness",
            "value" to target.toDouble()
        )
    }

    private fun setPlaybackOrientationMode(mode: String) {
        playbackOrientationMode = mode
        when (mode) {
            "landscape" -> {
                setRequestedOrientationIfChanged(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)
                startPlaybackOrientationSensor()
            }
            "portrait" -> {
                stopPlaybackOrientationSensor()
                setRequestedOrientationIfChanged(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)
            }
            else -> {
                stopPlaybackOrientationSensor()
                currentRequestedOrientation = null
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }
        }
    }

    private fun startPlaybackOrientationSensor() {
        if (orientationListener == null) {
            orientationListener = object : OrientationEventListener(this) {
                override fun onOrientationChanged(orientation: Int) {
                    if (playbackOrientationMode != "landscape") return
                    if (orientation == ORIENTATION_UNKNOWN) return
                    val next = landscapeOrientationFor(orientation) ?: return
                    setRequestedOrientationIfChanged(next)
                }
            }
        }
        orientationListener?.enable()
    }

    private fun stopPlaybackOrientationSensor() {
        orientationListener?.disable()
    }

    private fun landscapeOrientationFor(orientation: Int): Int? {
        return when {
            orientation in 45..135 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            orientation in 225..315 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            else -> null
        }
    }

    private fun setRequestedOrientationIfChanged(orientation: Int) {
        if (currentRequestedOrientation == orientation) return
        currentRequestedOrientation = orientation
        requestedOrientation = orientation
    }
}
