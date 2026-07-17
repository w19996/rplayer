@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package com.example.player_flutter

import android.content.Context
import android.media.MediaCodecList
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import okhttp3.Dns
import okhttp3.OkHttpClient
import java.net.InetAddress

internal class Media3VideoBridge(
    private val context: Context,
    private val sendEvent: (String, Any?) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    private var textureView: TextureView? = null
    private var firstFrameRendered = false
    private var subtitleText = ""
    private var fit = "contain"
    private var videoSize = VideoSize.UNKNOWN
    private val httpClient = OkHttpClient.Builder()
        .dns(object : Dns {
            override fun lookup(hostname: String): List<InetAddress> =
                media3McdnIp(hostname)?.let { listOf(InetAddress.getByName(it)) }
                    ?: Dns.SYSTEM.lookup(hostname)
        })
        .build()

    private val ticker = object : Runnable {
        override fun run() {
            if (player == null) return
            emitState()
            handler.postDelayed(this, 200)
        }
    }

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) = emitState()
        override fun onIsPlayingChanged(isPlaying: Boolean) = emitState()
        override fun onTracksChanged(tracks: Tracks) = emitState(tracks = tracks)

        override fun onVideoSizeChanged(size: VideoSize) {
            videoSize = size
            applySurfaceTransform()
            emitState()
        }

        override fun onRenderedFirstFrame() {
            firstFrameRendered = true
            emitState()
        }

        override fun onCues(cueGroup: CueGroup) {
            subtitleText = cueGroup.cues.mapNotNull { it.text?.toString() }.joinToString("\n")
            emitState()
        }

        override fun onPlayerError(error: PlaybackException) = emitState(error)
    }

    private val analyticsListener = object : AnalyticsListener {
        override fun onVideoDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializedTimestampMs: Long,
            initializationDurationMs: Long,
        ) = diagnostic("decoder=$decoderName")

        override fun onVideoInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: Format,
            decoderReuseEvaluation: DecoderReuseEvaluation?,
        ) = diagnostic("format=${format.sampleMimeType} codecs=${format.codecs} color=${format.colorInfo}")
    }

    fun open(uri: String, headers: Map<String, String>, mimeType: String?, startMs: Long) {
        releasePlayer()
        firstFrameRendered = false
        subtitleText = ""
        videoSize = VideoSize.UNKNOWN
        val next = ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory(headers))
            .build()
        player = next
        next.addListener(listener)
        next.addAnalyticsListener(analyticsListener)
        diagnostic(deviceCapabilities())
        textureView?.let(next::setVideoTextureView)
        next.setMediaItem(mediaItem(uri, mimeType), startMs.coerceAtLeast(0))
        next.prepare()
        next.playWhenReady = true
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    fun command(action: String, value: Any?) {
        val active = player ?: return
        when (action) {
            "play" -> active.play()
            "pause" -> active.pause()
            "seek" -> active.seekTo((value as? Number)?.toLong()?.coerceAtLeast(0) ?: 0)
            "rate" -> active.playbackParameters = PlaybackParameters((value as? Number)?.toFloat() ?: 1f)
            "volume" -> active.volume = ((value as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
            "stop" -> active.stop()
            "fit" -> {
                fit = value as? String ?: "contain"
                applySurfaceTransform()
            }
            "audioTrack" -> selectTrack(C.TRACK_TYPE_AUDIO, value as? String ?: "auto")
            "subtitleTrack" -> selectTrack(C.TRACK_TYPE_TEXT, value as? String ?: "no")
        }
    }

    fun release() {
        releasePlayer()
        textureView = null
    }

    fun attach(view: TextureView) {
        textureView = view
        view.keepScreenOn = player?.let {
            it.playWhenReady && it.playbackState != Player.STATE_IDLE && it.playbackState != Player.STATE_ENDED
        } == true
        view.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applySurfaceTransform() }
        player?.setVideoTextureView(view)
        applySurfaceTransform()
    }

    fun detach(view: TextureView) {
        if (textureView !== view) return
        view.keepScreenOn = false
        player?.clearVideoTextureView(view)
        textureView = null
    }

    private fun releasePlayer() {
        handler.removeCallbacks(ticker)
        textureView?.keepScreenOn = false
        player?.run {
            textureView?.let(::clearVideoTextureView)
            removeListener(listener)
            release()
        }
        player = null
    }

    private fun diagnostic(message: String) = sendEvent("media3Diagnostic", message)

    private fun deviceCapabilities(): String {
        val decoders = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
            .filter { info ->
                !info.isEncoder && info.supportedTypes.any {
                    it.equals(MimeTypes.VIDEO_DOLBY_VISION, ignoreCase = true)
                }
            }
            .joinToString { it.name }
            .ifEmpty { "none" }
        val hdrTypes = if (Build.VERSION.SDK_INT >= 24) {
            textureView?.display?.hdrCapabilities?.supportedHdrTypes
                ?.joinToString()
                ?: "unknown"
        } else {
            "unsupported-api"
        }
        return "device=${Build.MANUFACTURER}/${Build.MODEL} sdk=${Build.VERSION.SDK_INT} dvDecoders=$decoders displayHdrTypes=$hdrTypes"
    }

    private fun mediaSourceFactory(headers: Map<String, String>): DefaultMediaSourceFactory {
        val http = OkHttpDataSource.Factory(httpClient)
            .setDefaultRequestProperties(headers)
        return DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http))
    }

    private fun mediaItem(uri: String, mimeType: String?): MediaItem {
        val builder = MediaItem.Builder().setUri(uri)
        val lower = uri.lowercase()
        if (!mimeType.isNullOrBlank()) {
            builder.setMimeType(mimeType)
        } else if (lower.contains("getm3u8") || lower.contains(".m3u8")) {
            builder.setMimeType(MimeTypes.APPLICATION_M3U8)
        }
        return builder.build()
    }

    private fun selectTrack(type: Int, id: String) {
        val active = player ?: return
        val builder = active.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(type)
            .setTrackTypeDisabled(type, id == "no")
        if (id != "auto" && id != "no") {
            val parts = id.split(':')
            val groupIndex = parts.getOrNull(0)?.toIntOrNull()
            val trackIndex = parts.getOrNull(1)?.toIntOrNull()
            val group = groupIndex?.let { active.currentTracks.groups.getOrNull(it) }
            if (group != null && trackIndex != null && trackIndex in 0 until group.length) {
                builder.setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, trackIndex))
            }
        }
        active.trackSelectionParameters = builder.build()
    }

    private fun emitState(
        playbackError: PlaybackException? = player?.playerError,
        tracks: Tracks? = null,
    ) {
        val active = player ?: return
        textureView?.keepScreenOn =
            active.playWhenReady && active.playbackState != Player.STATE_IDLE && active.playbackState != Player.STATE_ENDED
        val duration = active.duration.takeUnless { it == C.TIME_UNSET } ?: 0
        val state = mutableMapOf<String, Any?>(
            "positionMs" to active.currentPosition,
            "durationMs" to duration,
            "buffering" to (active.playbackState == Player.STATE_BUFFERING),
            "bufferingPercent" to active.bufferedPercentage,
            "playing" to active.isPlaying,
            "ended" to (active.playbackState == Player.STATE_ENDED),
            "firstFrame" to firstFrameRendered,
            "width" to videoSize.width,
            "height" to videoSize.height,
            "rate" to active.playbackParameters.speed.toDouble(),
            "volume" to (active.volume * 100).toDouble(),
            "subtitle" to subtitleText,
            "error" to playbackError?.let { "${it.errorCodeName}: ${it.message ?: "Media3 playback failed"}" },
        )
        if (tracks != null) state["tracks"] = trackState(tracks)
        sendEvent("media3StateChanged", state)
    }

    private fun trackState(tracks: Tracks): Map<String, Any> {
        val audio = mutableListOf<Map<String, Any?>>(mapOf("id" to "auto", "title" to "自动"))
        val subtitles = mutableListOf<Map<String, Any?>>(
            mapOf("id" to "no", "title" to "关闭"),
            mapOf("id" to "auto", "title" to "自动"),
        )
        var selectedAudio = "auto"
        var selectedSubtitle = "no"
        tracks.groups.forEachIndexed { groupIndex, group ->
            val target = when (group.type) {
                C.TRACK_TYPE_AUDIO -> audio
                C.TRACK_TYPE_TEXT -> subtitles
                else -> null
            } ?: return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                val id = "$groupIndex:$trackIndex"
                target += mapOf(
                    "id" to id,
                    "title" to format.label,
                    "language" to format.language,
                    "codec" to (format.codecs ?: format.sampleMimeType),
                )
                if (group.isTrackSelected(trackIndex)) {
                    if (group.type == C.TRACK_TYPE_AUDIO) selectedAudio = id else selectedSubtitle = id
                }
            }
        }
        return mapOf(
            "audio" to audio,
            "subtitle" to subtitles,
            "selectedAudio" to selectedAudio,
            "selectedSubtitle" to selectedSubtitle,
        )
    }

    private fun applySurfaceTransform() {
        val view = textureView ?: return
        val viewWidth = view.width.toFloat()
        val viewHeight = view.height.toFloat()
        val videoWidth = videoSize.width.toFloat()
        val videoHeight = videoSize.height.toFloat()
        if (viewWidth <= 0 || viewHeight <= 0 || videoWidth <= 0 || videoHeight <= 0) return
        val viewAspect = viewWidth / viewHeight
        val videoAspect = videoWidth / videoHeight
        var scaleX = 1f
        var scaleY = 1f
        when (fit) {
            "contain" -> if (videoAspect > viewAspect) scaleY = viewAspect / videoAspect else scaleX = videoAspect / viewAspect
            "cover" -> if (videoAspect > viewAspect) scaleX = videoAspect / viewAspect else scaleY = viewAspect / videoAspect
            "none" -> {
                scaleX = videoWidth / viewWidth
                scaleY = videoHeight / viewHeight
            }
        }
        view.pivotX = viewWidth / 2f
        view.pivotY = viewHeight / 2f
        view.scaleX = scaleX
        view.scaleY = scaleY
    }
}

internal fun media3McdnIp(hostname: String): String? {
    val match =
        Regex("""^xy(\d{1,3})x(\d{1,3})x(\d{1,3})x(\d{1,3})xy\..*\.bilivideo\.cn$""")
            .matchEntire(hostname.lowercase()) ?: return null
    val parts = match.groupValues.drop(1).map { it.toInt() }
    if (parts.any { it !in 0..255 }) return null
    return parts.joinToString(".")
}

internal class Media3TextureViewFactory(
    private val bridge: Media3VideoBridge,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return object : PlatformView {
            private val view = TextureView(context).also(bridge::attach)
            override fun getView() = view
            override fun dispose() = bridge.detach(view)
        }
    }
}
