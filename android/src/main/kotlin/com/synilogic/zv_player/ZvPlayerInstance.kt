package com.synilogic.zv_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.WindowManager
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
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
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * One playback session backed by ExoPlayer (AndroidX Media3).
 *
 * Owns the player, its channels and its event stream. Views attach and detach;
 * the player outlives them. Everything Flutter learns arrives as an event -
 * Flutter never polls this class for state.
 */
@OptIn(UnstableApi::class)
class ZvPlayerInstance(
    private val context: Context,
    messenger: BinaryMessenger,
    private val playerId: Int,
    private val activityProvider: () -> Activity?,
    /**
     * Told when this player has just asked the system for PiP, so the plugin
     * can start watching for the window being closed again.
     */
    private val onPictureInPictureEntered: () -> Unit = {}
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, Player.Listener {

    private val methodChannel = MethodChannel(messenger, "zv_player/player_$playerId")
    private val eventChannel = EventChannel(messenger, "zv_player/events_$playerId")
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var attachedView: PlayerView? = null
    private var activity: Activity? = activityProvider()
    private var appliedSecureFlag = false
    private var lastReportedStatus: String? = null
    private var unmutedVolume: Float = 1f

    /** Applied to every view this player attaches to, so fit survives rebuilds. */
    private var resizeMode: Int = AspectRatioFrameLayout.RESIZE_MODE_FIT

    /** Ids are `groupIndex:trackIndex`, stable for as long as the tracks are. */
    private var trackIndex: Map<String, Pair<Tracks.Group, Int>> = emptyMap()

    private val player: ExoPlayer by lazy { buildPlayer() }

    private var tickerRunning = false

    private val positionTicker = object : Runnable {
        override fun run() {
            if (!tickerRunning) return
            if (player.isPlaying || player.isLoading) {
                emitPosition()
            }
            mainHandler.postDelayed(this, POSITION_INTERVAL_MS)
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        // The ticker deliberately does NOT start here. It touches `player`,
        // and `player` is lazy - so starting it at construction built an
        // ExoPlayer on the main thread half a second later, in the middle of
        // the navigation transition. It starts when media is actually loaded.
    }

    private fun startTicker() {
        if (tickerRunning) return
        tickerRunning = true
        mainHandler.postDelayed(positionTicker, POSITION_INTERVAL_MS)
    }

    private fun stopTicker() {
        tickerRunning = false
        mainHandler.removeCallbacks(positionTicker)
    }

    private fun buildPlayer(): ExoPlayer {
        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(CONNECT_TIMEOUT_MS)
            .setReadTimeoutMs(READ_TIMEOUT_MS)

        val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
        this.httpDataSourceFactory = httpFactory

        return ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .build()
            .also { exo ->
                // Handing audio focus to the platform is what makes calls,
                // alarms and other apps behave correctly without custom code.
                exo.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .build(),
                    /* handleAudioFocus = */ true
                )
                // Pause when headphones are unplugged, as viewers expect.
                exo.setHandleAudioBecomingNoisy(true)
                exo.addListener(this)
            }
    }

    private var httpDataSourceFactory: DefaultHttpDataSource.Factory? = null

    // --- View attachment -----------------------------------------------------

    fun createView(): PlayerView {
        val view = PlayerView(context).apply {
            useController = false
            // Never a stretching mode: FIT letterboxes, ZOOM crops. The chosen
            // mode is re-applied here so a new view inherits it.
            resizeMode = this@ZvPlayerInstance.resizeMode
            setShutterBackgroundColor(Color.BLACK)
        }
        view.player = player
        attachedView = view
        return view
    }

    /**
     * Detaches [view], or the current view when null.
     *
     * The identity check matters: during a rebuild the replacement view can
     * attach before the old one is disposed, and an unconditional detach would
     * then blank the new surface while playback continued behind it.
     */
    fun detachView(view: PlayerView? = null) {
        if (view != null && attachedView !== view) return
        attachedView?.player = null
        attachedView = null
    }

    fun attachActivity(activity: Activity?) {
        this.activity = activity
    }

    // --- Method channel ------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> {
                load(call)
                result.success(null)
            }

            "play" -> {
                player.play()
                result.success(null)
            }

            "pause" -> {
                player.pause()
                result.success(null)
            }

            "seekTo" -> {
                val positionMs = (call.argument<Number>("positionMs") ?: 0).toLong()
                player.seekTo(positionMs)
                emitPosition()
                result.success(null)
            }

            "setSpeed" -> {
                val speed = (call.argument<Number>("speed") ?: 1.0).toFloat()
                player.playbackParameters = PlaybackParameters(speed)
                result.success(null)
            }

            "setVolume" -> {
                val volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
                player.volume = volume.coerceIn(0f, 1f)
                if (player.volume > 0f) unmutedVolume = player.volume
                emitVolume()
                result.success(null)
            }

            "setMuted" -> {
                val muted = call.argument<Boolean>("muted") ?: false
                if (muted && player.volume > 0f) unmutedVolume = player.volume
                player.volume = if (muted) 0f else unmutedVolume
                emitVolume()
                result.success(null)
            }

            "selectVideoTrack" -> {
                selectTrack(C.TRACK_TYPE_VIDEO, call.argument<String>("trackId"))
                result.success(null)
            }

            "selectAudioTrack" -> {
                selectTrack(C.TRACK_TYPE_AUDIO, call.argument<String>("trackId"))
                result.success(null)
            }

            "selectSubtitleTrack" -> {
                selectTrack(C.TRACK_TYPE_TEXT, call.argument<String>("trackId"))
                result.success(null)
            }

            "enterPictureInPicture" -> result.success(enterPictureInPicture())

            "setVideoFit" -> {
                // RESIZE_MODE_ZOOM crops the overflow while preserving the
                // aspect ratio; FIT letterboxes. Neither stretches the picture.
                val fill = call.argument<String>("fit") == "fill"
                resizeMode = if (fill) {
                    AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                } else {
                    AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
                attachedView?.resizeMode = resizeMode
                result.success(null)
            }

            "setSecureSurface" -> {
                setSecureSurface(call.argument<Boolean>("secure") ?: false)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun load(call: MethodCall) {
        val uri = call.argument<String>("uri").orEmpty()
        if (uri.isBlank()) {
            emitError("source_unavailable", "Empty media URI", null, false)
            return
        }

        // DRM is an extension point, not a feature. Refuse clearly rather than
        // playing protected content unprotected or failing silently.
        val drm = call.argument<Map<String, Any?>>("drm")
        val scheme = drm?.get("scheme") as? String
        if (drm != null && scheme != null && scheme != "none") {
            emitError(
                "drm_unsupported",
                "DRM scheme '$scheme' is not implemented in ZV Player",
                null,
                false
            )
            return
        }

        val headers = (call.argument<Map<String, String>>("headers") ?: emptyMap())
        if (headers.isNotEmpty()) {
            httpDataSourceFactory?.setDefaultRequestProperties(headers)
        }

        val type = call.argument<String>("type").orEmpty()
        val builder = MediaItem.Builder().setUri(Uri.parse(uri))
        when (type) {
            "hls" -> builder.setMimeType(MimeTypes.APPLICATION_M3U8)
            "dash" -> builder.setMimeType(MimeTypes.APPLICATION_MPD)
        }

        // Side-loaded subtitle files join the same text-track list as any
        // in-manifest tracks, so the UI treats them identically.
        val externalSubtitles = call.argument<List<Map<String, Any?>>>("externalSubtitles")
        if (!externalSubtitles.isNullOrEmpty()) {
            builder.setSubtitleConfigurations(
                externalSubtitles.mapNotNull { subtitle ->
                    val subtitleUri = subtitle["uri"] as? String ?: return@mapNotNull null
                    MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitleUri))
                        .setMimeType(mimeTypeForSubtitle(subtitle["format"] as? String, subtitleUri))
                        .setLanguage(subtitle["language"] as? String)
                        .setLabel(subtitle["label"] as? String)
                        .setSelectionFlags(
                            if (subtitle["isDefault"] == true) C.SELECTION_FLAG_DEFAULT else 0
                        )
                        .build()
                }
            )
        }

        val startPositionMs = (call.argument<Number>("startPositionMs") ?: 0).toLong()
        val autoPlay = call.argument<Boolean>("autoPlay") ?: true

        applyPreferredLanguages(
            call.argument<String>("preferredAudioLanguage"),
            call.argument<String>("preferredSubtitleLanguage")
        )

        player.setMediaItem(builder.build(), startPositionMs)
        player.playWhenReady = autoPlay
        player.prepare()
        emitStatus("loading")
        startTicker()
    }

    private fun applyPreferredLanguages(audio: String?, text: String?) {
        var parameters = player.trackSelectionParameters.buildUpon()
        if (!audio.isNullOrBlank()) {
            parameters = parameters.setPreferredAudioLanguage(audio)
        }
        if (!text.isNullOrBlank()) {
            parameters = parameters.setPreferredTextLanguage(text)
        }
        player.trackSelectionParameters = parameters.build()
    }

    private fun mimeTypeForSubtitle(format: String?, uri: String): String {
        return when (format?.lowercase()) {
            "vtt", "webvtt" -> MimeTypes.TEXT_VTT
            "srt", "subrip" -> MimeTypes.APPLICATION_SUBRIP
            "ttml", "dfxp" -> MimeTypes.APPLICATION_TTML
            else -> when {
                uri.endsWith(".vtt", true) -> MimeTypes.TEXT_VTT
                uri.endsWith(".ttml", true) || uri.endsWith(".dfxp", true) -> MimeTypes.APPLICATION_TTML
                else -> MimeTypes.APPLICATION_SUBRIP
            }
        }
    }

    /**
     * Applies a track override, or restores automatic selection when [trackId]
     * is null. For text, null means "off" rather than "automatic": viewers
     * expect subtitles they turned off to stay off.
     */
    private fun selectTrack(trackType: Int, trackId: String?) {
        var parameters = player.trackSelectionParameters.buildUpon()

        if (trackId == null) {
            parameters = parameters.clearOverridesOfType(trackType)
            if (trackType == C.TRACK_TYPE_TEXT) {
                parameters = parameters.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            }
            player.trackSelectionParameters = parameters.build()
            return
        }

        val entry = trackIndex[trackId] ?: return
        parameters = parameters
            .setTrackTypeDisabled(trackType, false)
            .setOverrideForType(
                TrackSelectionOverride(entry.first.mediaTrackGroup, listOf(entry.second))
            )
        player.trackSelectionParameters = parameters.build()
    }

    private fun enterPictureInPicture(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val currentActivity = activity ?: activityProvider() ?: return false
        if (!currentActivity.packageManager.hasSystemFeature(
                android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE
            )
        ) {
            return false
        }
        return try {
            val size = player.videoSize
            val width = if (size.width > 0) size.width else 16
            val height = if (size.height > 0) size.height else 9
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(width, height))
                .build()
            val entered = currentActivity.enterPictureInPictureMode(params)
            if (entered) onPictureInPictureEntered()
            entered
        } catch (error: Exception) {
            // A device can refuse PiP outright; report that rather than crashing.
            false
        }
    }

    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        emit(mapOf("event" to "pip", "isInPip" to isInPictureInPictureMode))
    }

    private fun setSecureSurface(secure: Boolean) {
        val window = (activity ?: activityProvider())?.window ?: return
        mainHandler.post {
            if (secure) {
                window.setFlags(
                    WindowManager.LayoutParams.FLAG_SECURE,
                    WindowManager.LayoutParams.FLAG_SECURE
                )
                appliedSecureFlag = true
            } else if (appliedSecureFlag) {
                // Only clear what this player set, so app-level protection on
                // other screens is left exactly as the app configured it.
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                appliedSecureFlag = false
            }
        }
    }

    // --- Player.Listener -----------------------------------------------------

    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_IDLE -> emitStatus("idle")
            Player.STATE_BUFFERING -> emitStatus("buffering")
            Player.STATE_READY -> {
                emitStatus(if (player.isPlaying) "playing" else "ready")
                emitPosition()
            }
            Player.STATE_ENDED -> {
                emitStatus("completed")
                emit(mapOf("event" to "completed"))
            }
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (isPlaying) {
            emitStatus("playing")
        } else if (player.playbackState == Player.STATE_READY) {
            emitStatus("paused")
        }
    }

    override fun onTracksChanged(tracks: Tracks) {
        val index = mutableMapOf<String, Pair<Tracks.Group, Int>>()
        val video = mutableListOf<Map<String, Any?>>()
        val audio = mutableListOf<Map<String, Any?>>()
        val text = mutableListOf<Map<String, Any?>>()

        tracks.groups.forEachIndexed { groupIndex, group ->
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val format = group.getTrackFormat(i)
                val id = "$groupIndex:$i"
                index[id] = group to i
                val selected = group.isTrackSelected(i)

                when (group.type) {
                    C.TRACK_TYPE_VIDEO -> video.add(
                        mapOf(
                            "id" to id,
                            "label" to labelForVideo(format),
                            "width" to format.width.takeIf { it != Format.NO_VALUE },
                            "height" to format.height.takeIf { it != Format.NO_VALUE },
                            "bitrate" to format.bitrate.takeIf { it != Format.NO_VALUE },
                            "codec" to format.codecs,
                            // Media3 reports frame rate only when the media
                            // declares it; NO_VALUE stays absent rather than
                            // becoming a guess.
                            "frameRate" to format.frameRate.takeIf {
                                it != Format.NO_VALUE.toFloat() && it > 0f
                            },
                            "isSelected" to selected
                        )
                    )

                    C.TRACK_TYPE_AUDIO -> audio.add(
                        mapOf(
                            "id" to id,
                            "language" to (format.language ?: ""),
                            "label" to (format.label ?: format.language ?: "Audio"),
                            "codec" to format.codecs,
                            "channels" to format.channelCount.takeIf { it != Format.NO_VALUE },
                            "bitrate" to format.bitrate.takeIf { it != Format.NO_VALUE },
                            "isSelected" to selected
                        )
                    )

                    C.TRACK_TYPE_TEXT -> text.add(
                        mapOf(
                            "id" to id,
                            "language" to (format.language ?: ""),
                            "label" to (format.label ?: format.language ?: "Subtitle"),
                            "format" to format.sampleMimeType,
                            "isExternal" to false,
                            // Selection flags as the media declares them, so
                            // forced narrative subtitles can be told apart
                            // from ordinary ones.
                            "isForced" to
                                ((format.selectionFlags and C.SELECTION_FLAG_FORCED) != 0),
                            "isDefault" to
                                ((format.selectionFlags and C.SELECTION_FLAG_DEFAULT) != 0),
                            "isSelected" to selected
                        )
                    )
                }
            }
        }

        trackIndex = index
        emit(
            mapOf(
                "event" to "tracks",
                "video" to video,
                "audio" to audio,
                "text" to text
            )
        )
    }

    private fun labelForVideo(format: Format): String {
        val height = format.height
        if (height == Format.NO_VALUE) return format.label ?: "Track"
        return when {
            height >= 2160 -> "4K"
            height >= 1440 -> "1440p"
            height >= 1080 -> "1080p"
            height >= 720 -> "720p"
            height >= 480 -> "480p"
            height >= 360 -> "360p"
            else -> "240p"
        }
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        emit(
            mapOf(
                "event" to "videoSize",
                "width" to videoSize.width,
                "height" to videoSize.height
            )
        )
    }

    override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
        emit(mapOf("event" to "speed", "speed" to playbackParameters.speed.toDouble()))
    }

    override fun onVolumeChanged(volume: Float) {
        emitVolume()
    }

    override fun onPlayerError(error: PlaybackException) {
        val code = error.errorCodeName
        emitError(
            code = code,
            message = error.message ?: "Playback failed",
            detail = error.cause?.toString(),
            recoverable = isRecoverable(error.errorCode)
        )
    }

    /** Transient transport failures are worth a bounded retry; format and DRM failures are not. */
    private fun isRecoverable(errorCode: Int): Boolean = when (errorCode) {
        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
        PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
        PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW,
        PlaybackException.ERROR_CODE_TIMEOUT -> true
        else -> false
    }

    // --- Events --------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }

    private fun emitStatus(status: String) {
        if (status == lastReportedStatus) return
        lastReportedStatus = status
        emit(mapOf("event" to "status", "status" to status))
    }

    private fun emitPosition() {
        val duration = player.duration
        emit(
            mapOf(
                "event" to "position",
                "positionMs" to player.currentPosition,
                "bufferedMs" to player.bufferedPosition,
                "durationMs" to if (duration == C.TIME_UNSET) 0L else duration
            )
        )
    }

    private fun emitVolume() {
        emit(
            mapOf(
                "event" to "volume",
                "volume" to player.volume.toDouble(),
                "muted" to (player.volume == 0f)
            )
        )
    }

    private fun emitError(code: String, message: String, detail: String?, recoverable: Boolean) {
        emit(
            mapOf(
                "event" to "error",
                "code" to code,
                "message" to message,
                "detail" to detail,
                "recoverable" to recoverable
            )
        )
    }

    fun dispose() {
        stopTicker()
        setSecureSurface(false)
        detachView()
        player.removeListener(this)
        player.release()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    private companion object {
        const val POSITION_INTERVAL_MS = 500L
        const val CONNECT_TIMEOUT_MS = 15_000
        const val READ_TIMEOUT_MS = 15_000
    }
}
