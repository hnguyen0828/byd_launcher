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
        FileLogger.log(appContext, "AdbBridge registered; package=${appContext.packageName}")
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
     * Permission setup runner.
     *
     * Important:
     * - If this is executed by Runtime.exec() inside a sideloaded app, it usually runs as app uid=10xxx.
     * - It can only fully work when commands are run by a real ADB/shell bridge uid=2000(shell).
     * - The first command is always `id`; check the log for uid=2000(shell).
     */
    fun runKinexStylePermissionSetup(context: Context): Map<String, Any?> {
        FileLogger.log(context, "Starting permission setup; package=${context.packageName}")
        val commands = permissionCommands(context)
        FileLogger.log(context, "Permission command count: ${commands.size}")

        val results = commands.map { command ->
            FileLogger.log(context, "Running permission command: $command")
            runShell(command)
        }

        results.forEach { result ->
            FileLogger.log(
                context,
                "CMD result | exit=${result.exitCode} | started=${result.started} | command=${result.command} | output=${result.output}"
            )
        }

        val idOutput = results.firstOrNull()?.output.orEmpty()
        val shellUid = when {
            idOutput.contains("uid=2000") || idOutput.contains("uid=2000(shell)") -> "shell"
            idOutput.contains("uid=") -> "app_or_other"
            else -> "unknown"
        }

        val successCount = results.count { it.exitCode == 0 }
        val failed = results.filter { it.exitCode != 0 }

        FileLogger.log(
            context,
            "Permission setup finished; shellUid=$shellUid; success=$successCount/${results.size}; failed=${failed.size}"
        )

        return mapOf(
            "ok" to (failed.isEmpty() && shellUid == "shell"),
            "shellUid" to shellUid,
            "idOutput" to idOutput,
            "successCount" to successCount,
            "totalCount" to results.size,
            "shellAvailable" to results.any { it.started },
            "summary" to when {
                shellUid != "shell" ->
                    "Commands did not run as uid=2000(shell). A real ADB/shell bridge is required for notification/navigation grants."
                failed.isEmpty() ->
                    "System permission setup finished under shell uid."
                else ->
                    "${failed.size}/${results.size} shell commands failed."
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

        // Always verify the current uid first. For this flow to fully work, it must be uid=2000(shell).
        commands += "id"

        if (Build.VERSION.SDK_INT >= 33) {
            commands += "pm grant --user 0 $pkg android.permission.POST_NOTIFICATIONS"
        }

        // Notification listener / media session access.
        // Do NOT overwrite other enabled listeners; append this listener if missing.
        commands += "cmd notification allow_listener $listener"
        commands += "enabled=\"\$(settings get secure enabled_notification_listeners)\"; if [ \"\$enabled\" = \"null\" ] || [ -z \"\$enabled\" ]; then settings put secure enabled_notification_listeners \"$listener\"; elif echo \"\$enabled\" | grep -q \"$listener\"; then echo listener_already_enabled; else settings put secure enabled_notification_listeners \"\$enabled:$listener\"; fi"
        commands += "appops set --user 0 $pkg android:access_notifications allow"
        commands += "cmd appops set --user 0 $pkg android:access_notifications allow"

        // Overlay / floating controls.
        commands += "appops set --user 0 $pkg SYSTEM_ALERT_WINDOW allow"
        commands += "appops set --user 0 $pkg android:system_alert_window allow"
        commands += "cmd appops set --user 0 $pkg SYSTEM_ALERT_WINDOW allow"
        commands += "cmd appops set --user 0 $pkg android:system_alert_window allow"

        // Navigation / virtual-display helpers.
        // These are usually signature/system permissions; keep them for true shell/privileged bridge tests.
        commands += "pm grant --user 0 $pkg android.permission.WRITE_SECURE_SETTINGS"
        commands += "pm grant --user 0 $pkg android.permission.MEDIA_CONTENT_CONTROL"
        commands += "pm grant --user 0 $pkg android.permission.START_ACTIVITIES_FROM_BACKGROUND"
        commands += "pm grant --user 0 $pkg android.permission.INJECT_EVENTS"

        // Diagnostics only: BYDAUTO_* GET permissions are not changeable on this firmware.
        // Vehicle data is handled through BYD event/listener path, so we intentionally do not spam pm grant BYDAUTO_* here.
        commands += "dumpsys package $pkg | grep -i \"BYDAUTO\\|enabled_notification_listeners\\|granted=true\" | head -80"

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
            if (::appContext.isInitialized) {
                FileLogger.log(appContext, "Shell command failed to start: $command | ${error.javaClass.simpleName}: ${error.message}")
            }
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
