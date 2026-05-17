package byd

import android.Manifest
import android.app.Activity
import android.content.ComponentName
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
    private const val REQUEST_POST_NOTIFICATIONS = 8801
    private const val REQUEST_VEHICLE_PERMISSIONS = 8802

    private lateinit var appContext: Context
    private var activity: Activity? = null
    private var lastGrantReport: Map<String, Any?>? = null

    fun register(binaryMessenger: BinaryMessenger, context: Context, activity: Activity?) {
        appContext = context.applicationContext
        FileLogger.log(appContext, "PermissionBridge registered; package=${appContext.packageName}")
        this.activity = activity
        MethodChannel(binaryMessenger, CHANNEL).setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        FileLogger.log(appContext, "PermissionBridge method: ${call.method}")
        when (call.method) {
            "getStatus" -> result.success(statusMap())
            "openPermissionSettings" -> {
                openPermissionSettings(call.argument<String>("kind"))
                result.success(null)
            }
            "grantRecommendedPermissions" -> {
                lastGrantReport = runOneTapPermissionSetup()
                result.success(statusMap())
            }
            "getLastGrantReport" -> result.success(lastGrantReport)
            else -> result.notImplemented()
        }
    }

    private fun runOneTapPermissionSetup(): Map<String, Any?> {
        FileLogger.log(appContext, "Grant all permissions clicked")
        FileLogger.log(appContext, "Status before grant: ${rawStatusMap()}")
        requestPostNotificationsIfNeeded()

        // Vehicle data on this BYD firmware is handled through BYD event/listener callbacks.
        // Runtime requestPermissions() for BYDAUTO_* does not grant Speed/Statistic/Gearbox GET
        // and can add noisy prompts, so keep Grant All focused on Music/Overlay/Navigation.
        val vehicleRequestReport = mapOf(
            "requested" to false,
            "reason" to "Skipped; BYD vehicle data uses event/listener path"
        )

        val shellReport = AdbBridge.runKinexStylePermissionSetup(appContext)
        FileLogger.log(appContext, "Shell report: $shellReport")

        // Fallback: if shell-level commands did not fully enable user-grantable permissions,
        // open the next relevant Settings page just like Kinex's visible permission flow.
        FileLogger.log(appContext, "Overlay status after shell: ${Settings.canDrawOverlays(appContext)}")
        FileLogger.log(appContext, "Notification listener status after shell: ${isNotificationListenerEnabled()}")

        if (!Settings.canDrawOverlays(appContext)) {
            FileLogger.log(appContext, "Opening overlay settings fallback")
            openOverlaySettings()
        } else if (!isNotificationListenerEnabled()) {
            FileLogger.log(appContext, "Opening notification listener settings fallback")
            openNotificationListenerSettings(preferDetail = true)
        }

        val after = rawStatusMap()
        FileLogger.log(appContext, "Status after grant flow: $after")
        return mapOf(
            "vehicleRuntimeRequest" to vehicleRequestReport,
            "shell" to shellReport,
            "statusAfter" to after,
        )
    }

    private fun statusMap(): Map<String, Any?> {
        val raw = rawStatusMap()
        FileLogger.log(appContext, "Permission status requested: $raw")
        return mapOf(
            "musicAccess" to permissionItem(
                ready = raw.musicReady,
                status = if (raw.musicReady) "Ready" else "Needs setup",
                systemOnly = false,
            ),
            "systemOverlay" to permissionItem(
                ready = raw.overlayReady,
                status = if (raw.overlayReady) "Ready" else "Needs setup",
                systemOnly = false,
            ),
            "vehicleData" to permissionItem(
                ready = raw.vehicleReady,
                status = if (raw.vehicleReady) "Ready" else "OEM locked",
                systemOnly = !raw.vehicleReady,
            ),
            "navigationEmbed" to permissionItem(
                ready = raw.navigationSystemReady,
                status = if (raw.navigationSystemReady) "Ready" else "System locked",
                systemOnly = !raw.navigationSystemReady,
            ),
            "internet" to permissionItem(
                ready = hasAllPermissions(Manifest.permission.INTERNET),
                status = "Granted",
                systemOnly = false,
            ),
            "lastGrantReport" to lastGrantReport,
        )
    }

    private fun rawStatusMap(): RawPermissionStatus {
        val overlayReady = Settings.canDrawOverlays(appContext)
        val musicReady = isNotificationListenerEnabled()
        val vehicleReady = hasAnyPermissions(
            "android.permission.BYDACQUISITION_SEND_BUFFER",
            "android.permission.BYDACQUISITION_SEND_FILE",
            "com.byd.ditrainer.permission.CORE",
            "android.permission.BYDAUTO_BODYWORK_GET",
            "android.permission.BYDAUTO_BODYWORK_COMMON",
            "android.permission.BYDAUTO_STATISTIC_GET",
            "android.permission.BYDAUTO_SPEED_GET",
            "android.permission.BYDAUTO_GEARBOX_GET",
            "android.permission.BYDAUTO_AC_COMMON",
        )
        val navigationSystemReady = hasAnyPermissions(
            "android.permission.START_ACTIVITIES_FROM_BACKGROUND",
            "android.permission.WRITE_SECURE_SETTINGS",
            "android.permission.INJECT_EVENTS",
            "android.permission.MEDIA_CONTENT_CONTROL",
        )
        return RawPermissionStatus(
            overlayReady = overlayReady,
            musicReady = musicReady,
            vehicleReady = vehicleReady,
            navigationSystemReady = navigationSystemReady,
        )
    }

    private fun permissionItem(
        ready: Boolean,
        status: String,
        systemOnly: Boolean,
    ): Map<String, Any?> = mapOf(
        "ready" to ready,
        "status" to status,
        "systemOnly" to systemOnly,
    )

    private fun openPermissionSettings(kind: String?) {
        when (kind) {
            "musicAccess" -> openNotificationListenerSettings(preferDetail = true)
            "systemOverlay" -> openOverlaySettings()
            "vehicleData" -> openAppDetailsSettings()
            "navigationEmbed" -> openDeveloperOptions()
            else -> openAppDetailsSettings()
        }
    }

    private fun requestVehiclePermissions(): Map<String, Any?> {
        val currentActivity = activity
        val permissions = vehicleRuntimePermissions()
        val statesBefore = permissionGrantStates(permissions)
        FileLogger.log(appContext, "Requesting BYD vehicle runtime permissions; activityAvailable=${currentActivity != null}; permissions=${permissions.joinToString()}")
        FileLogger.log(appContext, "BYD vehicle permission states before request: $statesBefore")

        if (currentActivity == null) {
            FileLogger.log(appContext, "Cannot request BYD vehicle permissions because Activity is null")
            return mapOf(
                "requested" to false,
                "reason" to "Activity is null",
                "permissions" to permissions.toList(),
                "statesBefore" to statesBefore,
            )
        }

        val notGranted = permissions.filter {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                false
            } else {
                appContext.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
            }
        }.toTypedArray()

        if (notGranted.isEmpty()) {
            FileLogger.log(appContext, "All BYD vehicle runtime permissions already appear granted")
            return mapOf(
                "requested" to false,
                "reason" to "Already granted",
                "permissions" to permissions.toList(),
                "statesBefore" to statesBefore,
            )
        }

        return try {
            FileLogger.log(appContext, "Calling Activity.requestPermissions for BYD vehicle permissions: ${notGranted.joinToString()}")
            currentActivity.requestPermissions(notGranted, REQUEST_VEHICLE_PERMISSIONS)
            mapOf(
                "requested" to true,
                "requestCode" to REQUEST_VEHICLE_PERMISSIONS,
                "permissions" to notGranted.toList(),
                "statesBefore" to statesBefore,
            )
        } catch (error: Throwable) {
            FileLogger.log(appContext, "BYD vehicle requestPermissions failed: ${error.javaClass.simpleName}: ${error.message}")
            mapOf(
                "requested" to false,
                "reason" to "${error.javaClass.simpleName}: ${error.message}",
                "permissions" to notGranted.toList(),
                "statesBefore" to statesBefore,
            )
        }
    }

    private fun vehicleRuntimePermissions(): Array<String> = arrayOf(
        "android.permission.BYDAUTO_BODYWORK_GET",
        "android.permission.BYDAUTO_BODYWORK_COMMON",
        "android.permission.BYDAUTO_STATISTIC_GET",
        "android.permission.BYDAUTO_SPEED_GET",
        "android.permission.BYDAUTO_GEARBOX_GET",
        "android.permission.BYDAUTO_AC_COMMON",
        "android.permission.BYDACQUISITION_SEND_BUFFER",
        "android.permission.BYDACQUISITION_SEND_FILE",
        "com.byd.ditrainer.permission.CORE",
    )

    private fun permissionGrantStates(permissions: Array<String>): Map<String, Boolean> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return permissions.associateWith { true }
        }
        return permissions.associateWith {
            appContext.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestPostNotificationsIfNeeded() {
        if (Build.VERSION.SDK_INT < 33) {
            FileLogger.log(appContext, "POST_NOTIFICATIONS not required on SDK ${Build.VERSION.SDK_INT}")
            return
        }
        val currentActivity = activity ?: return
        if (appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            FileLogger.log(appContext, "POST_NOTIFICATIONS already granted")
            return
        }
        FileLogger.log(appContext, "Requesting POST_NOTIFICATIONS runtime permission")
        currentActivity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    private fun openOverlaySettings() {
        FileLogger.log(appContext, "Opening overlay settings")
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${appContext.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        appContext.startActivity(intent)
    }

    private fun openNotificationListenerSettings(preferDetail: Boolean) {
        FileLogger.log(appContext, "Opening notification listener settings; preferDetail=$preferDetail")
        val component = ComponentName(appContext, MusicNotificationListenerService::class.java)
        val intent = if (preferDetail && Build.VERSION.SDK_INT >= 30) {
            Intent("android.settings.NOTIFICATION_LISTENER_DETAIL_SETTINGS").apply {
                putExtra("android.provider.extra.NOTIFICATION_LISTENER_COMPONENT_NAME", component.flattenToString())
            }
        } else {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        try {
            appContext.startActivity(intent)
        } catch (_: Throwable) {
            appContext.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun openDeveloperOptions() {
        FileLogger.log(appContext, "Opening developer options settings")
        try {
            appContext.startActivity(
                Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Throwable) {
            openAppDetailsSettings()
        }
    }

    private fun openAppDetailsSettings() {
        FileLogger.log(appContext, "Opening app details settings")
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
            ComponentName.unflattenFromString(it)?.packageName == appContext.packageName
        }
    }

    private fun hasAllPermissions(vararg permissions: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return permissions.all {
            appContext.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasAnyPermissions(vararg permissions: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return permissions.any {
            appContext.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private data class RawPermissionStatus(
        val overlayReady: Boolean,
        val musicReady: Boolean,
        val vehicleReady: Boolean,
        val navigationSystemReady: Boolean,
    )
}
