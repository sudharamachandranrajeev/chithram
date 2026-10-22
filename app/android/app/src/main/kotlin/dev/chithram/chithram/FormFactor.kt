package dev.chithram.chithram

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration

/** What kind of device this is, decided once from the device and never from the window size. */
object FormFactor {
    /** "tv" on a television or a box with no touchscreen, else "phone" (tablets included). */
    fun detect(context: Context): String {
        val pm = context.packageManager
        val uiMode = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val tv = uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        return if (tv) "tv" else "phone"
    }
}
