import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:horilla/res/utilities/mobile_attendance_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cached mobile attendance settings clear stale geofencing preference', () async {
    SharedPreferences.setMockInitialValues({
      'face_detection': true,
      'attendance_location_enabled': true,
      'geo_fencing': true,
    });

    final result = await MobileAttendanceSettingsService.getCached();
    final prefs = await SharedPreferences.getInstance();

    expect(result.faceDetectionEnabled, isTrue);
    expect(result.locationEnabled, isTrue);
    expect(prefs.containsKey('geo_fencing'), isFalse);
  });
}
