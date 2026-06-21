package com.example.player_flutter

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.BatteryManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
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
                else -> result.notImplemented()
            }
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
            "volume" -> adjustVolume(delta)
            "brightness" -> adjustBrightness(delta)
            else -> mapOf("kind" to kind, "value" to 0.0)
        }
    }

    private fun adjustVolume(delta: Float): Map<String, Any> {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        var target = (current + delta * maxVolume).roundToInt().coerceIn(0, maxVolume)
        if (delta > 0.0f && target <= current) target = (current + 1).coerceAtMost(maxVolume)
        if (delta < 0.0f && target >= current) target = (current - 1).coerceAtLeast(0)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
        return mapOf(
            "kind" to "volume",
            "value" to (target.toDouble() / maxVolume.toDouble())
        )
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
}
