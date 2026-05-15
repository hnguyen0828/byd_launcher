package byd

import android.content.Context
import android.hardware.bydauto.ac.BYDAutoAcDevice
import android.hardware.bydauto.ac.AbsBYDAutoAcListener
import android.hardware.bydauto.bodywork.BYDAutoBodyworkDevice
import android.hardware.bydauto.gearbox.BYDAutoGearboxDevice
import android.hardware.bydauto.gearbox.AbsBYDAutoGearboxListener
import android.hardware.bydauto.speed.BYDAutoSpeedDevice
import android.hardware.bydauto.speed.AbsBYDAutoSpeedListener
import android.hardware.bydauto.statistic.BYDAutoStatisticDevice
import android.hardware.bydauto.statistic.AbsBYDAutoStatisticListener
import android.hardware.bydauto.tyre.BYDAutoTyreDevice
import android.hardware.bydauto.tyre.AbsBYDAutoTyreListener
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VehicleBridge {
    companion object {
        private const val CHANNEL_NAME = "byd.vehicle"
        private const val EVENT_CHANNEL_NAME = "byd.vehicle/events"
        private lateinit var appContext: Context
        private val mainHandler = Handler(Looper.getMainLooper())
        private var eventSink: EventChannel.EventSink? = null
        private var listenersRegistered = false
        private var speedDevice: BYDAutoSpeedDevice? = null
        private var statisticDevice: BYDAutoStatisticDevice? = null
        private var tyreDevice: BYDAutoTyreDevice? = null
        private var gearboxDevice: BYDAutoGearboxDevice? = null
        private var acDevice: BYDAutoAcDevice? = null
        private var speedListener: AbsBYDAutoSpeedListener? = null
        private var statisticListener: AbsBYDAutoStatisticListener? = null
        private var tyreListener: AbsBYDAutoTyreListener? = null
        private var gearboxListener: AbsBYDAutoGearboxListener? = null
        private var acListener: AbsBYDAutoAcListener? = null

        fun register(binaryMessenger: BinaryMessenger, context: Context) {
            appContext = context.applicationContext
            MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler(::handleMethodCall)
            EventChannel(binaryMessenger, EVENT_CHANNEL_NAME).setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        ensureListenersRegistered()
                        emitSnapshot()
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                },
            )
        }

        private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "ping" -> result.success(true)
                "getVehicleSnapshot" -> result.success(getVehicleSnapshot())
                else -> result.notImplemented()
            }
        }

        private fun getVehicleSnapshot(): Map<String, Any?> {
            ensureDeviceInstances()
            val bodyworkDevice = safe { BYDAutoBodyworkDevice.getInstance(appContext) }

            val fuelRange = safe { statisticDevice?.getFuelDrivingRangeValue() }
                ?.takeIf { it in 0..4095 }
            val electricRange = safe { statisticDevice?.getElecDrivingRangeValue() }
                ?.takeIf { it in 0..511 }
            val fuelPercent = safe { statisticDevice?.getFuelPercentageValue() }
                ?.takeIf { it in 0..100 }
            val batteryPercent = safe { statisticDevice?.getElecPercentageValue() }
                ?.takeIf { it in 0.0..100.0 }
            val totalRange = listOfNotNull(fuelRange, electricRange).takeIf { it.isNotEmpty() }?.sum()

            return mapOf(
                "available" to listOf(
                    speedDevice,
                    statisticDevice,
                    tyreDevice,
                    gearboxDevice,
                    acDevice,
                    bodyworkDevice,
                ).any { it != null },
                "speedKmh" to safe { speedDevice?.getCurrentSpeed() }
                    ?.takeIf { it in 0.0..300.0 },
                "gear" to safe { gearboxDevice?.getGearboxAutoModeType() }?.let(::gearLabel),
                "rangeKm" to totalRange,
                "fuelRangeKm" to fuelRange,
                "electricRangeKm" to electricRange,
                "fuelPercent" to fuelPercent,
                "batteryPercent" to batteryPercent,
                "outsideTemperatureC" to safe {
                    acDevice?.getTemprature(BYDAutoAcDevice.AC_TEMPERATURE_OUT)
                }?.takeIf { it != BYDAutoAcDevice.AC_TEMP_INVALID && it in -40..80 },
                "powerLevel" to safe { bodyworkDevice?.getPowerLevel() },
                "tpms" to mapOf(
                    "systemState" to safe { tyreDevice?.getTyreSystemState() },
                    "temperatureState" to safe { tyreDevice?.getTyreTemperatureState() },
                    "frontLeft" to tyreSnapshot(tyreDevice, BYDAutoTyreDevice.TYRE_COMMAND_AREA_LEFT_FRONT),
                    "frontRight" to tyreSnapshot(tyreDevice, BYDAutoTyreDevice.TYRE_COMMAND_AREA_RIGHT_FRONT),
                    "rearLeft" to tyreSnapshot(tyreDevice, BYDAutoTyreDevice.TYRE_COMMAND_AREA_LEFT_REAR),
                    "rearRight" to tyreSnapshot(tyreDevice, BYDAutoTyreDevice.TYRE_COMMAND_AREA_RIGHT_REAR),
                ),
            )
        }

        private fun ensureDeviceInstances() {
            if (speedDevice == null) speedDevice = safe { BYDAutoSpeedDevice.getInstance(appContext) }
            if (statisticDevice == null) statisticDevice = safe { BYDAutoStatisticDevice.getInstance(appContext) }
            if (tyreDevice == null) tyreDevice = safe { BYDAutoTyreDevice.getInstance(appContext) }
            if (gearboxDevice == null) gearboxDevice = safe { BYDAutoGearboxDevice.getInstance(appContext) }
            if (acDevice == null) acDevice = safe { BYDAutoAcDevice.getInstance(appContext) }
        }

        private fun ensureListenersRegistered() {
            if (listenersRegistered) return
            listenersRegistered = true
            ensureDeviceInstances()
            speedListener = safe { createSpeedListener() }
            statisticListener = safe { createStatisticListener() }
            tyreListener = safe { createTyreListener() }
            gearboxListener = safe { createGearboxListener() }
            acListener = safe { createAcListener() }
            speedListener?.let { listener -> safe { speedDevice?.registerListener(listener) } }
            statisticListener?.let { listener -> safe { statisticDevice?.registerListener(listener) } }
            tyreListener?.let { listener -> safe { tyreDevice?.registerListener(listener) } }
            gearboxListener?.let { listener -> safe { gearboxDevice?.registerListener(listener) } }
            acListener?.let { listener -> safe { acDevice?.registerListener(listener) } }
        }

        private fun emitSnapshot() {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                eventSink?.success(getVehicleSnapshot())
            } else {
                mainHandler.post { eventSink?.success(getVehicleSnapshot()) }
            }
        }

        private fun createSpeedListener(): AbsBYDAutoSpeedListener {
            return object : AbsBYDAutoSpeedListener() {
                override fun onSpeedChanged(speed: Double) = emitSnapshot()
                override fun onAccelerateDeepnessChanged(value: Int) = emitSnapshot()
                override fun onBrakeDeepnessChanged(value: Int) = emitSnapshot()
            }
        }

        private fun createStatisticListener(): AbsBYDAutoStatisticListener {
            return object : AbsBYDAutoStatisticListener() {
                override fun onElecDrivingRangeChanged(value: Int) = emitSnapshot()
                override fun onFuelDrivingRangeChanged(value: Int) = emitSnapshot()
                override fun onFuelPercentageChanged(value: Int) = emitSnapshot()
                override fun onElecPercentageChanged(value: Double) = emitSnapshot()
            }
        }

        private fun createTyreListener(): AbsBYDAutoTyreListener {
            return object : AbsBYDAutoTyreListener() {
                override fun onTyrePressureValueChanged(area: Int, value: Int) = emitSnapshot()
                override fun onTyrePressureStateChanged(area: Int, value: Int) = emitSnapshot()
                override fun onTyreAirLeakStateChanged(area: Int, value: Int) = emitSnapshot()
                override fun onTyreSignalStateChanged(area: Int, value: Int) = emitSnapshot()
                override fun onTyreSystemStateChanged(value: Int) = emitSnapshot()
            }
        }

        private fun createGearboxListener(): AbsBYDAutoGearboxListener {
            return object : AbsBYDAutoGearboxListener() {
                override fun onGearboxAutoModeTypeChanged(value: Int) = emitSnapshot()
            }
        }

        private fun createAcListener(): AbsBYDAutoAcListener {
            return object : AbsBYDAutoAcListener() {
                override fun onTemperatureChanged(area: Int, value: Int) {
                    if (area == BYDAutoAcDevice.AC_TEMPERATURE_OUT) emitSnapshot()
                }
            }
        }

        private fun tyreSnapshot(device: BYDAutoTyreDevice?, area: Int): Map<String, Any?> {
            val pressureRaw = safe { device?.getTyrePressureValue(area) }
                ?.takeIf { it in BYDAutoTyreDevice.TYRE_PRESSURE_VALUE_MIN..BYDAutoTyreDevice.TYRE_PRESSURE_VALUE_MAX }
            return mapOf(
                "pressureKpa" to pressureRaw,
                "pressureBar" to pressureRaw?.let { it / 100.0 },
                "pressureState" to safe { device?.getTyrePressureState(area) },
                "airLeakState" to safe { device?.getTyreAirLeakState(area) },
                "signalState" to safe { device?.getTyreSignalState(area) },
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

        private inline fun <T> safe(block: () -> T): T? {
            return try {
                block()
            } catch (_: Throwable) {
                null
            }
        }
    }
}
