import 'package:flutter/services.dart';

class VehicleChannel {
  static const MethodChannel platform = MethodChannel('byd.vehicle');

  Future<bool> ping() async {
    return await platform.invokeMethod<bool>('ping') ?? false;
  }

  Future<Map<String, dynamic>> getVehicleSnapshot() async {
    final result = await platform.invokeMapMethod<String, dynamic>(
      'getVehicleSnapshot',
    );

    return result ?? <String, dynamic>{};
  }
}
