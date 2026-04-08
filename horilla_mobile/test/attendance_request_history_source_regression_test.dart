import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance request history keeps explicit proposed/final/effective attendance sources for mobile history rendering', () {
    final text = File('lib/attendance_views/attendance_request.dart').readAsStringSync();

    expect(text, contains("record['proposed_\$key']"));
    expect(text, contains("record['final_\$key']"));
    expect(text, contains("record['effective_\$key']"));
    expect(text, contains('_proposedOrRecord(record, key)'));
    expect(text, contains('_finalOrRecord(record, key)'));
    expect(text, contains("_requestedOrRecord(record, 'attendance_clock_in')"));
    expect(text, contains("_requestedOrRecord(record, 'attendance_clock_out')"));
    expect(text, contains('Proposed Check In'));
    expect(text, contains('Final Check Out'));
  });
}
