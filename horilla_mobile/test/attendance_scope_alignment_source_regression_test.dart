import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monthly attendance screen uses backend-scoped employee options from recap response', () {
    final source = File('lib/attendance_views/attendance_attendance.dart').readAsStringSync();

    expect(source, contains("api/attendance/attendances-recap/"));
    expect(source, contains("decoded['employee_options']"));
    expect(source, contains("decoded['selected_employee_id']"));
    expect(source, contains("decoded['show_employee_filter']"));
    expect(source, isNot(contains("api/employee/employee-selector/")));
  });
}
