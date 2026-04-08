import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance disabled banner no longer exposes Open Requests link', () {
    final source = File(
      'lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("child: const Text('Open Requests')")));
    expect(source, isNot(contains("Navigator.pushNamed(context, '/attendance_request')")));
  });
}
