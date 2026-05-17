package byd

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object FileLogger {

    private const val SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
    private const val DEBUG_MODE_KEY = "flutter.launcher.debugMode"
    private const val FILE_NAME = "debug.txt"

    fun log(context: Context, message: String) {
        if (!isDebugModeEnabled(context)) return

        try {
            val dir = File(
                context.getExternalFilesDir(null),
                "logs"
            )

            if (!dir.exists()) {
                dir.mkdirs()
            }

            val file = File(dir, FILE_NAME)

            val timestamp = SimpleDateFormat(
                "yyyy-MM-dd HH:mm:ss",
                Locale.US
            ).format(Date())

            file.appendText("[$timestamp] $message\n")
        } catch (_: Exception) {
        }
    }

    private fun isDebugModeEnabled(context: Context): Boolean {
        return try {
            context
                .getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(DEBUG_MODE_KEY, false)
        } catch (_: Exception) {
            false
        }
    }
}
