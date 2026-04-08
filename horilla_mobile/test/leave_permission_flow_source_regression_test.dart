import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home no longer probes leave permissions during startup', () {
    final source = File('lib/horilla_main/home.dart').readAsStringSync();

    expect(source.contains("permissionLeaveOverviewChecks()"), isFalse);
    expect(source.contains("permissionLeaveTypeChecks()"), isFalse);
    expect(source.contains("permissionLeaveRequestChecks()"), isFalse);
    expect(source.contains("permissionLeaveAssignChecks()"), isFalse);
    expect(source.contains("/api/leave/check-assign/"), isFalse);
    expect(source.contains("/api/leave/check-request/"), isFalse);
    expect(source.contains("/api/leave/check-type/"), isFalse);
    expect(source.contains("await _openLeaveModule();"), isTrue);
  });

  test('leave screens cache permission checks instead of probing on every build', () {
    final files = <String>[
      'lib/horilla_leave/all_assigned_leave.dart',
      'lib/horilla_leave/leave_allocation_request.dart',
      'lib/horilla_leave/leave_overview.dart',
      'lib/horilla_leave/leave_request.dart',
      'lib/horilla_leave/leave_types.dart',
      'lib/horilla_leave/my_leave_request.dart',
      'lib/horilla_leave/selected_leave_type.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source.contains('late Future<void> _permissionFuture;'), isTrue, reason: path);
      expect(source.contains('future: _permissionFuture,'), isTrue, reason: path);
      expect(source.contains('future: checkPermissions(),'), isFalse, reason: path);
    }
  });

  test('leave screens suppress forbidden snackbar/tile messages during background permission probes', () {
    final files = <String>[
      'lib/horilla_leave/all_assigned_leave.dart',
      'lib/horilla_leave/leave_allocation_request.dart',
      'lib/horilla_leave/leave_overview.dart',
      'lib/horilla_leave/leave_request.dart',
      'lib/horilla_leave/leave_types.dart',
      'lib/horilla_leave/my_leave_request.dart',
      'lib/horilla_leave/selected_leave_type.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source.contains('!result.isForbidden'), isTrue, reason: path);
    }
  });
}
