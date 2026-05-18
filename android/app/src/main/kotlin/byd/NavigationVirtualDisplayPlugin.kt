package byd

import android.app.Activity
import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.net.Uri
import android.os.SystemClock
import android.view.InputDevice
import android.view.InputEvent
import android.view.MotionEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

object NavigationVirtualDisplayPlugin {
    private const val CHANNEL = "byd/navigation_vd"
    private val sessions = mutableMapOf<Long, NavigationVirtualDisplaySession>()

    fun register(flutterEngine: FlutterEngine, context: Context, activity: Activity?) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "create" -> create(flutterEngine, context.applicationContext, activity, call, result)
                "resize" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    val width = call.argument<Number>("width")?.toInt() ?: 1
                    val height = call.argument<Number>("height")?.toInt() ?: 1
                    sessions[textureId]?.resize(width, height)
                    result.success(null)
                }
                "touch" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    val session = sessions[textureId]
                    if (session == null) {
                        result.success(false)
                    } else {
                        result.success(session.injectTouch(call.arguments as? Map<*, *>))
                    }
                }
                "dispose" -> {
                    val textureId = call.argument<Number>("textureId")?.toLong()
                    if (textureId != null) {
                        sessions.remove(textureId)?.dispose()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun create(
        flutterEngine: FlutterEngine,
        context: Context,
        activity: Activity?,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val packageName = args["packageName"] as? String
        val width = (args["width"] as? Number)?.toInt() ?: 1
        val height = (args["height"] as? Number)?.toInt() ?: 1
        val densityDpi = (args["densityDpi"] as? Number)?.toInt() ?: 240
        if (packageName.isNullOrBlank() || width <= 0 || height <= 0) {
            result.error("bad_args", "Missing navigation package or size", null)
            return
        }

        try {
            val textureEntry = flutterEngine.renderer.createSurfaceProducer()
            textureEntry.setSize(width, height)
            FileLogger.log(
                context,
                "NavigationVD create requested package=$packageName size=${width}x$height density=$densityDpi"
            )
            val session = NavigationVirtualDisplaySession(
                context = context,
                activity = activity,
                textureEntry = textureEntry,
                packageName = packageName,
                width = width,
                height = height,
                densityDpi = densityDpi,
            )
            sessions[textureEntry.id()] = session
            result.success(
                mapOf(
                    "textureId" to textureEntry.id(),
                    "displayId" to session.displayId,
                    "launchOk" to session.launchOk,
                ),
            )
        } catch (error: Throwable) {
            FileLogger.log(context, "NavigationVD create failed ${error.javaClass.simpleName}: ${error.message}")
            result.error("navigation_vd_failed", error.message, null)
        }
    }
}

private class NavigationVirtualDisplaySession(
    private val context: Context,
    private val activity: Activity?,
    private val textureEntry: TextureRegistry.SurfaceProducer,
    private val packageName: String,
    width: Int,
    height: Int,
    private val densityDpi: Int,
) {
    private val displayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private var downTime = 0L
    private var width = width.coerceAtLeast(1)
    private var height = height.coerceAtLeast(1)
    private var virtualDisplay: VirtualDisplay? = displayManager.createVirtualDisplay(
        "byd-navigation-${SystemClock.uptimeMillis()}",
        this.width,
        this.height,
        densityDpi,
        textureEntry.surface,
        DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC or
            DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
    )
    val displayId: Int? = virtualDisplay?.display?.displayId
    val launchOk: Boolean = launchNavigation()

    init {
        FileLogger.log(
            context,
            "NavigationVD session package=$packageName displayId=$displayId launchOk=$launchOk size=${this.width}x${this.height}"
        )
    }

    fun resize(width: Int, height: Int) {
        this.width = width.coerceAtLeast(1)
        this.height = height.coerceAtLeast(1)
        textureEntry.setSize(this.width, this.height)
        virtualDisplay?.resize(this.width, this.height, densityDpi)
        FileLogger.log(context, "NavigationVD resize texture=${textureEntry.id()} size=${this.width}x${this.height}")
    }

    fun injectTouch(args: Map<*, *>?): Boolean {
        val displayId = displayId ?: return false
        if (args == null) return false
        val actionName = args["action"] as? String ?: return false
        val x = (args["x"] as? Number)?.toFloat() ?: return false
        val y = (args["y"] as? Number)?.toFloat() ?: return false
        val action = when (actionName) {
            "down" -> MotionEvent.ACTION_DOWN
            "move" -> MotionEvent.ACTION_MOVE
            "up" -> MotionEvent.ACTION_UP
            "cancel" -> MotionEvent.ACTION_CANCEL
            else -> return false
        }
        val now = SystemClock.uptimeMillis()
        if (action == MotionEvent.ACTION_DOWN || downTime == 0L) {
            downTime = now
        }
        val event = MotionEvent.obtain(
            downTime,
            now,
            action,
            x.coerceIn(0f, width.toFloat()),
            y.coerceIn(0f, height.toFloat()),
            0,
        ).apply {
            source = InputDevice.SOURCE_TOUCHSCREEN
            try {
                javaClass.getMethod("setDisplayId", Int::class.javaPrimitiveType)
                    .invoke(this, displayId)
            } catch (_: Throwable) {
            }
        }
        return try {
            injectInputEvent(event)
        } finally {
            event.recycle()
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                downTime = 0L
            }
        }
    }

    fun dispose() {
        FileLogger.log(context, "NavigationVD dispose texture=${textureEntry.id()} displayId=$displayId")
        virtualDisplay?.release()
        virtualDisplay = null
        textureEntry.release()
    }

    private fun launchNavigation(): Boolean {
        val displayId = displayId ?: run {
            FileLogger.log(context, "NavigationVD launch skipped; no display for package=$packageName")
            return false
        }
        val intent = navigationIntent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val options = ActivityOptions.makeBasic().setLaunchDisplayId(displayId)
        return try {
            activity?.startActivity(intent, options.toBundle())
                ?: context.startActivity(intent, options.toBundle())
            FileLogger.log(context, "NavigationVD launch ok package=$packageName displayId=$displayId intent=$intent")
            true
        } catch (error: Throwable) {
            FileLogger.log(
                context,
                "NavigationVD launch failed package=$packageName displayId=$displayId ${error.javaClass.simpleName}: ${error.message}"
            )
            false
        }
    }

    private fun navigationIntent(): Intent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
        return launchIntent ?: Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=")).apply {
            setPackage(packageName)
        }
    }

    private fun injectInputEvent(event: InputEvent): Boolean {
        return try {
            val inputManagerClass = Class.forName("android.hardware.input.InputManager")
            val getInstance = inputManagerClass.getDeclaredMethod("getInstance")
            val inputManager = getInstance.invoke(null)
            val inject = inputManagerClass.getMethod(
                "injectInputEvent",
                InputEvent::class.java,
                Int::class.javaPrimitiveType,
            )
            inject.invoke(inputManager, event, 0) == true
        } catch (_: Throwable) {
            false
        }
    }
}
