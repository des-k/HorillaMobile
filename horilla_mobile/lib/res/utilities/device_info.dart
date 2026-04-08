import 'dart:io';

import 'package:flutter/services.dart';

class HorillaDeviceInfo {
  static const MethodChannel _channel = MethodChannel('horilla/device_info');

  static Future<Map<String, String>> getPayload() async {
    try {
      final Map<Object?, Object?>? result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getDeviceInfo',
      );
      final model = (result?['model'] ?? '').toString().trim();
      final manufacturer = (result?['manufacturer'] ?? '').toString().trim();
      final osVersion = (result?['osVersion'] ?? '').toString().trim();
      final parts = <String>[];
      if (manufacturer.isNotEmpty) parts.add(manufacturer);
      if (model.isNotEmpty) parts.add(model);
      if (osVersion.isNotEmpty) parts.add(osVersion);
      final descriptor = parts.join(' | ');
      if (descriptor.isNotEmpty) {
        return {
          'device_info': descriptor,
          if (model.isNotEmpty) 'device_model': model,
        };
      }
    } catch (_) {
      // Native channel may not be registered in partial source exports.
    }

    final os = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion.trim();
    final fallback = version.isEmpty ? os : '$os | $version';
    return {
      'device_info': 'Fallback OS info | $fallback',
    };
  }
}
