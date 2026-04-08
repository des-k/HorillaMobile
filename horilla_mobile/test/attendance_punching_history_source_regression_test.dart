import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('punching history screen keeps scoped date and employee filters wired to the API', () {
    final source = File(
      'lib/attendance_views/attendance_punching_history.dart',
    ).readAsStringSync();

    expect(source, contains("'start_date': DateFormat('yyyy-MM-dd').format(_startDate)"));
    expect(source, contains("'end_date': DateFormat('yyyy-MM-dd').format(_endDate)"));
    expect(source, contains("query['employee_id'] = _selectedEmployeeId!;"));
    expect(source, contains("decoded['employee_options']"));
    expect(source, contains("decoded['show_employee_filter']"));
    expect(source, contains('_shouldShowEmployeeFilter('));
  });

  test('punching history screen keeps resilience for timeout and pagination failures', () {
    final source = File(
      'lib/attendance_views/attendance_punching_history.dart',
    ).readAsStringSync();

    expect(source, contains('on TimeoutException'));
    expect(source, contains('on SocketException'));
    expect(source, contains('Request timeout / network error'));
    expect(source, contains('Failed to load more data'));
  });

  test('punching history card still exposes audit-critical source and decision metadata', () {
    final source = File(
      'lib/attendance_views/attendance_punching_history.dart',
    ).readAsStringSync();

    expect(source, contains("label: 'Source'"));
    expect(source, contains("label: 'Decision'"));
    expect(source, contains("label: 'Decision Source'"));
    expect(source, contains("label: 'Device Info'"));
    expect(source, contains("label: 'Reason'"));
  });
}
