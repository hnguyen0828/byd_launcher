package byd

import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.hardware.BYDAutoManager
import android.hardware.IBYDAutoDevice
import android.hardware.IBYDAutoEvent
import android.hardware.bydauto.BYDAutoDeviceManager
import android.hardware.bydauto.ac.AbsBYDAutoAcListener
import android.hardware.bydauto.ac.BYDAutoAcDevice
import android.hardware.bydauto.bodywork.AbsBYDAutoBodyworkListener
import android.hardware.bydauto.bodywork.BYDAutoBodyworkDevice
import android.hardware.bydauto.gearbox.AbsBYDAutoGearboxListener
import android.hardware.bydauto.gearbox.BYDAutoGearboxDevice
import android.hardware.bydauto.speed.AbsBYDAutoSpeedListener
import android.hardware.bydauto.speed.BYDAutoSpeedDevice
import android.hardware.bydauto.statistic.AbsBYDAutoStatisticListener
import android.hardware.bydauto.statistic.BYDAutoStatisticDevice
import android.hardware.bydauto.tyre.AbsBYDAutoTyreListener
import android.hardware.bydauto.tyre.BYDAutoTyreDevice
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import kotlin.math.roundToInt
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VehicleBridge {
    companion object {
        private const val CHANNEL_NAME = "byd.vehicle"
        private const val EVENT_CHANNEL_NAME = "byd.vehicle/events"

        private lateinit var appContext: Context
        private lateinit var bydContext: Context
        private val mainHandler = Handler(Looper.getMainLooper())
        private var eventSink: EventChannel.EventSink? = null

        private var listenersRegistered = false
        private var globalManagerListenerRegistered = false
        private var deviceManagerEnabled = false

        private var attemptedSpeedDevice = false
        private var attemptedStatisticDevice = false
        private var attemptedTyreDevice = false
        private var attemptedGearboxDevice = false
        private var attemptedAcDevice = false
        private var attemptedBodyworkDevice = false

        private var speedDevice: BYDAutoSpeedDevice? = null
        private var statisticDevice: BYDAutoStatisticDevice? = null
        private var tyreDevice: BYDAutoTyreDevice? = null
        private var gearboxDevice: BYDAutoGearboxDevice? = null
        private var acDevice: BYDAutoAcDevice? = null
        private var bodyworkDevice: BYDAutoBodyworkDevice? = null
        private var deviceManager: BYDAutoDeviceManager? = null

        private var speedListener: AbsBYDAutoSpeedListener? = null
        private var statisticListener: AbsBYDAutoStatisticListener? = null
        private var tyreListener: AbsBYDAutoTyreListener? = null
        private var gearboxListener: AbsBYDAutoGearboxListener? = null
        private var acListener: AbsBYDAutoAcListener? = null
        private var bodyworkListener: AbsBYDAutoBodyworkListener? = null
        private var globalManagerListener: BYDAutoManager.OnBYDAutoListener? = null

        private const val SNAPSHOT_EMIT_INTERVAL_MS = 3000L
        private const val REALTIME_LOG_INTERVAL_MS = 10000L
        private const val TYRE_POLL_INTERVAL_MS = 8000L

        // Confirmed from BYD realtime bus on Sealion 6 / DiLink 3.0 logs.
        // Do NOT use heuristic mapping for statistic values; unrelated statistic
        // events share the same device id and cause fuel/battery/range to jump.
        private const val DEVICE_GEARBOX = 1011
        private const val DEVICE_SPEED = 1013
        private const val DEVICE_STATISTIC = 1014
        private const val DEVICE_TYRE = 1016
        private const val EVENT_STAT_PERCENT = 1134559272
        private const val EVENT_STAT_FUEL_RANGE = 1147142160
        private const val EVENT_STAT_OUTSIDE_TEMP = 1151336480
        private const val EVENT_STAT_FUEL_RANGE_ALT = 1147142192
        private var lastSnapshotEmitMs = 0L
        private var pendingSnapshotEmit = false
        private var lastRealtimeLogMs = 0L
        private var lastSnapshotLogMs = 0L
        private var lastTyrePollMs = 0L
        private val discoveryLastLogMs = mutableMapOf<String, Long>()

        // Cache-only vehicle state. Direct getters on BYD ROM require *_GET permissions.
        private var cachedAvailable = false
        private var cachedSpeedKmh: Double? = null
        private var cachedGear: String? = null
        private var cachedFuelRangeKm: Int? = null
        private var cachedElectricRangeKm: Int? = null
        private var cachedFuelPercent: Int? = null
        private var cachedBatteryPercent: Double? = null

        // Statistic events are noisy on BYD DiLink: the same device id can emit
        // transient/counter values. Keep only sane, debounced dashboard values.
        private var lastAcceptedFuelRangeKm: Int? = null
        private var lastAcceptedBatteryPercent: Int? = null
        private var lastAcceptedFuelPercent: Int? = null
        private var lastFuelRangeAcceptMs = 0L
        private var lastBatteryPercentAcceptMs = 0L
        private var cachedOutsideTemperatureC: Int? = null
        private var cachedTyreSystemState: Int? = null
        private var cachedTyreTemperatureState: Int? = null
        private val cachedTyres = mutableMapOf<Int, CachedTyre>()
        private val cachedWindows = mutableMapOf<Int, CachedWindow>()
        private val cachedDoors = mutableMapOf<Int, Int>()
        private var cachedPowerLevel: Int? = null
        private var cachedBatteryVoltageLevel: Int? = null

        fun register(binaryMessenger: BinaryMessenger, context: Context) {
            appContext = context.applicationContext
            bydContext = BydPermissionBypassContext(appContext)
            FileLogger.log(appContext, "VehicleBridge registered; package=${appContext.packageName}; using BydPermissionBypassContext")
            MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler(::handleMethodCall)
            EventChannel(binaryMessenger, EVENT_CHANNEL_NAME).setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        FileLogger.log(appContext, "Vehicle event stream attached")
                        ensureListenersRegistered()
                        emitSnapshot()
                    }

                    override fun onCancel(arguments: Any?) {
                        FileLogger.log(appContext, "Vehicle event stream detached")
                        eventSink = null
                    }
                },
            )
        }

        private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
            FileLogger.log(appContext, "VehicleBridge method: ${call.method}")
            when (call.method) {
                "ping" -> result.success(true)
                "getVehicleSnapshot" -> {
                    ensureListenersRegistered()
                    result.success(getVehicleSnapshot())
                }
                else -> result.notImplemented()
            }
        }

        private fun getVehicleSnapshot(): Map<String, Any?> {
            val snapshotLogNow = SystemClock.elapsedRealtime()
            if (snapshotLogNow - lastSnapshotLogMs >= 5000L) {
                lastSnapshotLogMs = snapshotLogNow
                FileLogger.log(
                    appContext,
                    "Returning cached vehicle snapshot: speed=$cachedSpeedKmh, gear=$cachedGear, " +
                        "fuelRange=$cachedFuelRangeKm, electricRange=$cachedElectricRangeKm, " +
                        "fuelPercent=$cachedFuelPercent, batteryPercent=$cachedBatteryPercent, " +
                        "outsideTemp=$cachedOutsideTemperatureC, tyres=${cachedTyres.size}"
                )
            }

            pollTyreSnapshotThrottled()

            val safeFuelRange = sanitizeDisplayRangeKm(cachedFuelRangeKm)
            val safeElectricRange = sanitizeDisplayRangeKm(cachedElectricRangeKm)
            return mapOf(
                "available" to cachedAvailable,
                "speedKmh" to cachedSpeedKmh,
                "gear" to cachedGear,
                "rangeKm" to listOfNotNull(safeFuelRange, safeElectricRange)
                    .takeIf { it.isNotEmpty() }
                    ?.sum(),
                "fuelRangeKm" to safeFuelRange,
                "electricRangeKm" to safeElectricRange,
                "fuelPercent" to cachedFuelPercent,
                "batteryPercent" to cachedBatteryPercent,
                "outsideTemperatureC" to cachedOutsideTemperatureC,
                "tpms" to mapOf(
                    "systemState" to cachedTyreSystemState,
                    "temperatureState" to cachedTyreTemperatureState,
                    "frontLeft" to tyreSnapshotFromCache(BYDAutoTyreDevice.TYRE_COMMAND_AREA_LEFT_FRONT, 1, 0),
                    "frontRight" to tyreSnapshotFromCache(BYDAutoTyreDevice.TYRE_COMMAND_AREA_RIGHT_FRONT, 2),
                    "rearLeft" to tyreSnapshotFromCache(BYDAutoTyreDevice.TYRE_COMMAND_AREA_LEFT_REAR, 3),
                    "rearRight" to tyreSnapshotFromCache(BYDAutoTyreDevice.TYRE_COMMAND_AREA_RIGHT_REAR, 4),
                ),
                "bodywork" to mapOf(
                    "powerLevel" to cachedPowerLevel,
                    "batteryVoltageLevel" to cachedBatteryVoltageLevel,
                    "windows" to cachedWindows.mapKeys { it.key.toString() }.mapValues { (_, v) ->
                        mapOf("state" to v.state, "percent" to v.percent)
                    },
                    "doors" to cachedDoors.mapKeys { it.key.toString() },
                ),
            )
        }

        private fun ensureDeviceInstances() {
            FileLogger.log(appContext, "Ensuring BYD device instances for listener/probe mode")

            if (!attemptedSpeedDevice) {
                attemptedSpeedDevice = true
                speedDevice = safe("get speed device") { BYDAutoSpeedDevice.getInstance(bydContext) }
            }
            if (!attemptedStatisticDevice) {
                attemptedStatisticDevice = true
                statisticDevice = safe("get statistic device") { BYDAutoStatisticDevice.getInstance(bydContext) }
            }
            if (!attemptedTyreDevice) {
                attemptedTyreDevice = true
                tyreDevice = safe("get tyre device") { BYDAutoTyreDevice.getInstance(bydContext) }
            }
            if (!attemptedGearboxDevice) {
                attemptedGearboxDevice = true
                gearboxDevice = safe("get gearbox device") { BYDAutoGearboxDevice.getInstance(bydContext) }
            }
            if (!attemptedAcDevice) {
                attemptedAcDevice = true
                acDevice = safe("get ac device") { BYDAutoAcDevice.getInstance(bydContext) }
            }
            if (!attemptedBodyworkDevice) {
                attemptedBodyworkDevice = true
                bodyworkDevice = safe("get bodywork device via getInstance") { BYDAutoBodyworkDevice.getInstance(bydContext) }
                if (bodyworkDevice == null) {
                    bodyworkDevice = createBodyworkDeviceReflectively()
                }
            }
            if (deviceManager == null) {
                deviceManager = safe("get BYDAutoDeviceManager") { BYDAutoDeviceManager.getInstance(bydContext) }
            }

            cachedAvailable = listOf(speedDevice, statisticDevice, tyreDevice, gearboxDevice, acDevice, bodyworkDevice).any { it != null }

            FileLogger.log(
                appContext,
                "BYD devices for listener/probe mode: speed=${speedDevice != null}, " +
                    "statistic=${statisticDevice != null}, tyre=${tyreDevice != null}, " +
                    "gearbox=${gearboxDevice != null}, ac=${acDevice != null}, bodywork=${bodyworkDevice != null}, manager=${deviceManager != null}"
            )

            logDeviceMethods("speed", speedDevice)
            logDeviceMethods("statistic", statisticDevice)
            logDeviceMethods("tyre", tyreDevice)
            logDeviceMethods("gearbox", gearboxDevice)
            logDeviceMethods("ac", acDevice)
            logDeviceMethods("bodywork", bodyworkDevice)
        }

        private fun ensureListenersRegistered() {
            if (listenersRegistered) {
                FileLogger.log(appContext, "BYD listeners already registered; using cached state only")
                return
            }

            FileLogger.log(appContext, "Registering BYD listeners in realtime probe mode")
            listenersRegistered = true
            ensureDeviceInstances()

            speedListener = safe("create speed listener") { createSpeedListener() }
            statisticListener = safe("create statistic listener") { createStatisticListener() }
            tyreListener = safe("create tyre listener") { createTyreListener() }
            gearboxListener = safe("create gearbox listener") { createGearboxListener() }
            acListener = safe("create ac listener") { createAcListener() }
            bodyworkListener = safe("create bodywork listener") { createBodyworkListener() }

            // Safe statistic mode:
            // - Keep typed listeners for speed/gear/tyre/bodywork.
            // - Attach the global BYDAutoManager listener but process ONLY statistic device=1014.
            // This restores range/fuel/battery values without decoding noisy bodywork/steering events.
            FileLogger.log(appContext, "Next map mode: typed TPMS/gear/battery + temp + fuel range discovery lock")

            // Enable devices once so typed SDK callbacks can dispatch, then register listeners.
            enableDevicesViaManager()
            registerGlobalManagerListener()

            speedListener?.let { listener -> registerTyped("speed") { speedDevice?.registerListener(listener) } }
            statisticListener?.let { listener -> registerTyped("statistic") { statisticDevice?.registerListener(listener) } }
            tyreListener?.let { listener -> registerTyped("tyre") { tyreDevice?.registerListener(listener) } }
            gearboxListener?.let { listener -> registerTyped("gearbox") { gearboxDevice?.registerListener(listener) } }
            acListener?.let { listener -> registerTyped("ac") { acDevice?.registerListener(listener) } }
            bodyworkListener?.let { listener -> registerTyped("bodywork") { bodyworkDevice?.registerListener(listener) } }

            FileLogger.log(appContext, "BYD next map listener registration completed/attempted")
        }

        private inline fun registerTyped(label: String, block: () -> Unit) {
            safe("register $label listener typed") {
                block()
                FileLogger.log(appContext, "registerListener typed ok for $label")
            }
        }

        private inline fun registerBase(label: String, block: () -> Unit) {
            safe("register $label listener base") {
                block()
                FileLogger.log(appContext, "registerListener base ok for $label")
            }
        }

        private fun registerGlobalManagerListener() {
            if (globalManagerListenerRegistered) return
            globalManagerListenerRegistered = true

            val manager = BYDAutoManager.mInstance
            if (manager == null) {
                FileLogger.log(appContext, "BYDAutoManager.mInstance is null; global listener skipped")
                return
            }

            globalManagerListener = object : BYDAutoManager.OnBYDAutoListener {
                override fun onChanged(deviceType: Int, eventType: Int, value: Int, data: Any?) {
                    // Process only whitelisted statistic events and tyre diagnostics.
                    // Unknown statistic events are ignored to avoid wrong UI values.
                    if (deviceType == DEVICE_STATISTIC || deviceType == DEVICE_TYRE) {
                        handleGlobalIntEvent(deviceType, eventType, value, data)
                    }
                }

                override fun onChanged(deviceType: Int, eventType: Int, value: Double, data: Any?) {
                    if (deviceType == DEVICE_STATISTIC || deviceType == DEVICE_TYRE) {
                        handleGlobalDoubleEvent(deviceType, eventType, value, data)
                    }
                }

                // Runtime BYD firmware on this vehicle requires an extra FLOAT callback:
                // BYDAutoManager.OnBYDAutoListener.onChanged(int, int, float, Object).
                // The compile-time stub only exposes Int/Double/ByteArray, so this method
                // must be declared without the override keyword. Without this exact JVM
                // method, native BYDAutoManager aborts with AbstractMethodError on its
                // BYDAutoManagerT thread.
                fun onChanged(deviceType: Int, eventType: Int, value: Float, data: Any?) {
                    if (deviceType == DEVICE_STATISTIC || deviceType == DEVICE_TYRE) {
                        handleGlobalFloatEvent(deviceType, eventType, value, data)
                    }
                }

                override fun onChanged(deviceType: Int, eventType: Int, value: ByteArray?, data: Any?) {
                    // Ignored intentionally. Buffer events are noisy and not needed for dashboard values.
                }

                override fun onError(errorCode: Int, message: String?) {
                    logRealtime("GLOBAL CALLBACK error code=$errorCode message=$message")
                }
            }

            safe("register global BYDAutoManager listener") {
                manager.registerListener(globalManagerListener)
            }
        }


        private fun handleGlobalIntEvent(deviceType: Int, eventType: Int, value: Int, data: Any? = null) {
            when (deviceType) {
                DEVICE_GEARBOX -> {
                    val label = gearLabel(value)
                    if (label != null) {
                        cachedGear = label
                        logRealtime("DECODE GLOBAL gearbox event=$eventType raw=$value gear=$label")
                        emitSnapshot()
                    }
                }
                DEVICE_STATISTIC -> handleStatisticEvent(eventType, value.toDouble(), data)
                DEVICE_TYRE -> handleTyreGlobalEvent(eventType, value.toDouble(), data)
                DEVICE_SPEED -> if (value in 0..300) {
                    cachedSpeedKmh = value.toDouble()
                    logRealtime("DECODE GLOBAL speed int event=$eventType value=$value")
                    emitSnapshot()
                }
            }
        }

        private fun handleGlobalDoubleEvent(deviceType: Int, eventType: Int, value: Double, data: Any? = null) {
            when (deviceType) {
                DEVICE_SPEED -> if (value in 0.0..300.0) {
                    cachedSpeedKmh = value
                    logRealtime("DECODE GLOBAL speed double event=$eventType value=$value")
                    emitSnapshot()
                }
                DEVICE_STATISTIC -> handleStatisticEvent(eventType, value, data)
                DEVICE_TYRE -> handleTyreGlobalEvent(eventType, value, data)
            }
        }

        private fun handleGlobalFloatEvent(deviceType: Int, eventType: Int, value: Float, data: Any? = null) {
            handleGlobalDoubleEvent(deviceType, eventType, value.toDouble(), data)
        }

        private fun handleStatisticEvent(eventType: Int, rawValue: Double, data: Any?) {
            // Discovery-safe mode:
            // - Do NOT map range/fuel from global statistic events yet. BYD emits many
            //   unrelated statistic counters on the same device id, so mapping them into
            //   UI fields makes Range/Fuel/Battery jump.
            // - Keep only the SOC event that matched the vehicle dashboard in testing.
            // - Log event/value/data class at a low rate so we can identify the exact
            //   fuel range / fuel percent / electric range event ids later.
            val rounded = rawValue.roundToInt()
            when (eventType) {
                EVENT_STAT_OUTSIDE_TEMP -> {
                    // Confirmed from discovery: raw around 34184/34696 corresponds to 34°C.
                    val temp = normalizeOutsideTempC(rawValue)
                    if (temp != null) {
                        cachedOutsideTemperatureC = temp
                        logDiscovery("STAT_TEMP", "MAP STAT outsideTemp event=$eventType raw=$rawValue -> ${temp}C data=${shortData(data)}")
                        emitSnapshot()
                    } else {
                        logDiscovery("STAT_TEMP_IGN", "DISCOVERY STAT tempCandidate ignored event=$eventType raw=$rawValue data=${shortData(data)}")
                    }
                }
                EVENT_STAT_PERCENT -> {
                    // This event looked like battery at first, but later proved to be noisy/counter-like
                    // (0 -> 5 -> 89 -> 231). Keep it in logs only; do not overwrite SOC.
                    logDiscovery("STAT_PERCENT_NO_UI", "DISCOVERY STAT percentLike_NOT_MAPPED event=$eventType value=$rounded raw=$rawValue data=${shortData(data)}")
                }
                EVENT_STAT_FUEL_RANGE, EVENT_STAT_FUEL_RANGE_ALT -> {
                    // These are stable range-like candidates but do not match the IC fuel range yet
                    // unless they normalize close to the known dashboard value. Do not display 325km
                    // when the cluster shows 511km.
                    val candidate = normalizeFuelRangeNearDashboard(rawValue)
                    if (candidate != null && acceptFuelRangeCandidate(candidate)) {
                        cachedFuelRangeKm = candidate
                        logDiscovery("STAT_FUEL_RANGE_LOCK", "MAP STAT fuelRange event=$eventType raw=$rawValue -> ${candidate}km data=${shortData(data)}")
                        emitSnapshot()
                    } else {
                        logDiscovery("STAT_FUEL_RANGE_DISC", "DISCOVERY FUEL rangeCandidate_NOT_LOCKED event=$eventType raw=$rawValue normalized=${normalizeRangeKm(rounded)} data=${shortData(data)}")
                    }
                }
                else -> {
                    logDiscovery("STAT_$eventType", "DISCOVERY STAT event=$eventType value=$rounded raw=$rawValue data=${shortData(data)}")
                }
            }
        }

        private fun normalizeOutsideTempC(rawValue: Double): Int? {
            val candidates = listOf(
                rawValue.roundToInt(),
                (rawValue / 10.0).roundToInt(),
                (rawValue / 100.0).roundToInt(),
                (rawValue / 1000.0).roundToInt(),
            )
            return candidates.firstOrNull { it in -40..80 }
        }

        private fun normalizeFuelRangeNearDashboard(rawValue: Double): Int? {
            val rounded = rawValue.roundToInt()
            val candidates = listOf(
                rounded,
                (rawValue / 10.0).roundToInt(),
                (rawValue / 100.0).roundToInt(),
            ).filter { it in 0..900 }
            // Current dashboard reference while discovering on this vehicle: fuel/range ~511km.
            // Only lock candidates near that to avoid showing 325km/338km from unrelated events.
            return candidates.firstOrNull { it in 490..530 }
        }

        private fun acceptPercentCandidate(percent: Int): Boolean {
            if (percent !in 0..100) return false
            val now = SystemClock.elapsedRealtime()
            val last = lastAcceptedBatteryPercent
            if (last == null) {
                lastAcceptedBatteryPercent = percent
                lastAcceptedFuelPercent = percent
                lastBatteryPercentAcceptMs = now
                return true
            }
            // Real SOC/fuel should not jump rapidly. Allow small changes immediately,
            // larger changes only after a long interval. This prevents transient stat
            // counters being displayed as battery/fuel percent.
            val delta = kotlin.math.abs(percent - last)
            val allow = delta <= 2 || now - lastBatteryPercentAcceptMs >= 60_000L
            if (allow) {
                lastAcceptedBatteryPercent = percent
                lastAcceptedFuelPercent = percent
                lastBatteryPercentAcceptMs = now
            }
            return allow
        }

        private fun acceptFuelRangeCandidate(km: Int): Boolean {
            if (km !in 0..900) return false
            val now = SystemClock.elapsedRealtime()
            val last = lastAcceptedFuelRangeKm
            if (last == null) {
                lastAcceptedFuelRangeKm = km
                lastFuelRangeAcceptMs = now
                return true
            }
            // Range can move, but not hundreds of km every second. Allow small drift
            // immediately; allow larger refreshes only after one minute.
            val delta = kotlin.math.abs(km - last)
            val allow = delta <= 10 || now - lastFuelRangeAcceptMs >= 60_000L
            if (allow) {
                lastAcceptedFuelRangeKm = km
                lastFuelRangeAcceptMs = now
            }
            return allow
        }

        private fun handleTyreGlobalEvent(eventType: Int, rawValue: Double, data: Any?) {
            // TPMS often arrives inside the BYD data object rather than as the float/int
            // value. Keep a very low-rate diagnostic log so we can map it without
            // flooding BYDAutoManagerT.
            val now = SystemClock.elapsedRealtime()
            if (now - lastRealtimeLogMs >= REALTIME_LOG_INTERVAL_MS) {
                lastRealtimeLogMs = now
                FileLogger.log(appContext, "TPMS GLOBAL candidate event=$eventType value=$rawValue data=${shortData(data)}")
            }
            tryParseTyreDataObject(data)
        }

        private fun normalizeRangeKm(value: Int): Int? {
            // BYD event may arrive as km, km*10, or sometimes one extra decimal due
            // to float/int bridge conversion. Normalize defensively and never return
            // values that a passenger car range widget should not display.
            val candidates = listOf(
                value,
                (value / 10.0).roundToInt(),
                (value / 100.0).roundToInt(),
            )
            return candidates.firstOrNull { it in 0..900 }
        }

        private fun sanitizeDisplayRangeKm(value: Int?): Int? {
            if (value == null) return null
            return normalizeRangeKm(value)
        }

        private fun enableDevicesViaManager() {
            if (deviceManagerEnabled) return
            deviceManagerEnabled = true
            val manager = deviceManager
            if (manager == null) {
                FileLogger.log(appContext, "BYDAutoDeviceManager unavailable; enableDevice skipped")
                return
            }

            enableDevice(manager, "speed", speedDevice)
            enableDevice(manager, "statistic", statisticDevice)
            enableDevice(manager, "tyre", tyreDevice)
            enableDevice(manager, "gearbox", gearboxDevice)
            enableDevice(manager, "ac", acDevice)
            enableDevice(manager, "bodywork", bodyworkDevice)
        }

        private fun enableDevice(manager: BYDAutoDeviceManager, label: String, device: IBYDAutoDevice?) {
            if (device == null) {
                FileLogger.log(appContext, "enableDevice skipped for $label: device=null")
                return
            }

            // Kinex-style realtime path: native events are usually routed by BYDAutoDeviceManager.
            // registerListener() alone can store the listener but still not subscribe the device to native dispatch.
            safe("addDevice $label") {
                manager.addDevice(device)
                FileLogger.log(appContext, "addDevice ok for $label")
            }

            val deviceType = safe("getType $label") { device.getType() }
            FileLogger.log(appContext, "device type for $label: $deviceType")

            val result = safe("enableDevice manager $label") { manager.enableDevice(device) }
            FileLogger.log(appContext, "enableDevice(manager) result for $label: $result")

            val autoManager = android.hardware.BYDAutoManager.mInstance
            if (autoManager != null && deviceType != null) {
                val directResult = safe("BYDAutoManager.enableDevice $label type=$deviceType") {
                    autoManager.enableDevice(deviceType)
                }
                FileLogger.log(appContext, "BYDAutoManager.enableDevice result for $label type=$deviceType: $directResult")
            } else {
                FileLogger.log(appContext, "BYDAutoManager.enableDevice skipped for $label: manager=${autoManager != null}, type=$deviceType")
            }
        }

        private fun emitSnapshot() {
            if (eventSink == null) return
            val now = SystemClock.elapsedRealtime()
            val elapsed = now - lastSnapshotEmitMs
            if (elapsed >= SNAPSHOT_EMIT_INTERVAL_MS) {
                lastSnapshotEmitMs = now
                pendingSnapshotEmit = false
                mainHandler.post {
                    try {
                        eventSink?.success(getVehicleSnapshot())
                    } catch (e: Throwable) {
                        FileLogger.log(appContext, "emitSnapshot failed: ${e.javaClass.simpleName}: ${e.message}")
                    }
                }
                return
            }

            if (pendingSnapshotEmit) return
            pendingSnapshotEmit = true
            mainHandler.postDelayed({
                lastSnapshotEmitMs = SystemClock.elapsedRealtime()
                pendingSnapshotEmit = false
                try {
                    eventSink?.success(getVehicleSnapshot())
                } catch (e: Throwable) {
                    FileLogger.log(appContext, "emitSnapshot delayed failed: ${e.javaClass.simpleName}: ${e.message}")
                }
            }, (SNAPSHOT_EMIT_INTERVAL_MS - elapsed).coerceAtLeast(250L))
        }

        private fun logDiscovery(key: String, message: String, intervalMs: Long = 5000L) {
            val now = SystemClock.elapsedRealtime()
            val last = discoveryLastLogMs[key] ?: 0L
            if (now - last >= intervalMs) {
                discoveryLastLogMs[key] = now
                FileLogger.log(appContext, message)
            }
        }

        private fun logRealtime(message: String) {
            val now = SystemClock.elapsedRealtime()
            if (now - lastRealtimeLogMs >= REALTIME_LOG_INTERVAL_MS) {
                lastRealtimeLogMs = now
                FileLogger.log(appContext, message)
            }
        }

        private fun createSpeedListener(): AbsBYDAutoSpeedListener {
            return object : AbsBYDAutoSpeedListener() {

                override fun onSpeedChanged(speed: Double) {
                    cachedSpeedKmh = speed.takeIf { it in 0.0..300.0 }
                    logRealtime("CALLBACK speed=$speed cached=$cachedSpeedKmh")
                    emitSnapshot()
                }

                override fun onAccelerateDeepnessChanged(value: Int) {
                    logRealtime("CALLBACK acceleratorDepth=$value")
                    emitSnapshot()
                }

                override fun onBrakeDeepnessChanged(value: Int) {
                    logRealtime("CALLBACK brakeDepth=$value")
                    emitSnapshot()
                }
            }
        }

        private fun createStatisticListener(): AbsBYDAutoStatisticListener {
            return object : AbsBYDAutoStatisticListener() {

                override fun onElecDrivingRangeChanged(value: Int) {
                    // Discovery only. Do not display until event/scale is verified.
                    logDiscovery("TYPED_ELEC_RANGE", "DISCOVERY TYPED electricRange raw=$value NOT_MAPPED")
                }

                override fun onFuelDrivingRangeChanged(value: Int) {
                    // Typed SDK callback is safer than generic statistic event. Accept if it is a sane km value
                    // or if it normalizes near the dashboard fuel/range value.
                    val direct = value.takeIf { it in 0..900 }
                    val nearDash = normalizeFuelRangeNearDashboard(value.toDouble())
                    val km = nearDash ?: direct
                    if (km != null && acceptFuelRangeCandidate(km)) {
                        cachedFuelRangeKm = km
                        logDiscovery("TYPED_FUEL_RANGE_LOCK", "MAP TYPED fuelRange raw=$value -> ${km}km")
                        emitSnapshot()
                    } else {
                        logDiscovery("TYPED_FUEL_RANGE", "DISCOVERY TYPED fuelRange raw=$value NOT_LOCKED")
                    }
                }

                override fun onFuelPercentageChanged(value: Int) {
                    // Discovery only. Fuel percent is separate from SOC on PHEV; do not
                    // mirror battery percent into fuel.
                    logDiscovery("TYPED_FUEL_PERCENT", "DISCOVERY TYPED fuelPercent raw=$value NOT_MAPPED")
                }

                override fun onElecPercentageChanged(value: Double) {
                    val rounded = value.roundToInt()
                    if (rounded in 0..100 && acceptPercentCandidate(rounded)) {
                        cachedBatteryPercent = rounded.toDouble()
                        logDiscovery("TYPED_BATTERY_PERCENT", "DISCOVERY TYPED batteryPercent raw=$value cached=$cachedBatteryPercent")
                        emitSnapshot()
                    } else {
                        logDiscovery("TYPED_BATTERY_PERCENT_IGN", "DISCOVERY TYPED batteryPercent ignored raw=$value")
                    }
                }
            }
        }

        private fun createTyreListener(): AbsBYDAutoTyreListener {
            return object : AbsBYDAutoTyreListener() {

                override fun onTyrePressureValueChanged(area: Int, value: Int) {
                    tyre(area).pressureKpa = value.takeIf {
                        it in BYDAutoTyreDevice.TYRE_PRESSURE_VALUE_MIN..BYDAutoTyreDevice.TYRE_PRESSURE_VALUE_MAX
                    }
                    logRealtime("CALLBACK tyrePressure area=$area value=$value cached=${tyre(area).pressureKpa}")
                    emitSnapshot()
                }

                override fun onTyrePressureStateChanged(area: Int, value: Int) {
                    tyre(area).pressureState = value
                    logRealtime("CALLBACK tyrePressureState area=$area value=$value")
                    emitSnapshot()
                }

                override fun onTyreAirLeakStateChanged(area: Int, value: Int) {
                    tyre(area).airLeakState = value
                    logRealtime("CALLBACK tyreAirLeak area=$area value=$value")
                    emitSnapshot()
                }

                override fun onTyreSignalStateChanged(area: Int, value: Int) {
                    tyre(area).signalState = value
                    logRealtime("CALLBACK tyreSignal area=$area value=$value")
                    emitSnapshot()
                }

                override fun onTyreSystemStateChanged(value: Int) {
                    cachedTyreSystemState = value
                    logRealtime("CALLBACK tyreSystemState=$value")
                    emitSnapshot()
                }

                override fun onTyreTemperatureStateChanged(value: Int) {
                    cachedTyreTemperatureState = value
                    logRealtime("CALLBACK tyreTemperatureState=$value")
                    emitSnapshot()
                }
            }
        }

        private fun createGearboxListener(): AbsBYDAutoGearboxListener {
            return object : AbsBYDAutoGearboxListener() {
                override fun onGearboxAutoModeTypeChanged(value: Int) {
                    cachedGear = gearLabel(value)
                    logRealtime("CALLBACK gearRaw=$value cached=$cachedGear")
                    emitSnapshot()
                }

                override fun onGearboxManualModeLevelChanged(value: Int) {
                    logRealtime("CALLBACK gearboxManualLevel=$value")
                    emitSnapshot()
                }

                override fun onBrakeFluidLevelChanged(value: Int) {
                    logRealtime("CALLBACK brakeFluidLevel=$value")
                }

                override fun onParkBrakeSwitchChanged(value: Int) {
                    logRealtime("CALLBACK parkBrakeSwitch=$value")
                }

                override fun onBrakePedalStateChanged(value: Int) {
                    logRealtime("CALLBACK brakePedalState=$value")
                }
            }
        }

        private fun createAcListener(): AbsBYDAutoAcListener {
            return object : AbsBYDAutoAcListener() {

                override fun onTemperatureChanged(area: Int, value: Int) {
                    if (area == BYDAutoAcDevice.AC_TEMPERATURE_OUT) {
                        cachedOutsideTemperatureC = value.takeIf { it != BYDAutoAcDevice.AC_TEMP_INVALID && it in -40..80 }
                        logRealtime("CALLBACK outsideTemp area=$area value=$value cached=$cachedOutsideTemperatureC")
                        emitSnapshot()
                    } else {
                        logRealtime("CALLBACK acTemperature area=$area value=$value")
                    }
                }
            }
        }


        private fun createBodyworkListener(): AbsBYDAutoBodyworkListener {
            return object : AbsBYDAutoBodyworkListener() {

                override fun onWindowStateChanged(area: Int, state: Int) {
                    window(area).state = state
                    logRealtime("BODYWORK CALLBACK windowState area=$area state=$state")
                    emitSnapshot()
                }

                override fun onWindowOpenPercentChanged(area: Int, percent: Int) {
                    window(area).percent = percent.takeIf { it in BYDAutoBodyworkDevice.WINDOW_OPEN_PERCENT_MIN..BYDAutoBodyworkDevice.WINDOW_OPEN_PERCENT_MAX }
                    logRealtime("BODYWORK CALLBACK windowPercent area=$area percent=$percent cached=${window(area).percent}")
                    emitSnapshot()
                }

                override fun onDoorStateChanged(area: Int, state: Int) {
                    cachedDoors[area] = state
                    logRealtime("BODYWORK CALLBACK doorState area=$area state=$state")
                    emitSnapshot()
                }

                override fun onPowerLevelChanged(value: Int) {
                    cachedPowerLevel = value
                    logRealtime("BODYWORK CALLBACK powerLevel=$value")
                    emitSnapshot()
                }

                override fun onBatteryVoltageLevelChanged(value: Int) {
                    cachedBatteryVoltageLevel = value
                    logRealtime("BODYWORK CALLBACK batteryVoltageLevel=$value")
                    emitSnapshot()
                }

                override fun onAutoSystemStateChanged(value: Int) {
                    logRealtime("BODYWORK CALLBACK autoSystemState=$value")
                    emitSnapshot()
                }

                override fun onSteeringWheelValueChanged(area: Int, value: Double) {
                    logRealtime("BODYWORK CALLBACK steeringWheel area=$area value=$value")
                }

                override fun onMoonRoofConfigChanged(value: Int) {
                    logRealtime("BODYWORK CALLBACK moonRoofConfig=$value")
                }

                override fun onFuelElecLowPowerChanged(value: Int) {
                    logRealtime("BODYWORK CALLBACK fuelElecLowPower=$value")
                }

                override fun onAlarmStateChanged(value: Int) {
                    logRealtime("BODYWORK CALLBACK alarmState=$value")
                }
            }
        }

        private fun createBodyworkDeviceReflectively(): BYDAutoBodyworkDevice? {
            val clazz = BYDAutoBodyworkDevice::class.java
            val constructors = clazz.declaredConstructors.joinToString { ctor ->
                "(${ctor.parameterTypes.joinToString { it.simpleName }})"
            }
            FileLogger.log(appContext, "Bodywork getInstance failed; trying reflective constructors: $constructors")

            safe("reflect bodywork no-arg constructor") {
                val ctor = clazz.declaredConstructors.firstOrNull { it.parameterTypes.isEmpty() }
                    ?: return@safe null
                ctor.isAccessible = true
                ctor.newInstance() as? BYDAutoBodyworkDevice
            }?.let { reflected ->
                FileLogger.log(appContext, "Bodywork reflective no-arg constructor ok")
                return reflected
            }

            safe("reflect bodywork context constructor") {
                val ctor = clazz.declaredConstructors.firstOrNull { it.parameterTypes.size == 1 && Context::class.java.isAssignableFrom(it.parameterTypes[0]) }
                    ?: return@safe null
                ctor.isAccessible = true
                ctor.newInstance(bydContext) as? BYDAutoBodyworkDevice
            }?.let { reflected ->
                FileLogger.log(appContext, "Bodywork reflective context constructor ok")
                return reflected
            }

            FileLogger.log(appContext, "Bodywork reflective construction failed")
            return null
        }


        private fun pollTyreSnapshotThrottled() {
            val now = SystemClock.elapsedRealtime()
            if (now - lastTyrePollMs < TYRE_POLL_INTERVAL_MS) return
            lastTyrePollMs = now
            val device = tyreDevice ?: return
            val areas = listOf(
                BYDAutoTyreDevice.TYRE_COMMAND_AREA_LEFT_FRONT,
                BYDAutoTyreDevice.TYRE_COMMAND_AREA_RIGHT_FRONT,
                BYDAutoTyreDevice.TYRE_COMMAND_AREA_LEFT_REAR,
                BYDAutoTyreDevice.TYRE_COMMAND_AREA_RIGHT_REAR,
                // Some BYD builds use compact numeric areas 1..4 in callbacks.
                1, 2, 3, 4,
            ).distinct()
            for (area in areas) {
                val pressure = safe("poll tyre pressure area=$area") { device.getTyrePressureValue(area) }
                if (pressure != null && pressure in BYDAutoTyreDevice.TYRE_PRESSURE_VALUE_MIN..BYDAutoTyreDevice.TYRE_PRESSURE_VALUE_MAX) {
                    tyre(area).pressureKpa = pressure
                }
                val pState = safe("poll tyre pressure state area=$area") { device.getTyrePressureState(area) }
                if (pState != null) tyre(area).pressureState = pState
                val leak = safe("poll tyre air leak area=$area") { device.getTyreAirLeakState(area) }
                if (leak != null) tyre(area).airLeakState = leak
                val signal = safe("poll tyre signal area=$area") { device.getTyreSignalState(area) }
                if (signal != null) tyre(area).signalState = signal
            }
            cachedTyreSystemState = safe("poll tyre system state") { device.getTyreSystemState() } ?: cachedTyreSystemState
            cachedTyreTemperatureState = safe("poll tyre temperature state") { device.getTyreTemperatureState() } ?: cachedTyreTemperatureState
        }

        private fun tryParseTyreDataObject(data: Any?) {
            if (data == null) return
            safe("parse tyre data object") {
                val cls = data.javaClass
                val methods = cls.methods.associateBy { it.name }
                val area = (methods["getArea"]?.invoke(data) as? Number)?.toInt()
                    ?: (methods["getTyreArea"]?.invoke(data) as? Number)?.toInt()
                    ?: (methods["getCommandArea"]?.invoke(data) as? Number)?.toInt()
                val pressure = (methods["getPressure"]?.invoke(data) as? Number)?.toInt()
                    ?: (methods["getPressureValue"]?.invoke(data) as? Number)?.toInt()
                    ?: (methods["getTyrePressureValue"]?.invoke(data) as? Number)?.toInt()
                if (area != null && pressure != null && pressure in BYDAutoTyreDevice.TYRE_PRESSURE_VALUE_MIN..BYDAutoTyreDevice.TYRE_PRESSURE_VALUE_MAX) {
                    tyre(area).pressureKpa = pressure
                    logRealtime("TPMS object parsed area=$area pressure=$pressure class=${cls.name}")
                    emitSnapshot()
                }
            }
        }

        private fun window(area: Int): CachedWindow = cachedWindows.getOrPut(area) { CachedWindow() }

        private fun tyre(area: Int): CachedTyre = cachedTyres.getOrPut(area) { CachedTyre() }

        private fun tyreSnapshotFromCache(primaryArea: Int, vararg aliases: Int): Map<String, Any?> {
            val tyre = sequenceOf(primaryArea, *aliases.toTypedArray())
                .mapNotNull { cachedTyres[it] }
                .firstOrNull { it.pressureKpa != null || it.pressureState != null || it.airLeakState != null || it.signalState != null }
            val pressureKpa = tyre?.pressureKpa
            return mapOf(
                "pressureKpa" to pressureKpa,
                "pressureBar" to pressureKpa?.let { it / 100.0 },
                "pressureState" to tyre?.pressureState,
                "airLeakState" to tyre?.airLeakState,
                "signalState" to tyre?.signalState,
            )
        }

        private fun gearLabel(value: Int): String? {
            return when (value) {
                BYDAutoGearboxDevice.GEARBOX_AUTO_MODE_P -> "P"
                BYDAutoGearboxDevice.GEARBOX_AUTO_MODE_R -> "R"
                BYDAutoGearboxDevice.GEARBOX_AUTO_MODE_N -> "N"
                BYDAutoGearboxDevice.GEARBOX_AUTO_MODE_D -> "D"
                BYDAutoGearboxDevice.GEARBOX_AUTO_MODE_M -> "M"
                BYDAutoGearboxDevice.GEARBOX_AUTO_MODE_S -> "S"
                else -> null
            }
        }

        private fun logRawEvent(label: String, event: IBYDAutoEvent?) {
            if (event == null) {
                FileLogger.log(appContext, "RAW EVENT $label null")
                return
            }
            val deviceType = safe("$label raw getDeviceType") { event.getDeviceType() }
            val eventType = safe("$label raw getEventType") { event.getEventType() }
            val value = safe("$label raw getValue") { event.getValue() }
            val doubleValue = safe("$label raw getDoubleValue") { event.getDoubleValue() }
            val data = safe("$label raw getData") { event.getData() }
            FileLogger.log(
                appContext,
                "RAW EVENT $label device=$deviceType event=$eventType value=$value double=$doubleValue data=${shortData(data)}"
            )
        }

        private fun logDeviceMethods(label: String, device: Any?) {
            if (device == null) return
            val methodNames = device.javaClass.methods
                .map { it.name }
                .filter { name ->
                    name.contains("listen", ignoreCase = true) ||
                        name.contains("register", ignoreCase = true) ||
                        name.contains("enable", ignoreCase = true) ||
                        name.contains("subscribe", ignoreCase = true) ||
                        name.contains("observe", ignoreCase = true)
                }
                .distinct()
                .sorted()
                .joinToString(",")
            FileLogger.log(appContext, "Device methods probe $label: $methodNames")
        }

        private fun shortData(data: Any?): String {
            return when (data) {
                null -> "null"
                is ByteArray -> "ByteArray(size=${data.size})"
                else -> data.toString().take(120)
            }
        }

        private inline fun <T> safe(label: String, block: () -> T): T? {
            return try {
                block()
            } catch (e: Throwable) {
                try {
                    FileLogger.log(appContext, "Vehicle API exception during $label: ${e.javaClass.simpleName}: ${e.message}")
                } catch (_: Throwable) {
                }
                null
            }
        }

        private class CachedTyre {
            var pressureKpa: Int? = null
            var pressureState: Int? = null
            var airLeakState: Int? = null
            var signalState: Int? = null
        }

        private class CachedWindow {
            var state: Int? = null
            var percent: Int? = null
        }
    }
}


private class BydPermissionBypassContext(base: Context) : ContextWrapper(base) {
    private val allowedPermissions = setOf(
        "android.permission.BYDAUTO_BODYWORK_GET",
        "android.permission.BYDAUTO_BODYWORK_COMMON",
        "android.permission.BYDAUTO_STATISTIC_GET",
        "android.permission.BYDAUTO_SPEED_GET",
        "android.permission.BYDAUTO_GEARBOX_GET",
        "android.permission.BYDAUTO_AC_COMMON",
        "android.permission.BYDAUTO_AC_GET",
        "android.permission.BYDAUTO_TYRE_GET",
        "android.permission.BYDAUTO_TYRE_COMMON",
        "android.permission.BYDAUTO_MULTIMEDIA_GET",
        "android.permission.BYDAUTO_MULTIMEDIA_COMMON",
        "android.permission.BYDACQUISITION_SEND_BUFFER",
        "android.permission.BYDACQUISITION_SEND_FILE",
        "com.byd.ditrainer.permission.CORE",
        "android.permission.WRITE_SECURE_SETTINGS",
        "android.permission.INJECT_EVENTS",
        "android.permission.MEDIA_CONTENT_CONTROL",
        "android.permission.START_ACTIVITIES_FROM_BACKGROUND",
    )

    private fun isBydPermission(permission: String?): Boolean {
        if (permission.isNullOrBlank()) return false
        return permission in allowedPermissions ||
            permission.contains("BYDAUTO", ignoreCase = true) ||
            permission.contains("BYDACQUISITION", ignoreCase = true) ||
            permission.contains("byd", ignoreCase = true)
    }

    override fun checkPermission(permission: String, pid: Int, uid: Int): Int {
        return if (isBydPermission(permission)) PackageManager.PERMISSION_GRANTED
        else super.checkPermission(permission, pid, uid)
    }

    override fun checkCallingPermission(permission: String): Int {
        return if (isBydPermission(permission)) PackageManager.PERMISSION_GRANTED
        else super.checkCallingPermission(permission)
    }

    override fun checkCallingOrSelfPermission(permission: String): Int {
        return if (isBydPermission(permission)) PackageManager.PERMISSION_GRANTED
        else super.checkCallingOrSelfPermission(permission)
    }

    override fun checkSelfPermission(permission: String): Int {
        return if (isBydPermission(permission)) PackageManager.PERMISSION_GRANTED
        else super.checkSelfPermission(permission)
    }

    override fun enforcePermission(permission: String, pid: Int, uid: Int, message: String?) {
        if (!isBydPermission(permission)) {
            super.enforcePermission(permission, pid, uid, message)
        }
    }

    override fun enforceCallingPermission(permission: String, message: String?) {
        if (!isBydPermission(permission)) {
            super.enforceCallingPermission(permission, message)
        }
    }

    override fun enforceCallingOrSelfPermission(permission: String, message: String?) {
        if (!isBydPermission(permission)) {
            super.enforceCallingOrSelfPermission(permission, message)
        }
    }
}
