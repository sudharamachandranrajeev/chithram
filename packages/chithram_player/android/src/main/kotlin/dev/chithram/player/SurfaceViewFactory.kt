@file:OptIn(UnstableApi::class)

package dev.chithram.player

import android.content.Context
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Creates a SurfaceView bound to the player named in the creation params. */
class SurfaceViewFactory(private val lookup: (Int) -> PlayerHost?) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val playerId = (args as? Map<*, *>)?.get("playerId") as? Int ?: -1
        return SurfacePlatformView(context, lookup(playerId))
    }
}

/**
 * The video surface with Media3's SubtitleView over it, which draws text and
 * bitmap subtitles in the system caption style (Settings > Accessibility).
 */
private class SurfacePlatformView(context: Context, private val host: PlayerHost?) : PlatformView {
    private val surfaceView = SurfaceView(context)
    private val subtitleView = SubtitleView(context).apply {
        setUserDefaultStyle()
        setUserDefaultTextSize()
    }
    // Sized by PlayerHost.setAspect; centred in the platform view.
    private val shape = AspectRatioFrameLayout(context).apply {
        addView(surfaceView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }
    private val root = FrameLayout(context).apply {
        val match = ViewGroup.LayoutParams.MATCH_PARENT
        addView(shape, FrameLayout.LayoutParams(match, match, android.view.Gravity.CENTER))
        addView(subtitleView, FrameLayout.LayoutParams(match, match))
    }

    init {
        host?.attach(surfaceView, subtitleView, shape)
    }

    override fun getView(): View = root

    override fun dispose() {
        host?.detach(surfaceView)
    }
}
