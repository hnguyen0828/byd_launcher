package byd

import android.app.Activity
import android.app.ActivityOptions
import android.content.ComponentName
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
    private var lastTouchX = 0f
    private var lastTouchY = 0f
    private var inputManagerInjectionAvailable: Boolean? = null
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
        val rawX = (args["x"] as? Number)?.toFloat() ?: return false
        val rawY = (args["y"] as? Number)?.toFloat() ?: return false
        val x = rawX.coerceIn(0f, (width - 1).coerceAtLeast(1).toFloat())
        val y = rawY.coerceIn(0f, (height - 1).coerceAtLeast(1).toFloat())
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
            lastTouchX = x
            lastTouchY = y
        }
        val event = MotionEvent.obtain(
            downTime,
            now,
            action,
            x,
            y,
            1.0f,
            1.0f,
            0,
            1.0f,
            1.0f,
            0,
            0,
        ).apply {
            source = InputDevice.SOURCE_TOUCHSCREEN
            try {
                javaClass.getMethod("setDisplayId", Int::class.javaPrimitiveType)
                    .invoke(this, displayId)
            } catch (_: Throwable) {
            }
        }

        val injected = try {
            injectInputEvent(event)
        } finally {
            event.recycle()
        }

        val fallbackInjected = if (!injected) {
            injectTouchViaShell(displayId, action, x, y)
        } else {
            true
        }

        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            downTime = 0L
        }
        if (action != MotionEvent.ACTION_CANCEL) {
            lastTouchX = x
            lastTouchY = y
        }
        return fallbackInjected
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
        val intent = navigationIntent().addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                Intent.FLAG_ACTIVITY_NO_ANIMATION,
        )
        val options = ActivityOptions.makeBasic().setLaunchDisplayId(displayId)
        val normalLaunchOk = try {
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
        if (normalLaunchOk) return true

        return launchNavigationViaShell(displayId, intent)
    }

    private fun navigationIntent(): Intent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
        return launchIntent ?: Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=")).apply {
            setPackage(packageName)
        }
    }

    private fun launchNavigationViaShell(displayId: Int, intent: Intent): Boolean {
        val component = intent.component ?: resolveLaunchComponent()
        val command = if (component != null) {
            "am start --display $displayId -n ${component.flattenToShortString().shellQuote()}"
        } else {
            "am start --display $displayId -a android.intent.action.VIEW -d ${"geo:0,0?q=".shellQuote()} ${packageName.shellQuote()}"
        }
        val result = LocalAdbClient.runShellCommandWithCandidates(context, command)
        val ok = result.started && result.exitCode == 0 &&
            !result.output.contains("Error:", ignoreCase = true) &&
            !result.output.contains("Exception", ignoreCase = true)
        FileLogger.log(
            context,
            "NavigationVD shell launch ok=$ok displayId=$displayId package=$packageName exit=${result.exitCode} output=${result.output}"
        )
        return ok
    }

    private fun resolveLaunchComponent(): ComponentName? {
        return context.packageManager.getLaunchIntentForPackage(packageName)?.component
    }

    private fun String.shellQuote(): String {
        return "'${replace("'", "'\\''")}'"
    }

    private fun injectInputEvent(event: InputEvent): Boolean {
        if (inputManagerInjectionAvailable == false) return false
        return try {
            val inputManagerClass = Class.forName("android.hardware.input.InputManager")
            val getInstance = inputManagerClass.getDeclaredMethod("getInstance")
            val inputManager = getInstance.invoke(null)
            val inject = inputManagerClass.getMethod(
                "injectInputEvent",
                InputEvent::class.java,
                Int::class.javaPrimitiveType,
            )
            // WAIT_FOR_FINISH is much more reliable than ASYNC for a secondary display.
            val ok = inject.invoke(inputManager, event, 2) == true
            inputManagerInjectionAvailable = ok
            ok
        } catch (error: Throwable) {
            inputManagerInjectionAvailable = false
            FileLogger.log(
                context,
                "NavigationVD InputManager inject disabled ${error.javaClass.simpleName}: ${error.message}"
            )
            false
        }
    }

    private fun injectTouchViaShell(displayId: Int, action: Int, x: Float, y: Float): Boolean {
        // Most non-system launcher builds cannot call InputManager.injectInputEvent.
        // Fall back to the local ADB bridge so taps still reach Google Maps/Waze on the VirtualDisplay.
        val command = when (action) {
            MotionEvent.ACTION_UP -> "input -d $displayId tap ${x.toInt()} ${y.toInt()}"
            MotionEvent.ACTION_MOVE -> {
                val dx = kotlin.math.abs(x - lastTouchX)
                val dy = kotlin.math.abs(y - lastTouchY)
                if (dx < 2f && dy < 2f) return false
                "input -d $displayId swipe ${lastTouchX.toInt()} ${lastTouchY.toInt()} ${x.toInt()} ${y.toInt()} 80"
            }
            MotionEvent.ACTION_CANCEL -> return true
            else -> return false
        }
        val result = LocalAdbClient.runShellCommandWithCandidates(context, command)
        val ok = result.started && result.exitCode == 0 &&
            !result.output.contains("Error:", ignoreCase = true) &&
            !result.output.contains("Exception", ignoreCase = true) &&
            !result.output.contains("Unknown option", ignoreCase = true)
        FileLogger.log(
            context,
            "NavigationVD shell input ok=$ok displayId=$displayId action=$action x=${x.toInt()} y=${y.toInt()} exit=${result.exitCode} output=${result.output}"
        )
        return ok
    }
}
