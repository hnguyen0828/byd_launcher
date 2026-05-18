package byd

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

object NavigationBridge {
    private const val CHANNEL = "byd/navigation"

    private lateinit var appContext: Context

    fun register(binaryMessenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        FileLogger.log(appContext, "NavigationBridge registered; package=${appContext.packageName}")
        MethodChannel(binaryMessenger, CHANNEL).setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getNavigationApps" -> result.success(getNavigationApps())
            "getLaunchableApps" -> result.success(getLaunchableApps())
            "launchNavigationApp" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                result.success(launchNavigationApp(packageName))
            }
            "launchApp" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                result.success(launchApp(packageName))
            }
            else -> result.notImplemented()
        }
    }

    private fun getNavigationApps(): List<Map<String, String>> {
        val packageManager = appContext.packageManager
        val geoIntent = Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q="))
        return packageManager
            .queryIntentActivities(geoIntent, 0)
            .mapNotNull { info ->
                val activityInfo = info.activityInfo ?: return@mapNotNull null
                val packageName = activityInfo.packageName ?: return@mapNotNull null
                if (packageName == appContext.packageName) return@mapNotNull null
                val label = info.loadLabel(packageManager)?.toString()?.trim().orEmpty()
                if (label.isBlank()) return@mapNotNull null
                mapOf("label" to label, "packageName" to packageName)
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["label"]?.lowercase() }
            .also { apps ->
                FileLogger.log(
                    appContext,
                    "Navigation apps: ${apps.joinToString { "${it["label"]}=${it["packageName"]}" }}"
                )
            }
    }

    private fun getLaunchableApps(): List<Map<String, String>> {
        val packageManager = appContext.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        return packageManager
            .queryIntentActivities(launcherIntent, 0)
            .mapNotNull { info ->
                val activityInfo = info.activityInfo ?: return@mapNotNull null
                val packageName = activityInfo.packageName ?: return@mapNotNull null
                if (packageName == appContext.packageName) return@mapNotNull null
                val label = info.loadLabel(packageManager)?.toString()?.trim().orEmpty()
                if (label.isBlank()) return@mapNotNull null
                mapOf(
                    "label" to label,
                    "packageName" to packageName,
                    "iconBase64" to loadIconBase64(info.loadIcon(packageManager)),
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["label"]?.lowercase() }
    }

    private fun launchNavigationApp(packageName: String): Boolean {
        val ok = launchApp(packageName) || launchGeoApp(packageName)
        FileLogger.log(appContext, "Navigation launch package=$packageName ok=$ok")
        return ok
    }

    private fun launchApp(packageName: String): Boolean {
        val packageManager = appContext.packageManager
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        return try {
            appContext.startActivity(launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun launchGeoApp(packageName: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=")).apply {
            setPackage(packageName)
        }
        return try {
            appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun loadIconBase64(drawable: android.graphics.drawable.Drawable): String {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
