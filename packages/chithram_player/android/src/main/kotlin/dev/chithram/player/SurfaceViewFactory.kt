package dev.chithram.player

import android.content.Context
import android.view.SurfaceView
import android.view.View
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

private class SurfacePlatformView(context: Context, private val host: PlayerHost?) : PlatformView {
    private val surfaceView = SurfaceView(context)

    init {
        host?.attach(surfaceView)
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        host?.detach(surfaceView)
    }
}
