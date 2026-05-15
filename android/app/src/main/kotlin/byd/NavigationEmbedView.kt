package byd

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NavigationEmbedViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        return NavigationEmbedView(context, params?.get("packageName") as? String)
    }
}

private class NavigationEmbedView(
    private val context: Context,
    private val packageName: String?,
) : PlatformView {
    private val root = FrameLayout(context)
    private var activityView: Any? = null

    init {
        root.setBackgroundColor(Color.TRANSPARENT)
        startEmbeddedNavigation()
    }

    override fun getView(): View = root

    override fun dispose() {
        try {
            activityView?.javaClass?.getMethod("release")?.invoke(activityView)
        } catch (_: Exception) {
        }
        activityView = null
    }

    private fun startEmbeddedNavigation() {
        if (packageName.isNullOrBlank()) {
            showFallback("No navigation app selected")
            return
        }

        val intent = navigationIntent(packageName)
        if (intent == null) {
            showFallback("Navigation app is not available")
            return
        }

        try {
            val activityViewClass = Class.forName("android.app.ActivityView")
            val constructor = activityViewClass.getConstructor(Context::class.java)
            val embeddedView = constructor.newInstance(context)

            if (embeddedView !is View) {
                showFallback("Embedded navigation is not supported")
                return
            }

            activityView = embeddedView
            root.addView(
                embeddedView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            root.post {
                try {
                    embeddedView.javaClass.getMethod("startActivity", Intent::class.java)
                        .invoke(embeddedView, intent)
                } catch (_: Exception) {
                    showFallback("Unable to embed navigation app")
                }
            }
        } catch (_: Exception) {
            showFallback("Embedded navigation is not supported on this system")
        }
    }

    private fun navigationIntent(packageName: String): Intent? {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
        return (launchIntent ?: Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=")).apply {
            setPackage(packageName)
        }).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun showFallback(message: String) {
        root.removeAllViews()
        val text = TextView(context).apply {
            setTextColor(Color.rgb(183, 194, 207))
            textSize = 14f
            this.text = message
            gravity = android.view.Gravity.CENTER
        }
        root.addView(
            text,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }
}
