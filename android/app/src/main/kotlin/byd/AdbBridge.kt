package byd

import android.content.ComponentName
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

object AdbBridge {
    private const val CHANNEL = "byd/adb"
    private const val COMMAND_TIMEOUT_SECONDS = 8L

    private lateinit var appContext: Context

    fun register(binaryMessenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        MethodChannel(binaryMessenger, CHANNEL).setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "runPermissionSetup" -> result.success(runKinexStylePermissionSetup(appContext))
            "getPermissionCommands" -> result.success(permissionCommands(appContext).joinToString("\n"))
            else -> result.notImplemented()
        }
    }

    /**
     * Kinex-style one-button flow:
     * - Try to execute the same shell-level grant/appops/settings commands.
     * - On a normal sideloaded app these may fail because the process is not `shell`/system.
     * - On BYD images that expose a shell bridge/privileged context, they can succeed silently.
     */
    fun runKinexStylePermissionSetup(context: Context): Map<String, Any?> {
        val commands = permissionCommands(context)
        val results = commands.map { command -> runShell(command) }
        val successCount = results.count { it.exitCode == 0 }
        val failed = results.filter { it.exitCode != 0 }

        return mapOf(
            "ok" to failed.isEmpty(),
            "successCount" to successCount,
            "totalCount" to results.size,
            "shellAvailable" to results.any { it.started },
            "summary" to if (failed.isEmpty()) {
                "System permission setup finished"
            } else {
                "${failed.size}/${results.size} shell commands failed. This is expected if the app is not running as shell/system."
            },
            "commands" to commands.joinToString("\n"),
            "results" to results.map { it.toMap() },
        )
    }

    private fun permissionCommands(context: Context): List<String> {
        val pkg = context.packageName
        val listener = ComponentName(context, MusicNotificationListenerService::class.java)
            .flattenToString()

        val commands = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= 33) {
            commands += "pm grant $pkg android.permission.POST_NOTIFICATIONS"
        }

        // Notification listener / media session access.
        commands += "cmd notification allow_listener $listener"
        commands += "settings put secure enabled_notification_listeners $listener"
        commands += "appops set $pkg android:access_notifications allow"

        // Overlay / floating controls.
        commands += "appops set $pkg SYSTEM_ALERT_WINDOW allow"
        commands += "appops set $pkg android:system_alert_window allow"

        // BYD/OEM permissions. These may be refused on non-whitelisted apps.
        commands += "pm grant $pkg android.permission.BYDACQUISITION_SEND_BUFFER"
        commands += "pm grant $pkg android.permission.BYDACQUISITION_SEND_FILE"
        commands += "pm grant $pkg com.byd.ditrainer.permission.CORE"
        commands += "pm grant $pkg android.permission.BYDAUTO_BODYWORK_GET"
        commands += "pm grant $pkg android.permission.BYDAUTO_BODYWORK_COMMON"
        commands += "pm grant $pkg android.permission.BYDAUTO_STATISTIC_GET"

        // Navigation embedding / input injection. Usually signature/system only.
        commands += "pm grant $pkg android.permission.WRITE_SECURE_SETTINGS"
        commands += "pm grant $pkg android.permission.INJECT_EVENTS"
        commands += "pm grant $pkg android.permission.MEDIA_CONTENT_CONTROL"
        commands += "pm grant $pkg android.permission.START_ACTIVITIES_FROM_BACKGROUND"

        return commands
    }

    private fun runShell(command: String): ShellCommandResult {
        return try {
            val process = ProcessBuilder("sh", "-c", command)
                .redirectErrorStream(true)
                .start()
            val finished = process.waitFor(COMMAND_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            val output = BufferedReader(InputStreamReader(process.inputStream)).use { it.readText() }.trim()
            val exitCode = if (finished) process.exitValue() else -124
            if (!finished) process.destroyForcibly()
            ShellCommandResult(
                command = command,
                started = true,
                exitCode = exitCode,
                output = output.take(4000),
            )
        } catch (error: Throwable) {
            ShellCommandResult(
                command = command,
                started = false,
                exitCode = -1,
                output = error.message.orEmpty().take(4000),
            )
        }
    }

    private data class ShellCommandResult(
        val command: String,
        val started: Boolean,
        val exitCode: Int,
        val output: String,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "command" to command,
            "started" to started,
            "exitCode" to exitCode,
            "output" to output,
        )
    }
}
