import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('check in out screen parses and displays clock_in_type grace mode', () {
    final source = File(
      'lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart',
    ).readAsStringSync();

    expect(source, contains('String? graceClockInType;'));
    expect(source, contains("data['clock_in_type'] ?? data['grace_clock_in_type'] ?? data['grace_type']"));
    expect(source, contains("return '±';"));
    expect(source, contains(r"return 'Flex In $symbol$short';"));
    expect(source, contains("_infoChip(_graceDisplayWithMode())"));
  });

  test('attendance request screen keeps flex info aware of clock_in_type', () {
    final source = File(
      'lib/attendance_views/attendance_request.dart',
    ).readAsStringSync();

    expect(source, contains("'clock_in_type': clockInType ?? '',"));
    expect(source, contains('String _flexMinutesDisplayWithMode(int? minutes, {String? clockInType})'));
    expect(source, contains(r"return '$symbol$flex';"));
    expect(source, contains("clockInType: (record['clock_in_type'] ?? record['grace_clock_in_type'] ?? record['grace_type'])?.toString(),"));
  });
}
