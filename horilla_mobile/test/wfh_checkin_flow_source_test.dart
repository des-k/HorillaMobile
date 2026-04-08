import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source() => File(
    'lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart',
  ).readAsStringSync();

  test('check-in source preserves WFH setup and payload location rules', () {
    final text = source();

    expect(text, contains("if (s == 'WFH') return 'WFH';"));
    expect(text, contains("if (s == 'REMOTE') return 'WFA';"));

    expect(text, contains('requiresHomeReconfiguration'));
    expect(text, contains('requiresFaceReenrollment'));
    expect(text, contains('hasHomeLocationConfigured'));
    expect(text, contains('wfhGeofencingEnabled'));
    expect(text, contains('wfhRadiusInMeters'));

    expect(text, contains("'latitude': pos.latitude"));
    expect(text, contains("'longitude': pos.longitude"));

    expect(text, contains('if (!hasHomeLocationConfigured || requiresHomeReconfiguration)'));
    expect(text, contains('if (wfhGeofencingEnabled)'));
  });
}