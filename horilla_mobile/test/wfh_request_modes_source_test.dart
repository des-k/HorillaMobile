import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('work mode request source keeps WFH as a first-class mode', () {
    final source = File('lib/attendance_views/work_mode_request.dart').readAsStringSync();

    expect(source, contains("if (raw == 'wfh') return 'WFH';"));
    expect(source, contains("value: 'wfh'"));
    expect(source, contains('WFH (Needs approval before punch)'));
  });
}
