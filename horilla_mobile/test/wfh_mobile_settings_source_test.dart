import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source() => File(
        'lib/res/utilities/mobile_attendance_settings.dart',
      ).readAsStringSync();

  test('mobile attendance settings service parses and caches WFH fields', () {
    final text = source();

    expect(text, contains("static const String _wfhGeofencingEnabledKey = 'wfh_geofencing_enabled';"));
    expect(text, contains("static const String _wfhRadiusKey = 'wfh_radius';"));
    expect(text, contains("static const String _wfhRequiresHomeKey = 'wfh_requires_home_reconfiguration';"));
    expect(text, contains("static const String _wfhRequiresFaceKey = 'wfh_requires_face_reenrollment';"));
    expect(text, contains("static const String _wfhHasHomeKey = 'wfh_has_home_location';"));
    expect(text, contains("data['wfh_geofencing_enabled']"));
    expect(text, contains("data['wfh_radius_in_meters']"));
    expect(text, contains("data['requires_home_reconfiguration']"));
    expect(text, contains("data['requires_face_reenrollment']"));
    expect(text, contains("data['has_home_location_configured']"));
    expect(text, contains('await prefs.setBool(_wfhGeofencingEnabledKey, wfhGeofencingEnabled);'));
    expect(text, contains('await prefs.setInt(_wfhRadiusKey, wfhRadiusInMeters);'));
  });
}
