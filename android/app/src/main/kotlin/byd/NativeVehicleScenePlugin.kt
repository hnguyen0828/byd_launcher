package byd

import android.content.Context
import android.graphics.Color
import android.view.Choreographer
import android.view.SurfaceView
import android.view.View
import com.google.android.filament.Camera
import com.google.android.filament.EntityManager
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.Skybox
import com.google.android.filament.utils.ModelViewer
import com.google.android.filament.utils.Utils
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.nio.ByteBuffer
import kotlin.math.pow

object NativeVehicleScenePlugin {
    private const val VIEW_TYPE = "byd/native_vehicle_scene"

    fun preload(context: Context, asset: String) {
        val flutterAssetPath = normalizeFlutterAsset(asset)
        Thread {
            cachedModelBytes(context.applicationContext, flutterAssetPath)
        }.start()
    }

    fun register(flutterEngine: FlutterEngine) {
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(VIEW_TYPE, NativeVehicleSceneFactory())
    }
}

private val modelBytesCache = mutableMapOf<String, ByteArray>()

private fun normalizeFlutterAsset(asset: String): String {
    return if (asset.startsWith("flutter_assets/")) {
        asset
    } else {
        "flutter_assets/$asset"
    }
}

private fun cachedModelBytes(context: Context, flutterAssetPath: String): ByteArray {
    return synchronized(modelBytesCache) {
        modelBytesCache[flutterAssetPath]
            ?: context.assets.open(flutterAssetPath).use { it.readBytes() }.also { bytes ->
                modelBytesCache[flutterAssetPath] = bytes
            }
    }
}

private class NativeVehicleSceneFactory :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<String, Any>()
        return NativeVehicleSceneView(context, params)
    }
}

private class NativeVehicleSceneView(
    private val context: Context,
    private val params: Map<*, *>,
) : PlatformView, Choreographer.FrameCallback {
    private val surfaceView = SurfaceView(context)
    private val choreographer = Choreographer.getInstance()
    private val sceneBackgroundColor = parseColor(
        params["backgroundColor"] as? Number,
        0xFF121B26,
    )
    private val sceneBackgroundComponents = colorComponents(sceneBackgroundColor)
    private var modelViewer: ModelViewer? = null
    private var sunlight: Int = 0
    private var fillLight: Int = 0
    private var rimLight: Int = 0
    private var indirectLight: IndirectLight? = null
    private var disposed = false
    private var lastRenderFrameNanos = 0L

    init {
        Utils.init()

        modelViewer = ModelViewer(surfaceView).also { viewer ->
            surfaceView.setOnTouchListener(viewer)
            viewer.scene.skybox = Skybox.Builder()
                .color(
                    sceneBackgroundComponents[0],
                    sceneBackgroundComponents[1],
                    sceneBackgroundComponents[2],
                    1.0f,
                )
                .build(viewer.engine)
            viewer.view.antiAliasing = com.google.android.filament.View.AntiAliasing.FXAA
            viewer.view.setShadowingEnabled(false)
            viewer.view.ambientOcclusion = com.google.android.filament.View.AmbientOcclusion.NONE
            viewer.renderer.clearOptions = Renderer.ClearOptions().apply {
                clear = true
                clearColor = floatArrayOf(
                    sceneBackgroundComponents[0],
                    sceneBackgroundComponents[1],
                    sceneBackgroundComponents[2],
                    1.0f,
                )
            }
            addStudioLighting(viewer)
            addSunlight(viewer)
            loadModel(viewer)
        }

        choreographer.postFrameCallback(this)
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        disposed = true
        choreographer.removeFrameCallback(this)
        surfaceView.setOnTouchListener(null)
        modelViewer?.let { viewer ->
            destroyLight(viewer, sunlight)
            destroyLight(viewer, fillLight)
            destroyLight(viewer, rimLight)
            sunlight = 0
            fillLight = 0
            rimLight = 0
            indirectLight?.let { light ->
                viewer.scene.indirectLight = null
                viewer.engine.destroyIndirectLight(light)
            }
            indirectLight = null
            viewer.destroyModel()
        }
        modelViewer = null
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (disposed) {
            return
        }

        // Cap PlatformView render to ~24fps on BYD headunit to avoid GPU/process kill
        // after the GLB is fully loaded.
        val minFrameIntervalNanos = 41_666_667L
        if (lastRenderFrameNanos != 0L && frameTimeNanos - lastRenderFrameNanos < minFrameIntervalNanos) {
            choreographer.postFrameCallback(this)
            return
        }
        lastRenderFrameNanos = frameTimeNanos

        try {
            modelViewer?.let { viewer ->
                updateCamera(viewer)
                viewer.render(frameTimeNanos)
            }
        } catch (error: Throwable) {
            try { FileLogger.log(context, "NativeVehicleScene render error: ${error.javaClass.simpleName}: ${error.message}") } catch (_: Throwable) {}
        }
        choreographer.postFrameCallback(this)
    }

    private fun loadModel(viewer: ModelViewer) {
        val asset = params["asset"] as? String ?: return
        val flutterAssetPath = normalizeFlutterAsset(asset)

        val bytes = cachedModelBytes(context, flutterAssetPath)
        val buffer = ByteBuffer.allocateDirect(bytes.size)
        buffer.put(bytes)
        buffer.rewind()
        viewer.loadModelGlb(buffer)
        viewer.transformToUnitCube()
        tuneRenderables(viewer)
        applyBodyPaint(viewer)
        updateCamera(viewer)
    }

    private fun updateCamera(viewer: ModelViewer) {
        val width = surfaceView.width.takeIf { it > 0 } ?: return
        val height = surfaceView.height.takeIf { it > 0 } ?: return
        val orbit = parseCameraOrbit(params["cameraOrbit"] as? String)
        val aspect = width.toDouble() / height.toDouble()
        val theta = Math.toRadians(orbit.thetaDegrees)
        val phi = Math.toRadians(orbit.phiDegrees)
        val distance = 1.30 + (orbit.radiusPercent / 100.0) * 0.42
        val x = kotlin.math.sin(theta) * kotlin.math.sin(phi) * distance
        val y = kotlin.math.cos(phi) * distance + 0.34
        val z = kotlin.math.cos(theta) * kotlin.math.sin(phi) * distance

        viewer.camera.setProjection(17.0, aspect, 0.05, 100.0, Camera.Fov.VERTICAL)
        viewer.camera.lookAt(
            x,
            y,
            z,
            0.0,
            0.22,
            0.0,
            0.0,
            1.0,
            0.0,
        )
    }

    private fun parseCameraOrbit(value: String?): CameraOrbit {
        val parts = value.orEmpty().split(" ")
        fun clean(index: Int, suffix: String, fallback: Double): Double {
            return parts.getOrNull(index)
                ?.removeSuffix(suffix)
                ?.toDoubleOrNull()
                ?: fallback
        }

        return CameraOrbit(
            thetaDegrees = clean(0, "deg", 318.0),
            phiDegrees = clean(1, "deg", 70.0),
            radiusPercent = clean(2, "%", 86.0),
        )
    }

    private fun parseColor(value: Number?, fallback: Long): Int {
        return (value?.toLong() ?: fallback).toInt()
    }

    private fun colorComponents(color: Int): FloatArray {
        return floatArrayOf(
            srgbToLinear(Color.red(color) / 255.0f),
            srgbToLinear(Color.green(color) / 255.0f),
            srgbToLinear(Color.blue(color) / 255.0f),
        )
    }

    private fun srgbToLinear(component: Float): Float {
        return component.toDouble().pow(2.0).toFloat()
    }

    private fun applyBodyPaint(viewer: ModelViewer) {
        val color = (params["color"] as? Number)?.toLong() ?: return
        val r = ((color shr 16) and 0xFF) / 255.0f
        val g = ((color shr 8) and 0xFF) / 255.0f
        val b = (color and 0xFF) / 255.0f
        val asset = viewer.asset ?: return
        val renderableManager = viewer.engine.renderableManager
        val paintKeywords = listOf("bodypaint", "carpaint", "car_paint", "paint")

        asset.renderableEntities.forEach { entity ->
            val entityName = asset.getName(entity).orEmpty().lowercase()
            if (paintKeywords.none { entityName.contains(it) }) {
                return@forEach
            }

            val instance = renderableManager.getInstance(entity)
            if (instance == 0) {
                return@forEach
            }

            for (primitive in 0 until renderableManager.getPrimitiveCount(instance)) {
                val materialInstance = renderableManager.getMaterialInstanceAt(instance, primitive)
                val material = materialInstance.material
                if (material.hasParameter("baseColorFactor")) {
                    materialInstance.setParameter("baseColorFactor", r, g, b, 1.0f)
                }
                if (material.hasParameter("metallicFactor")) {
                    materialInstance.setParameter("metallicFactor", 0.22f)
                }
                if (material.hasParameter("roughnessFactor")) {
                    materialInstance.setParameter("roughnessFactor", 0.15f)
                }
                if (material.hasParameter("clearCoatFactor")) {
                    materialInstance.setParameter("clearCoatFactor", 1.0f)
                }
                if (material.hasParameter("clearCoatRoughnessFactor")) {
                    materialInstance.setParameter("clearCoatRoughnessFactor", 0.08f)
                }
            }
        }
    }

    private fun addSunlight(viewer: ModelViewer) {
        sunlight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.SUN)
            .color(1.0f, 0.98f, 0.94f)
            .intensity(108_000.0f)
            .direction(-0.42f, -0.86f, -0.32f)
            .castShadows(false)
            .build(viewer.engine, sunlight)
        viewer.scene.addEntity(sunlight)
    }

    private fun addStudioLighting(viewer: ModelViewer) {
        indirectLight = IndirectLight.Builder()
            .irradiance(
                1,
                floatArrayOf(
                    1.00f, 1.00f, 1.00f,
                    0.78f, 0.88f, 1.00f,
                    0.86f, 0.92f, 1.00f,
                    0.62f, 0.72f, 0.84f,
                    0.62f, 0.72f, 0.84f,
                    0.72f, 0.80f, 0.90f,
                    0.50f, 0.58f, 0.68f,
                    0.68f, 0.76f, 0.86f,
                    0.82f, 0.88f, 0.96f,
                ),
            )
            .intensity(76_000.0f)
            .build(viewer.engine)
        viewer.scene.indirectLight = indirectLight

        fillLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.82f, 0.90f, 1.0f)
            .intensity(56_000.0f)
            .direction(0.58f, -0.42f, 0.48f)
            .castShadows(false)
            .build(viewer.engine, fillLight)
        viewer.scene.addEntity(fillLight)

        rimLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.95f, 0.98f, 1.0f)
            .intensity(42_000.0f)
            .direction(-0.70f, -0.30f, 0.55f)
            .castShadows(false)
            .build(viewer.engine, rimLight)
        viewer.scene.addEntity(rimLight)
    }

    private fun tuneRenderables(viewer: ModelViewer) {
        val asset = viewer.asset ?: return
        val renderableManager = viewer.engine.renderableManager
        asset.renderableEntities.forEach { entity ->
            val instance = renderableManager.getInstance(entity)
            if (instance != 0) {
                renderableManager.setCastShadows(instance, false)
                renderableManager.setReceiveShadows(instance, false)
            }
        }
    }

    private fun destroyLight(viewer: ModelViewer, entity: Int) {
        if (entity == 0) {
            return
        }

        viewer.scene.remove(entity)
        viewer.engine.destroyEntity(entity)
        EntityManager.get().destroy(entity)
    }
}

private data class CameraOrbit(
    val thetaDegrees: Double,
    val phiDegrees: Double,
    val radiusPercent: Double,
)
