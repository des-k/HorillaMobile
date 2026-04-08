import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active attendance flow no longer contains geofencing endpoint or validation text', () {
    final checkinSource = File(
      'lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart',
    ).readAsStringSync();
    final faceSource = File(
      'lib/checkin_checkout/checkin_checkout_views/face_detection.dart',
    ).readAsStringSync();

    expect(checkinSource, isNot(contains('/api/geofencing/location-check/')));
    expect(checkinSource, isNot(contains('Unable to validate geofencing')));
    expect(checkinSource, isNot(contains('Cannot validate geofencing')));

    expect(faceSource, isNot(contains('/api/geofencing/location-check/')));
    expect(faceSource, isNot(contains('Failed to validate geofencing')));
  });
}
