package byd

import android.content.Context
import android.opengl.Matrix
import android.view.Choreographer
import com.google.android.filament.Camera
import com.google.android.filament.ColorGrading
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.SwapChain
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.android.filament.utils.Utils
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.max

object NativeVehicleTexturePlugin {
    private const val CHANNEL = "byd/native_vehicle_texture"
    private val renderers = mutableMapOf<Long, VehicleTextureRenderer>()
    private val preloadExecutor = Executors.newSingleThreadExecutor()

    fun preload(context: Context, asset: String) {
        val appContext = context.applicationContext
        val flutterAssetPath = normalizeFlutterAsset(asset)
        preloadExecutor.execute {
            runCatching {
                cachedTextureModelBytes(appContext, flutterAssetPath)
            }
        }
    }

    fun register(flutterEngine: FlutterEngine, appContext: Context) {
        val context = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(context, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "create" -> createRenderer(flutterEngine, appContext, call, result)
                "dispose" -> {
                    val id = call.argument<Number>("textureId")?.toLong()
                    if (id != null) {
                        renderers.remove(id)?.dispose()
                    }
                    result.success(null)
                }
                "update" -> {
                    val id = call.argument<Number>("textureId")?.toLong()
                    val renderer = id?.let { renderers[it] }
                    if (renderer == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    call.argument<String>("cameraOrbit")?.let(renderer::setCameraOrbit)
                    call.argument<Number>("color")?.let { renderer.setPaintColor(it.toLong()) }
                    call.argument<Boolean>("active")?.let(renderer::setActive)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createRenderer(
        flutterEngine: FlutterEngine,
        appContext: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val asset = args["asset"] as? String
        val width = (args["width"] as? Number)?.toInt() ?: 1
        val height = (args["height"] as? Number)?.toInt() ?: 1
        if (asset.isNullOrBlank() || width <= 0 || height <= 0) {
            result.error("bad_args", "Missing asset or invalid texture size", null)
            return
        }

        try {
            val textureEntry = flutterEngine.renderer.createSurfaceProducer()
            textureEntry.setSize(width, height)
            val renderer = VehicleTextureRenderer(
                context = appContext,
                textureEntry = textureEntry,
                params = args,
                width = width,
                height = height,
            )
            renderers[textureEntry.id()] = renderer
            result.success(textureEntry.id())
        } catch (error: Throwable) {
            result.error("native_texture_failed", error.message, null)
        }
    }
}

private class VehicleTextureRenderer(
    private val context: Context,
    private val textureEntry: TextureRegistry.SurfaceProducer,
    private val params: Map<*, *>,
    private val width: Int,
    private val height: Int,
) : Choreographer.FrameCallback {
    private val choreographer = Choreographer.getInstance()
    private val engine: Engine
    private val renderer: Renderer
    private val scene: com.google.android.filament.Scene
    private val view: View
    private val cameraEntity: Int
    private val camera: Camera
    private val swapChain: SwapChain
    private val materialProvider: UbershaderProvider
    private val assetLoader: AssetLoader
    private val resourceLoader: ResourceLoader
    private var asset: FilamentAsset? = null
    private var sunlight: Int = 0
    private var fillLight: Int = 0
    private var rimLight: Int = 0
    private var indirectLight: IndirectLight? = null
    private var colorGrading: ColorGrading? = null
    private var cameraOrbit = params["cameraOrbit"] as? String
    private var paintColor = (params["color"] as? Number)?.toLong()
    private var active = params["active"] as? Boolean ?: true
    private val quality = TextureRenderQuality.from(params["quality"] as? String)
    private var disposed = false
    private var lastRenderFrameNanos = 0L
    private var frameCallbackPosted = false

    init {
        Utils.init()
        engine = Engine.create()
        renderer = engine.createRenderer()
        scene = engine.createScene()
        view = engine.createView()
        cameraEntity = EntityManager.get().create()
        camera = engine.createCamera(cameraEntity)
        swapChain = engine.createSwapChain(textureEntry.surface)
        materialProvider = UbershaderProvider(engine)
        assetLoader = AssetLoader(engine, materialProvider, EntityManager.get())
        resourceLoader = ResourceLoader(engine, true)

        view.scene = scene
        view.camera = camera
        view.viewport = Viewport(0, 0, width, height)
        view.blendMode = View.BlendMode.TRANSLUCENT
        view.antiAliasing = quality.antiAliasing
        view.sampleCount = quality.sampleCount
        view.multiSampleAntiAliasingOptions =
            View.MultiSampleAntiAliasingOptions().apply {
                enabled = quality.sampleCount > 1
                sampleCount = quality.sampleCount
                customResolve = false
            }
        view.renderQuality = View.RenderQuality().apply {
            hdrColorBuffer = quality.hdrColorBuffer
        }
        view.setShadowingEnabled(false)
        view.ambientOcclusion = quality.ambientOcclusion
        renderer.clearOptions = Renderer.ClearOptions().apply {
            clear = true
            clearColor = floatArrayOf(0.0f, 0.0f, 0.0f, 0.0f)
        }

        colorGrading = ColorGrading.Builder()
            .toneMapping(ColorGrading.ToneMapping.FILMIC)
            .exposure(0.18f)
            .contrast(1.08f)
            .saturation(1.05f)
            .build(engine)
        view.colorGrading = colorGrading

        addStudioLighting()
        addSunlight()
        loadModel()
        updateCamera()
        postFrameCallbackIfNeeded()
    }

    override fun doFrame(frameTimeNanos: Long) {
        frameCallbackPosted = false
        if (disposed) return
        if (!active) return

        // BYD headunits can kill the app when Filament renders at full 60fps
        // while vehicle callbacks are also streaming. Cap native texture render to ~24fps
        // and never let a renderer exception take down the process.
        val minFrameIntervalNanos = 41_666_667L
        if (lastRenderFrameNanos != 0L && frameTimeNanos - lastRenderFrameNanos < minFrameIntervalNanos) {
            postFrameCallbackIfNeeded()
            return
        }
        lastRenderFrameNanos = frameTimeNanos

        try {
            if (renderer.beginFrame(swapChain, frameTimeNanos)) {
                renderer.render(view)
                renderer.endFrame()
                textureEntry.scheduleFrame()
            }
        } catch (error: Throwable) {
            try { FileLogger.log(context, "NativeVehicleTexture render error: ${error.javaClass.simpleName}: ${error.message}") } catch (_: Throwable) {}
        }
        postFrameCallbackIfNeeded()
    }

    fun dispose() {
        disposed = true
        choreographer.removeFrameCallback(this)
        frameCallbackPosted = false
        asset?.let { assetLoader.destroyAsset(it) }
        asset = null
        destroyLight(sunlight)
        destroyLight(fillLight)
        destroyLight(rimLight)
        indirectLight?.let { engine.destroyIndirectLight(it) }
        colorGrading?.let { engine.destroyColorGrading(it) }
        resourceLoader.destroy()
        assetLoader.destroy()
        materialProvider.destroy()
        engine.destroyCameraComponent(cameraEntity)
        EntityManager.get().destroy(cameraEntity)
        engine.destroyView(view)
        engine.destroyScene(scene)
        engine.destroyRenderer(renderer)
        engine.destroySwapChain(swapChain)
        textureEntry.release()
        engine.destroy()
    }

    fun setCameraOrbit(value: String) {
        cameraOrbit = value
        updateCamera()
    }

    fun setPaintColor(value: Long) {
        paintColor = value
        asset?.let(::applyBodyPaint)
    }

    fun setActive(value: Boolean) {
        if (active == value) return
        active = value
        if (active) {
            lastRenderFrameNanos = 0L
            updateCamera()
            postFrameCallbackIfNeeded()
        } else {
            choreographer.removeFrameCallback(this)
            frameCallbackPosted = false
        }
    }

    private fun postFrameCallbackIfNeeded() {
        if (disposed || !active || frameCallbackPosted) return
        frameCallbackPosted = true
        choreographer.postFrameCallback(this)
    }

    private fun loadModel() {
        val assetPath = normalizeFlutterAsset(params["asset"] as? String ?: return)
        val bytes = cachedTextureModelBytes(context, assetPath)
        val buffer = ByteBuffer.allocateDirect(bytes.size)
        buffer.put(bytes)
        buffer.rewind()

        asset = assetLoader.createAsset(buffer)?.also { loaded ->
            resourceLoader.loadResources(loaded)
            loaded.releaseSourceData()
            scene.addEntities(loaded.entities)
            transformToUnitCube(loaded)
            tuneRenderables(loaded)
            applyBodyPaint(loaded)
        }
    }

    private fun transformToUnitCube(loaded: FilamentAsset) {
        val box = loaded.boundingBox
        val center = box.center
        val half = box.halfExtent
        val maxExtent = max(half[0], max(half[1], half[2]))
        if (maxExtent <= 0.0f) return
        val scale = 1.0f / maxExtent
        val transform = FloatArray(16)
        Matrix.setIdentityM(transform, 0)
        Matrix.scaleM(transform, 0, scale, scale, scale)
        Matrix.translateM(transform, 0, -center[0], -center[1], -center[2])
        val transformManager = engine.transformManager
        val rootInstance = transformManager.getInstance(loaded.root)
        if (rootInstance != 0) {
            transformManager.setTransform(rootInstance, transform)
        }
    }

    private fun updateCamera() {
        val orbit = parseTextureCameraOrbit(cameraOrbit)
        val aspect = width.toDouble() / height.toDouble()
        val theta = Math.toRadians(orbit.thetaDegrees)
        val phi = Math.toRadians(orbit.phiDegrees)
        val distance = 4.10 + (orbit.radiusPercent / 100.0) * 1.20
        val x = kotlin.math.sin(theta) * kotlin.math.sin(phi) * distance
        val y = kotlin.math.cos(phi) * distance + 0.50
        val z = kotlin.math.cos(theta) * kotlin.math.sin(phi) * distance
        camera.setProjection(20.0, aspect, 0.05, 100.0, Camera.Fov.VERTICAL)
        camera.lookAt(x, y, z, 0.0, 0.08, 0.0, 0.0, 1.0, 0.0)
    }

    private fun applyBodyPaint(loaded: FilamentAsset) {
        val color = paintColor ?: return
        val r = ((color shr 16) and 0xFF) / 255.0f
        val g = ((color shr 8) and 0xFF) / 255.0f
        val b = (color and 0xFF) / 255.0f
        val renderableManager = engine.renderableManager
        val paintKeywords = listOf("bodypaint", "carpaint", "car_paint", "paint")

        loaded.renderableEntities.forEach { entity ->
            val entityName = loaded.getName(entity).orEmpty().lowercase()
            if (paintKeywords.none { entityName.contains(it) }) return@forEach
            val instance = renderableManager.getInstance(entity)
            if (instance == 0) return@forEach

            for (primitive in 0 until renderableManager.getPrimitiveCount(instance)) {
                val materialInstance = renderableManager.getMaterialInstanceAt(instance, primitive)
                val material = materialInstance.material
                if (material.hasParameter("baseColorFactor")) {
                    materialInstance.setParameter("baseColorFactor", r, g, b, 1.0f)
                }
                if (material.hasParameter("metallicFactor")) {
                    materialInstance.setParameter("metallicFactor", 0.62f)
                }
                if (material.hasParameter("roughnessFactor")) {
                    materialInstance.setParameter("roughnessFactor", 0.09f)
                }
            }
        }
    }

    private fun tuneRenderables(loaded: FilamentAsset) {
        val renderableManager = engine.renderableManager
        loaded.renderableEntities.forEach { entity ->
            val instance = renderableManager.getInstance(entity)
            if (instance != 0) {
                renderableManager.setCastShadows(instance, false)
                renderableManager.setReceiveShadows(instance, false)
            }
        }
    }

    private fun addSunlight() {
        sunlight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.SUN)
            .color(1.0f, 0.98f, 0.94f)
            .intensity(92_000.0f)
            .direction(-0.42f, -0.86f, -0.32f)
            .castShadows(false)
            .build(engine, sunlight)
        scene.addEntity(sunlight)
    }

    private fun addStudioLighting() {
        indirectLight = IndirectLight.Builder()
            .irradiance(
                1,
                floatArrayOf(
                    1.00f, 1.00f, 1.00f,
                    0.80f, 0.88f, 1.00f,
                    0.88f, 0.93f, 1.00f,
                    0.64f, 0.72f, 0.84f,
                    0.64f, 0.72f, 0.84f,
                    0.74f, 0.82f, 0.92f,
                    0.50f, 0.58f, 0.68f,
                    0.70f, 0.78f, 0.88f,
                    0.84f, 0.90f, 0.98f,
                ),
            )
            .intensity(62_000.0f)
            .build(engine)
        scene.indirectLight = indirectLight

        fillLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.82f, 0.90f, 1.0f)
            .intensity(44_000.0f)
            .direction(0.58f, -0.42f, 0.48f)
            .castShadows(false)
            .build(engine, fillLight)
        scene.addEntity(fillLight)

        rimLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.95f, 0.98f, 1.0f)
            .intensity(32_000.0f)
            .direction(-0.70f, -0.30f, 0.55f)
            .castShadows(false)
            .build(engine, rimLight)
        scene.addEntity(rimLight)
    }

    private fun destroyLight(entity: Int) {
        if (entity == 0) return
        scene.remove(entity)
        engine.destroyEntity(entity)
        EntityManager.get().destroy(entity)
    }
}

private val textureModelBytesCache = mutableMapOf<String, ByteArray>()

private fun cachedTextureModelBytes(context: Context, flutterAssetPath: String): ByteArray {
    return synchronized(textureModelBytesCache) {
        textureModelBytesCache[flutterAssetPath]
            ?: context.assets.open(flutterAssetPath).use { it.readBytes() }.also { bytes ->
                textureModelBytesCache[flutterAssetPath] = bytes
            }
    }
}

private fun normalizeFlutterAsset(asset: String): String {
    return if (asset.startsWith("flutter_assets/")) {
        asset
    } else {
        "flutter_assets/$asset"
    }
}

private fun parseTextureCameraOrbit(value: String?): TextureCameraOrbit {
    val parts = value.orEmpty().split(" ")
    fun clean(index: Int, suffix: String, fallback: Double): Double {
        return parts.getOrNull(index)
            ?.removeSuffix(suffix)
            ?.toDoubleOrNull()
            ?: fallback
    }

    return TextureCameraOrbit(
        thetaDegrees = clean(0, "deg", 318.0),
        phiDegrees = clean(1, "deg", 70.0),
        radiusPercent = clean(2, "%", 86.0),
    )
}

private data class TextureCameraOrbit(
    val thetaDegrees: Double,
    val phiDegrees: Double,
    val radiusPercent: Double,
)

private enum class TextureRenderQuality(
    val sampleCount: Int,
    val hdrColorBuffer: View.QualityLevel,
    val antiAliasing: View.AntiAliasing,
    val ambientOcclusion: View.AmbientOcclusion,
) {
    LOW(
        sampleCount = 1,
        hdrColorBuffer = View.QualityLevel.LOW,
        antiAliasing = View.AntiAliasing.NONE,
        ambientOcclusion = View.AmbientOcclusion.NONE,
    ),
    MEDIUM(
        sampleCount = 1,
        hdrColorBuffer = View.QualityLevel.MEDIUM,
        antiAliasing = View.AntiAliasing.FXAA,
        ambientOcclusion = View.AmbientOcclusion.NONE,
    ),
    HIGH(
        sampleCount = 4,
        hdrColorBuffer = View.QualityLevel.HIGH,
        antiAliasing = View.AntiAliasing.NONE,
        ambientOcclusion = View.AmbientOcclusion.SSAO,
    );

    companion object {
        fun from(value: String?): TextureRenderQuality {
            return when (value?.lowercase()) {
                "low" -> LOW
                "high" -> HIGH
                else -> MEDIUM
            }
        }
    }
}
