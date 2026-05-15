package byd

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object PermissionBridge {
    private const val CHANNEL = "byd/permissions"

    private lateinit var appContext: Context
    private var activity: Activity? = null

    fun register(binaryMessenger: BinaryMessenger, context: Context, activity: Activity?) {
        appContext = context.applicationContext
        this.activity = activity
        MethodChannel(binaryMessenger, CHANNEL).setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(statusMap())
            "openPermissionSettings" -> {
                openPermissionSettings(call.argument<String>("kind"))
                result.success(null)
            }
            "grantRecommendedPermissions" -> {
                openNextRecommendedPermission()
                result.success(statusMap())
            }
            else -> result.notImplemented()
        }
    }

    private fun statusMap(): Map<String, Any?> {
        val overlayReady = Settings.canDrawOverlays(appContext)
        val musicReady = isNotificationListenerEnabled()
        val vehicleReady = hasAllPermissions(
            "android.permission.BYDACQUISITION_SEND_BUFFER",
            "android.permission.BYDACQUISITION_SEND_FILE",
            "com.byd.ditrainer.permission.CORE",
        )
        val navigationSystemReady = hasAllPermissions(
            "android.permission.START_ACTIVITIES_FROM_BACKGROUND",
            "android.permission.WRITE_SECURE_SETTINGS",
            "android.permission.INJECT_EVENTS",
        )

        return mapOf(
            "musicAccess" to permissionItem(
                ready = musicReady,
                status = if (musicReady) "Ready" else "Needed",
                systemOnly = false,
            ),
            "systemOverlay" to permissionItem(
                ready = overlayReady,
                status = if (overlayReady) "Ready" else "Needed",
                systemOnly = false,
            ),
            "vehicleData" to permissionItem(
                ready = vehicleReady,
                status = if (vehicleReady) "Ready" else "System only",
                systemOnly = !vehicleReady,
            ),
            "navigationEmbed" to permissionItem(
                ready = navigationSystemReady,
                status = if (navigationSystemReady) "Ready" else "System only",
                systemOnly = !navigationSystemReady,
            ),
            "internet" to permissionItem(
                ready = hasAllPermissions(Manifest.permission.INTERNET),
                status = "Granted",
                systemOnly = false,
            ),
        )
    }

    private fun permissionItem(
        ready: Boolean,
        status: String,
        systemOnly: Boolean,
    ): Map<String, Any?> {
        return mapOf(
            "ready" to ready,
            "status" to status,
            "systemOnly" to systemOnly,
        )
    }

    private fun openNextRecommendedPermission() {
        when {
            !Settings.canDrawOverlays(appContext) -> openOverlaySettings()
            !isNotificationListenerEnabled() -> openNotificationListenerSettings()
            else -> openAppDetailsSettings()
        }
    }

    private fun openPermissionSettings(kind: String?) {
        when (kind) {
            "musicAccess" -> openNotificationListenerSettings()
            "systemOverlay" -> openOverlaySettings()
            "vehicleData", "navigationEmbed" -> openAppDetailsSettings()
            else -> openAppDetailsSettings()
        }
    }

    private fun openOverlaySettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${appContext.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        appContext.startActivity(intent)
    }

    private fun openNotificationListenerSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        appContext.startActivity(intent)
    }

    private fun openAppDetailsSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${appContext.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        appContext.startActivity(intent)
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            appContext.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(":").any {
            android.content.ComponentName.unflattenFromString(it)?.packageName ==
                appContext.packageName
        }
    }

    private fun hasAllPermissions(vararg permissions: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return permissions.all {
            appContext.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }
}
