package byd

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VehicleBridge {
    companion object {
        private const val CHANNEL_NAME = "byd.vehicle"

        fun register(binaryMessenger: BinaryMessenger) {
            MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler(::handleMethodCall)
        }

        private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "ping" -> result.success(true)
                "getVehicleSnapshot" -> result.success(getVehicleSnapshot())
                else -> result.notImplemented()
            }
        }

        private fun getVehicleSnapshot(): Map<String, Any?> {
            return mapOf(
                "speed" to null,
                "fuelLevel" to null,
                "batteryLevel" to null,
                "tpms" to null,
                "doors" to null,
                "sunroof" to null,
            )
        }
    }
}
