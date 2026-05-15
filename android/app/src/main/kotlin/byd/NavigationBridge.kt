package byd

import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object NavigationBridge {
    private const val CHANNEL = "byd/navigation"

    private lateinit var appContext: Context

    fun register(binaryMessenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        MethodChannel(binaryMessenger, CHANNEL).setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getNavigationApps" -> result.success(getNavigationApps())
            "launchNavigationApp" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                result.success(launchNavigationApp(packageName))
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
                val label = info.loadLabel(packageManager)?.toString()?.trim().orEmpty()
                if (label.isBlank()) return@mapNotNull null
                mapOf("label" to label, "packageName" to packageName)
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["label"]?.lowercase() }
    }

    private fun launchNavigationApp(packageName: String): Boolean {
        val packageManager = appContext.packageManager
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val intent = launchIntent ?: Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=")).apply {
            setPackage(packageName)
        }

        return try {
            appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }
}
