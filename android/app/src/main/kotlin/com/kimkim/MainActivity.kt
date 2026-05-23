package com.kimkim

import android.app.Activity
import android.content.Intent
import android.content.ComponentName
import android.content.pm.PackageManager
import android.provider.Settings
import android.net.Uri
import android.provider.OpenableColumns
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.Window
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import byd.VehicleBridge
import byd.MusicBridge
import byd.NavigationBridge
import byd.NavigationVirtualDisplayPlugin
import byd.NativeVehicleScenePlugin
import byd.NativeVehicleTexturePlugin
import byd.PermissionBridge
import byd.AdbBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var pendingWallpaperImportResult: MethodChannel.Result? = null
    private var lastSystemBarsDark: Boolean? = null
    private val systemUiHandler = Handler(Looper.getMainLooper())
    private val vehicleModelAssets = listOf(
        "assets/models/2024_byd_atto_3.glb",
        "assets/models/2024_byd_dolphin.glb",
        "assets/models/2024_byd_m6.glb",
        "assets/models/2024_byd_seagull.glb",
        "assets/models/2024_byd_seal.glb",
        "assets/models/2024_byd_seal_5_dm-i.glb",
        "assets/models/2024_byd_seal_u_dm-i.glb",
    )

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        enableHomeComponentIfNeeded()
        applyLauncherSystemUi()
    }

    override fun onResume() {
        super.onResume()
        applyLauncherSystemUi()
    }

    override fun onPostResume() {
        super.onPostResume()
        applyLauncherSystemUi()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyLauncherSystemUi()
        }
    }

    private fun applyLauncherSystemUi(dark: Boolean = lastSystemBarsDark ?: resolveInitialSystemBarsDark()) {
        lastSystemBarsDark = dark
        applyLauncherSystemUiNow(dark)

        // Flutter/DiLink/BYD shell can re-apply dark/immersive system-bar flags
        // after Activity resume, after Flutter first frame, and after window focus.
        // Re-assert the latest launcher theme for a longer window so Light mode
        // survives OEM post-processing on the real head unit.
        systemUiHandler.post { applyLauncherSystemUiNow(dark) }
        for (delay in listOf(80L, 250L, 900L, 1700L, 2600L)) {
            systemUiHandler.postDelayed({ applyLauncherSystemUiNow(dark) }, delay)
        }
    }

    private fun applyLauncherSystemUiNow(dark: Boolean) {
        val barOverlayColor = if (dark) {
            android.graphics.Color.argb(0x40, 0x00, 0x00, 0x00)
        } else {
            android.graphics.Color.argb(0x33, 0xFF, 0xFF, 0xFF)
        }
        val transparent = android.graphics.Color.TRANSPARENT

        // Kinex-style fix for BYD/DiLink: draw real Android system bars with
        // the launcher theme color instead of letting the OEM black surface stay
        // active. Keep the existing edge-to-edge layout flags unchanged so the
        // Flutter layout is not pushed or resized.
        window.clearFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS or
                WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION
        )
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)

        window.statusBarColor = barOverlayColor
        window.navigationBarColor = barOverlayColor

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            window.navigationBarDividerColor = transparent
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }

        var flags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        if (!dark && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            flags = flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
        if (!dark && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            flags = flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        window.decorView.systemUiVisibility = flags

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.show(WindowInsets.Type.systemBars())

                val lightAppearance =
                    WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                        WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
                val appearance = if (dark) 0 else lightAppearance

                controller.setSystemBarsAppearance(appearance, lightAppearance)
            }
        }
    }

    private fun resolveInitialSystemBarsDark(): Boolean {
        val storedTheme = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
            .getString("flutter.launcher.themeMode", "light")
        return when (storedTheme) {
            "dark" -> true
            "system" -> {
                val nightMode = resources.configuration.uiMode and
                    android.content.res.Configuration.UI_MODE_NIGHT_MASK
                nightMode == android.content.res.Configuration.UI_MODE_NIGHT_YES
            }
            else -> false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        vehicleModelAssets.forEach { asset ->
            NativeVehicleScenePlugin.preload(applicationContext, asset)
            NativeVehicleTexturePlugin.preload(applicationContext, asset)
        }

        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WALLPAPER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "importWallpapers" -> importWallpapers(result)
                "getWallpaperPath" -> result.success(wallpapersDir().absolutePath)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LAUNCHER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableHomeComponent" -> {
                    enableHomeComponentIfNeeded()
                    result.success(true)
                }
                "isDefaultLauncher", "isDefaultHomeApp" -> {
                    enableHomeComponentIfNeeded()
                    result.success(isDefaultHomeApp())
                }
                "openDefaultLauncherSettings", "openHomeSettings" -> {
                    enableHomeComponentIfNeeded()
                    openHomeSettings(result)
                }
                "applySystemBars" -> {
                    val dark = call.argument<Boolean>("dark") ?: resolveInitialSystemBarsDark()
                    applyLauncherSystemUi(dark)
                    result.success(true)
                }
                "goHome" -> {
                    goHome()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        VehicleBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
        PermissionBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
            this,
        )
        AdbBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
        MusicBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
        NavigationBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
        NavigationVirtualDisplayPlugin.register(
            flutterEngine,
            applicationContext,
            this,
        )
        NativeVehicleScenePlugin.register(flutterEngine)
        NativeVehicleTexturePlugin.register(flutterEngine, applicationContext)
    }


    private fun homeComponentName(): ComponentName {
        return ComponentName(this, MainActivity::class.java)
    }

    private fun enableHomeComponentIfNeeded() {
        val component = homeComponentName()
        val currentState = packageManager.getComponentEnabledSetting(component)
        if (currentState != PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
            packageManager.setComponentEnabledSetting(
                component,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    private fun isDefaultHomeApp(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addCategory(Intent.CATEGORY_DEFAULT)
        }
        val resolveInfo = packageManager.resolveActivity(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY,
        )
        return resolveInfo?.activityInfo?.packageName == packageName
    }

    private fun openHomeSettings(result: MethodChannel.Result) {
        val intents = listOf(
            Intent(Settings.ACTION_HOME_SETTINGS),
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
        )

        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    result.success(true)
                    return
                }
            } catch (_: Exception) {
            }
        }

        try {
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallback)
            result.success(true)
        } catch (error: Exception) {
            result.error(
                "HOME_SETTINGS_UNAVAILABLE",
                error.message ?: "Could not open default launcher settings.",
                null,
            )
        }
    }

    private fun goHome() {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun importWallpapers(result: MethodChannel.Result) {
        if (pendingWallpaperImportResult != null) {
            result.error(
                "IMPORT_IN_PROGRESS",
                "Wallpaper import is already in progress.",
                null,
            )
            return
        }

        pendingWallpaperImportResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }

        try {
            startActivityForResult(
                Intent.createChooser(intent, "Import Wallpapers"),
                WALLPAPER_IMPORT_REQUEST_CODE,
            )
        } catch (error: Exception) {
            pendingWallpaperImportResult = null
            result.error(
                "PICKER_UNAVAILABLE",
                error.message ?: "Could not open image picker.",
                null,
            )
        }
    }

    @Deprecated("Deprecated in Android, but still compatible with FlutterActivity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == WALLPAPER_IMPORT_REQUEST_CODE) {
            handleWallpaperImportResult(resultCode, data)
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun handleWallpaperImportResult(resultCode: Int, data: Intent?) {
        val result = pendingWallpaperImportResult ?: return
        pendingWallpaperImportResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(
                mapOf(
                    "imported" to 0,
                    "cancelled" to true,
                    "path" to wallpapersDir().absolutePath,
                ),
            )
            return
        }

        val uris = mutableListOf<Uri>()
        data.clipData?.let { clipData ->
            for (index in 0 until clipData.itemCount) {
                uris.add(clipData.getItemAt(index).uri)
            }
        }
        data.data?.let { uri -> uris.add(uri) }

        if (uris.isEmpty()) {
            result.success(
                mapOf(
                    "imported" to 0,
                    "cancelled" to false,
                    "path" to wallpapersDir().absolutePath,
                ),
            )
            return
        }

        var importedCount = 0
        val failedFiles = mutableListOf<String>()
        val targetDir = wallpapersDir().apply { mkdirs() }

        for (uri in uris.distinct()) {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: Exception) {
                // Some providers do not support persistable URI permission.
                // This is safe because we copy the file immediately.
            }

            try {
                val displayName = displayNameForUri(uri)
                val targetFile = uniqueWallpaperFile(targetDir, displayName, uri)
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                } ?: throw IllegalStateException("Could not open input stream.")
                importedCount++
            } catch (error: Exception) {
                failedFiles.add(error.message ?: uri.toString())
            }
        }

        result.success(
            mapOf(
                "imported" to importedCount,
                "failed" to failedFiles.size,
                "errors" to failedFiles.take(5),
                "path" to targetDir.absolutePath,
            ),
        )
    }

    private fun wallpapersDir(): File {
        return File(getExternalFilesDir(null), "wallpapers")
    }

    private fun displayNameForUri(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun uniqueWallpaperFile(dir: File, displayName: String?, uri: Uri): File {
        val safeBaseName = sanitizeFileName(
            displayName?.substringBeforeLast('.', missingDelimiterValue = displayName)
                ?.takeIf { it.isNotBlank() }
                ?: "wallpaper_${System.currentTimeMillis()}",
        )
        val extension = resolveImageExtension(displayName, uri)

        var candidate = File(dir, "$safeBaseName.$extension")
        var suffix = 1
        while (candidate.exists()) {
            candidate = File(dir, "${safeBaseName}_$suffix.$extension")
            suffix++
        }
        return candidate
    }

    private fun resolveImageExtension(displayName: String?, uri: Uri): String {
        val nameExtension = displayName
            ?.substringAfterLast('.', missingDelimiterValue = "")
            ?.lowercase(Locale.US)
            ?.takeIf { it in SUPPORTED_IMAGE_EXTENSIONS }

        if (nameExtension != null) return nameExtension

        return when (contentResolver.getType(uri)?.lowercase(Locale.US)) {
            "image/jpeg", "image/jpg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            "image/bmp" -> "bmp"
            else -> "jpg"
        }
    }

    private fun sanitizeFileName(value: String): String {
        return value
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trim('_')
            .take(80)
            .ifBlank { "wallpaper_${System.currentTimeMillis()}" }
    }

    companion object {
        private const val WALLPAPER_CHANNEL = "byd/wallpapers"
        private const val LAUNCHER_CHANNEL = "byd/launcher"
        private const val WALLPAPER_IMPORT_REQUEST_CODE = 9082
        private val SUPPORTED_IMAGE_EXTENSIONS = setOf(
            "jpg",
            "jpeg",
            "png",
            "webp",
            "gif",
            "bmp",
        )
    }
}
