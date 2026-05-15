package com.example.byd_launcher

import byd.VehicleBridge
import byd.MusicBridge
import byd.NavigationBridge
import byd.NativeVehicleScenePlugin
import byd.NativeVehicleTexturePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        NativeVehicleScenePlugin.preload(
            applicationContext,
            "assets/models/2024_byd_seal_u_dm-i.glb",
        )

        super.configureFlutterEngine(flutterEngine)

        VehicleBridge.register(flutterEngine.dartExecutor.binaryMessenger)
        MusicBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
        NavigationBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
        NativeVehicleScenePlugin.register(flutterEngine)
        NativeVehicleTexturePlugin.register(flutterEngine, applicationContext)
    }
}
