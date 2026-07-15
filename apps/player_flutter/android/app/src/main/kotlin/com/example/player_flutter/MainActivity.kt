package com.example.player_flutter

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.graphics.drawable.Icon
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.util.Rational
import android.view.OrientationEventListener
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val ACTION_PIP_TOGGLE_PLAYBACK = "com.example.player_flutter.PIP_TOGGLE_PLAYBACK"
    }

    private var orientationListener: OrientationEventListener? = null
    private var playbackOrientationMode: String = "off"
    private var currentRequestedOrientation: Int? = null
    private var playbackPipEnabled: Boolean = false
    private var pipPlaybackPlaying: Boolean = false
    private var pipActionReceiverRegistered: Boolean = false
    private var appChannel: MethodChannel? = null
    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_PIP_TOGGLE_PLAYBACK) {
                appChannel?.invokeMethod("pipTogglePlayback", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerPipActionReceiver()
        appChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rplayer/app")
        appChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "appFilesDir" -> result.success(filesDir.absolutePath)
                "playerStatus" -> result.success(playerStatus())
                "nativePlaybackCapabilities" -> result.success(nativePlaybackCapabilities())
                "videoThumbnail" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    val remote = call.argument<Boolean>("remote") == true
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    Thread {
                        result.success(videoThumbnail(uri, remote, headers))
                    }.start()
                }
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
                "setPlaybackPipEnabled" -> {
                    playbackPipEnabled = call.argument<Boolean>("enabled") == true
                    result.success(null)
                }
                "setPlaybackPipPlaybackState" -> {
                    pipPlaybackPlaying = call.argument<Boolean>("playing") == true
                    updatePictureInPictureParamsIfNeeded()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun videoThumbnail(uri: String, remote: Boolean, headers: Map<String, String>): ByteArray? {
        if (uri.isBlank()) return null
        val retriever = MediaMetadataRetriever()
        return try {
            if (remote) {
                retriever.setDataSource(uri, headers)
            } else {
                retriever.setDataSource(uri)
            }
            val frame = retriever.getFrameAtTime(1_000_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.frameAtTime
                ?: return null
            val scaled = scaleBitmap(frame, 480)
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
            if (scaled !== frame) scaled.recycle()
            frame.recycle()
            out.toByteArray()
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun scaleBitmap(bitmap: Bitmap, maxSide: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val side = maxOf(width, height)
        if (side <= maxSide || side <= 0) return bitmap
        val scale = maxSide.toFloat() / side.toFloat()
        return Bitmap.createScaledBitmap(
            bitmap,
            maxOf(1, (width * scale).toInt()),
            maxOf(1, (height * scale).toInt()),
            true
        )
    }

    override fun onDestroy() {
        stopPlaybackOrientationSensor()
        unregisterPipActionReceiver()
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

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        notifyFlutterWindowFocus(hasFocus)
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        notifyFlutterMultiWindowMode(isInMultiWindowMode)
    }

    override fun onUserLeaveHint() {
        if (!tryEnterPlaybackPictureInPicture()) {
            super.onUserLeaveHint()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (tryEnterPlaybackPictureInPicture()) return
        super.onBackPressed()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        notifyFlutterPipMode(isInPictureInPictureMode)
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

    private fun nativePlaybackCapabilities(): Map<String, Any> {
        val hdrTypes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.hdrCapabilities.supportedHdrTypes.toSet()
        } else {
            emptySet()
        }
        val displaySupportsDolbyVision = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION)
        val displaySupportsHdr10 = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_HDR10)
        val decoders = mutableListOf<Map<String, Any>>()
        val supportedProfiles = mutableSetOf<Int>()
        try {
            for (codec in MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos) {
                if (codec.isEncoder) continue
                for (mimeType in codec.supportedTypes) {
                    if (!mimeType.startsWith("video/")) continue
                    val hardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        codec.isHardwareAccelerated
                    } else {
                        val name = codec.name.lowercase()
                        !name.startsWith("omx.google.") && !name.startsWith("c2.android.")
                    }
                    val profiles = if (mimeType.equals("video/dolby-vision", true)) {
                        codec.getCapabilitiesForType(mimeType).profileLevels
                            .flatMap { dolbyVisionProfiles(it.profile) }
                            .toSet()
                    } else {
                        emptySet()
                    }
                    if (hardware && profiles.isNotEmpty()) supportedProfiles.addAll(profiles)
                    if (hardware) {
                        decoders.add(
                            mapOf(
                                "name" to codec.name,
                                "mimeType" to mimeType,
                                "hardwareAccelerated" to true,
                                "dolbyVisionProfiles" to profiles.toList().sorted()
                            )
                        )
                    }
                }
            }
        } catch (_: Throwable) {
        }
        return mapOf(
            "supportsNativeDolbyVision" to
                (displaySupportsDolbyVision && supportedProfiles.isNotEmpty()),
            "supportedDolbyVisionProfiles" to supportedProfiles.toList().sorted(),
            "supportsHdr10" to displaySupportsHdr10,
            "hardwareDecoders" to decoders
        )
    }

    private fun dolbyVisionProfiles(codecProfile: Int): Set<Int> {
        return when (codecProfile) {
            MediaCodecInfo.CodecProfileLevel.DolbyVisionProfileDvheDer -> setOf(1)
            MediaCodecInfo.CodecProfileLevel.DolbyVisionProfileDvheDen -> setOf(2)
            MediaCodecInfo.CodecProfileLevel.DolbyVisionProfileDvheDtr -> setOf(3)
            MediaCodecInfo.CodecProfileLevel.DolbyVisionProfileDvheDth -> setOf(4)
            MediaCodecInfo.CodecProfileLevel.DolbyVisionProfileDvheStn -> setOf(5)
            MediaCodecInfo.CodecProfileLevel.DolbyVisionProfileDvheDtb -> setOf(6)
            MediaCodecInfo.CodecProfileLevel.DolbyVisionProfileDvheSt -> setOf(7, 8)
            MediaCodecInfo.CodecProfileLevel.DolbyVisionProfileDvavSe -> setOf(9)
            else -> emptySet()
        }
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

    private fun tryEnterPlaybackPictureInPicture(): Boolean {
        if (!playbackPipEnabled) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (isInPictureInPictureMode) return false
        val params = buildPictureInPictureParams()
        notifyFlutterPipMode(true)
        return try {
            val entered = enterPictureInPictureMode(params)
            if (!entered) notifyFlutterPipMode(false)
            entered
        } catch (_: Throwable) {
            notifyFlutterPipMode(false)
            false
        }
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        val title = if (pipPlaybackPlaying) "暂停" else "播放"
        val iconRes = if (pipPlaybackPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val intent = Intent(ACTION_PIP_TOGGLE_PLAYBACK).setPackage(packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getBroadcast(this, 0, intent, flags)
        val action = RemoteAction(
            Icon.createWithResource(this, iconRes),
            title,
            title,
            pendingIntent
        )
        builder.setActions(listOf(action))
        return builder.build()
    }

    private fun updatePictureInPictureParamsIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!isInPictureInPictureMode) return
        try {
            setPictureInPictureParams(buildPictureInPictureParams())
        } catch (_: Throwable) {
        }
    }

    private fun notifyFlutterPipMode(enabled: Boolean) {
        appChannel?.invokeMethod("pipModeChanged", enabled)
    }

    private fun notifyFlutterWindowFocus(focused: Boolean) {
        appChannel?.invokeMethod("windowFocusChanged", focused)
    }

    private fun notifyFlutterMultiWindowMode(enabled: Boolean) {
        appChannel?.invokeMethod("multiWindowModeChanged", enabled)
    }

    private fun registerPipActionReceiver() {
        if (pipActionReceiverRegistered) return
        val filter = IntentFilter(ACTION_PIP_TOGGLE_PLAYBACK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(pipActionReceiver, filter)
        }
        pipActionReceiverRegistered = true
    }

    private fun unregisterPipActionReceiver() {
        if (!pipActionReceiverRegistered) return
        try {
            unregisterReceiver(pipActionReceiver)
        } catch (_: Throwable) {
        }
        pipActionReceiverRegistered = false
    }
}
