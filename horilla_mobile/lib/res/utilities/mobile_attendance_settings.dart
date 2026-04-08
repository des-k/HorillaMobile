import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MobileAttendanceSettingsResult {
  final bool faceDetectionEnabled;
  final bool locationEnabled;
  final bool wfhGeofencingEnabled;
  final int wfhRadiusInMeters;
  final bool requiresHomeReconfiguration;
  final bool requiresFaceReenrollment;
  final bool hasHomeLocationConfigured;

  static const bool defaultFaceDetectionEnabled = true;
  static const bool defaultLocationCaptureEnabled = true;
  static const bool defaultWfhGeofencingEnabled = true;
  static const int defaultWfhRadiusInMeters = 250;

  const MobileAttendanceSettingsResult({
    required this.faceDetectionEnabled,
    required this.locationEnabled,
    required this.wfhGeofencingEnabled,
    required this.wfhRadiusInMeters,
    required this.requiresHomeReconfiguration,
    required this.requiresFaceReenrollment,
    required this.hasHomeLocationConfigured,
  });
}

class MobileAttendanceSettingsService {
  static const String _faceKey = 'face_detection';
  static const String _locationKey = 'attendance_location_enabled';
  static const String _geoFencingKey = 'geo_fencing';
  static const String _wfhGeofencingEnabledKey = 'wfh_geofencing_enabled';
  static const String _wfhRadiusKey = 'wfh_radius';
  static const String _wfhRequiresHomeKey = 'wfh_requires_home_reconfiguration';
  static const String _wfhRequiresFaceKey = 'wfh_requires_face_reenrollment';
  static const String _wfhHasHomeKey = 'wfh_has_home_location';

  static Future<MobileAttendanceSettingsResult> fetchAndCache({
    String? serverAddress,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedToken = token ?? prefs.getString('token');
    final resolvedServer = serverAddress ?? prefs.getString('typed_url');

    if (resolvedToken == null || resolvedServer == null) {
      await prefs.remove(_geoFencingKey);
      return MobileAttendanceSettingsResult(
        faceDetectionEnabled: prefs.getBool(_faceKey) ??
            MobileAttendanceSettingsResult.defaultFaceDetectionEnabled,
        locationEnabled: prefs.getBool(_locationKey) ??
            MobileAttendanceSettingsResult.defaultLocationCaptureEnabled,
        wfhGeofencingEnabled: prefs.getBool(_wfhGeofencingEnabledKey) ?? MobileAttendanceSettingsResult.defaultWfhGeofencingEnabled,
        wfhRadiusInMeters: prefs.getInt(_wfhRadiusKey) ?? MobileAttendanceSettingsResult.defaultWfhRadiusInMeters,
        requiresHomeReconfiguration: prefs.getBool(_wfhRequiresHomeKey) ?? false,
        requiresFaceReenrollment: prefs.getBool(_wfhRequiresFaceKey) ?? false,
        hasHomeLocationConfigured: prefs.getBool(_wfhHasHomeKey) ?? false,
      );
    }

    final base = resolvedServer.endsWith('/')
        ? resolvedServer.substring(0, resolvedServer.length - 1)
        : resolvedServer;
    final uri = Uri.parse('$base/api/attendance/mobile-attendance-settings/');

    try {
      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $resolvedToken',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final faceEnabled = (data['face_detection_enabled'] ??
                MobileAttendanceSettingsResult.defaultFaceDetectionEnabled) ==
            true;
        final locationEnabled = ((data['location_capture_enabled'] ??
                    data['location_enabled'] ??
                    MobileAttendanceSettingsResult.defaultLocationCaptureEnabled) ==
                true);
        final wfhGeofencingEnabled = (data['wfh_geofencing_enabled'] ?? MobileAttendanceSettingsResult.defaultWfhGeofencingEnabled) == true;
        final wfhRadiusInMeters = int.tryParse((data['wfh_radius_in_meters'] ?? MobileAttendanceSettingsResult.defaultWfhRadiusInMeters).toString()) ?? MobileAttendanceSettingsResult.defaultWfhRadiusInMeters;
        final requiresHomeReconfiguration = (data['requires_home_reconfiguration'] ?? false) == true;
        final requiresFaceReenrollment = (data['requires_face_reenrollment'] ?? false) == true;
        final hasHomeLocationConfigured = (data['has_home_location_configured'] ?? false) == true;
        await prefs.setBool(_faceKey, faceEnabled);
        await prefs.setBool(_locationKey, locationEnabled);
        await prefs.setBool(_wfhGeofencingEnabledKey, wfhGeofencingEnabled);
        await prefs.setInt(_wfhRadiusKey, wfhRadiusInMeters);
        await prefs.setBool(_wfhRequiresHomeKey, requiresHomeReconfiguration);
        await prefs.setBool(_wfhRequiresFaceKey, requiresFaceReenrollment);
        await prefs.setBool(_wfhHasHomeKey, hasHomeLocationConfigured);
        await prefs.remove(_geoFencingKey);
        return MobileAttendanceSettingsResult(
          faceDetectionEnabled: faceEnabled,
          locationEnabled: locationEnabled,
          wfhGeofencingEnabled: wfhGeofencingEnabled,
          wfhRadiusInMeters: wfhRadiusInMeters,
          requiresHomeReconfiguration: requiresHomeReconfiguration,
          requiresFaceReenrollment: requiresFaceReenrollment,
          hasHomeLocationConfigured: hasHomeLocationConfigured,
        );
      }
    } catch (_) {}

    await prefs.remove(_geoFencingKey);
    return MobileAttendanceSettingsResult(
      faceDetectionEnabled: prefs.getBool(_faceKey) ??
          MobileAttendanceSettingsResult.defaultFaceDetectionEnabled,
      locationEnabled: prefs.getBool(_locationKey) ??
          MobileAttendanceSettingsResult.defaultLocationCaptureEnabled,
      wfhGeofencingEnabled: prefs.getBool(_wfhGeofencingEnabledKey) ?? MobileAttendanceSettingsResult.defaultWfhGeofencingEnabled,
      wfhRadiusInMeters: prefs.getInt(_wfhRadiusKey) ?? MobileAttendanceSettingsResult.defaultWfhRadiusInMeters,
      requiresHomeReconfiguration: prefs.getBool(_wfhRequiresHomeKey) ?? false,
      requiresFaceReenrollment: prefs.getBool(_wfhRequiresFaceKey) ?? false,
      hasHomeLocationConfigured: prefs.getBool(_wfhHasHomeKey) ?? false,
    );
  }

  static Future<MobileAttendanceSettingsResult> getCached() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_geoFencingKey);
    return MobileAttendanceSettingsResult(
      faceDetectionEnabled: prefs.getBool(_faceKey) ??
          MobileAttendanceSettingsResult.defaultFaceDetectionEnabled,
      locationEnabled: prefs.getBool(_locationKey) ??
          MobileAttendanceSettingsResult.defaultLocationCaptureEnabled,
      wfhGeofencingEnabled: prefs.getBool(_wfhGeofencingEnabledKey) ?? MobileAttendanceSettingsResult.defaultWfhGeofencingEnabled,
      wfhRadiusInMeters: prefs.getInt(_wfhRadiusKey) ?? MobileAttendanceSettingsResult.defaultWfhRadiusInMeters,
      requiresHomeReconfiguration: prefs.getBool(_wfhRequiresHomeKey) ?? false,
      requiresFaceReenrollment: prefs.getBool(_wfhRequiresFaceKey) ?? false,
      hasHomeLocationConfigured: prefs.getBool(_wfhHasHomeKey) ?? false,
    );
  }
}
