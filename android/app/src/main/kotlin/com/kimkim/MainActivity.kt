package com.kimkim

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
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
        applyLauncherSystemUi()
    }

    override fun onResume() {
        super.onResume()
        applyLauncherSystemUi()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyLauncherSystemUi()
        }
    }

    private fun applyLauncherSystemUi() {
        window.statusBarColor = android.graphics.Color.parseColor("#F1F5FA")
        window.navigationBarColor = android.graphics.Color.parseColor("#F1F5FA")

        var flags = android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            android.view.View.SYSTEM_UI_FLAG_FULLSCREEN or
            android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            flags = flags or android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            flags = flags or android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        window.decorView.systemUiVisibility = flags

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(android.view.WindowInsets.Type.systemBars())
                controller.systemBarsBehavior =
                    android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
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
