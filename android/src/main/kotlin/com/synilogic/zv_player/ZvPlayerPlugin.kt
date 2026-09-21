package com.synilogic.zv_player

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.provider.Settings
import android.os.Looper
import android.view.WindowManager
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Entry point for ZV Player on Android.
 *
 * Owns the registry of live players and the platform-view factory. Players are
 * created here rather than by the view, so one playback session can survive a
 * view being detached - which is what makes fullscreen, the mini player and
 * Picture-in-Picture possible without a second ExoPlayer instance.
 */
class ZvPlayerPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private lateinit var globalChannel: MethodChannel
    private lateinit var messenger: BinaryMessenger
    private lateinit var applicationContext: Context

    private val players = mutableMapOf<Int, ZvPlayerInstance>()
    private var nextPlayerId = 1
    private var activity: Activity? = null
    private var originalBrightness: Float? = null

    /** Single background thread for capability probing; see onMethodCall. */
    private val probeExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        /** Live plugin instances, so the host Activity can forward PiP changes. */
        private val instances = mutableSetOf<ZvPlayerPlugin>()

        /**
         * Call from the host Activity's `onPictureInPictureModeChanged`.
         * Android reports the mode on the Activity, not on the player.
         */
        @JvmStatic
        fun notifyPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
            instances.forEach { plugin ->
                plugin.players.values.forEach { it.onPictureInPictureModeChanged(isInPictureInPictureMode) }
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        messenger = binding.binaryMessenger
        applicationContext = binding.applicationContext
        globalChannel = MethodChannel(messenger, "zv_player/global")
        globalChannel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            "zv_player/view",
            ZvPlayerViewFactory { playerId -> players[playerId] }
        )
        instances.add(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        instances.remove(this)
        players.values.forEach { it.dispose() }
        players.clear()
        probeExecutor.shutdownNow()
        globalChannel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        players.values.forEach { it.attachActivity(binding.activity) }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Keep playing across rotation; only the Activity reference is refreshed.
        activity = null
        players.values.forEach { it.attachActivity(null) }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        players.values.forEach { it.attachActivity(binding.activity) }
    }

    override fun onDetachedFromActivity() {
        activity = null
        players.values.forEach { it.attachActivity(null) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> {
                val id = nextPlayerId++
                players[id] = ZvPlayerInstance(
                    context = applicationContext,
                    messenger = messenger,
                    playerId = id,
                    activityProvider = { activity }
                )
                result.success(id)
            }

            "dispose" -> {
                val id = call.argument<Int>("playerId")
                players.remove(id)?.dispose()
                result.success(null)
            }

            // Window-level brightness. This never touches the device setting:
            // the override lives on the app window and dies with it.
            "getBrightness" -> {
                val window = activity?.window
                if (window == null) {
                    result.success(null)
                } else {
                    val value = window.attributes.screenBrightness
                    // Following system brightness is supported, not a missing
                    // capability. Read the setting without changing it.
                    val current = if (value >= 0f) value else
                        Settings.System.getInt(applicationContext.contentResolver,
                            Settings.System.SCREEN_BRIGHTNESS, 128) / 255f
                    result.success(current.coerceIn(0f, 1f).toDouble())
                }
            }

            "setBrightness" -> {
                val window = activity?.window
                val requested = (call.argument<Number>("brightness"))?.toFloat()
                if (window == null || requested == null) {
                    result.success(null)
                } else {
                    val params = window.attributes
                    if (originalBrightness == null) originalBrightness = params.screenBrightness
                    params.screenBrightness = requested.coerceIn(0f, 1f)
                    window.attributes = params
                    result.success(null)
                }
            }

            "restoreBrightness" -> {
                val window = activity?.window
                if (window != null) {
                    val params = window.attributes
                    params.screenBrightness =
                        originalBrightness ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    originalBrightness = null
                    window.attributes = params
                }
                result.success(null)
            }

            "capabilities" -> {
                // Decoder enumeration is slow. Answer instantly if it has
                // already been computed, otherwise do it off the main thread so
                // player creation never blocks the UI.
                val cached = ZvCapabilities.cachedOrNull()
                if (cached != null) {
                    result.success(cached)
                } else {
                    probeExecutor.execute {
                        val probed = ZvCapabilities.probe(applicationContext)
                        mainHandler.post { result.success(probed) }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}
