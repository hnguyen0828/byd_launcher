package com.example.byd_launcher

import byd.VehicleBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        VehicleBridge.register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
