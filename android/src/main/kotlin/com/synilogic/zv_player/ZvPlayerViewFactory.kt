package com.synilogic.zv_player

import android.content.Context
import android.graphics.Color
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Creates the native video surface for an already-running player.
 *
 * The view is a window onto a session it does not own: disposing it detaches
 * the surface and leaves playback untouched, which is what lets the same
 * session continue through a rotation, a mini player or PiP.
 */
class ZvPlayerViewFactory(
    private val playerLookup: (Int) -> ZvPlayerInstance?
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val playerId = (params?.get("playerId") as? Number)?.toInt()
        val instance = playerId?.let(playerLookup)
        return ZvPlayerPlatformView(context, instance)
    }
}

@OptIn(UnstableApi::class)
private class ZvPlayerPlatformView(
    context: Context,
    private val instance: ZvPlayerInstance?
) : PlatformView {

    private val playerView: PlayerView? = instance?.createView()

    private val view: View = playerView ?: View(context).apply {
        // No player for this id: a black surface is the honest fallback, and
        // Flutter already surfaces the error state separately.
        setBackgroundColor(Color.BLACK)
    }

    override fun getView(): View = view

    override fun dispose() {
        // Detach only this view, never whichever view is current.
        playerView?.let { instance?.detachView(it) }
    }
}
