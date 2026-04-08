import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance and leave screens use guarded permission helper instead of fail-open fallback', () {
    final hourAccount = File('lib/attendance_views/hour_account.dart').readAsStringSync();
    final attendanceOverview = File('lib/attendance_views/attendance_overview.dart').readAsStringSync();
    final leaveRequest = File('lib/horilla_leave/leave_request.dart').readAsStringSync();
    final attendanceRequest = File('lib/attendance_views/attendance_request.dart').readAsStringSync();
    final leaveTypes = File('lib/horilla_leave/leave_types.dart').readAsStringSync();
    final home = File('lib/horilla_main/home.dart').readAsStringSync();
    final myLeaveRequest = File('lib/horilla_leave/my_leave_request.dart').readAsStringSync();

    expect(hourAccount, contains("import '../res/utilities/permission_guard.dart';"));
    expect(attendanceOverview, contains("import '../res/utilities/permission_guard.dart';"));
    expect(leaveRequest, contains("import '../res/utilities/permission_guard.dart';"));
    expect(attendanceRequest, contains("import '../res/utilities/permission_guard.dart';"));
    expect(leaveTypes, contains("import '../res/utilities/permission_guard.dart';"));
    expect(home, contains("import '../res/utilities/permission_guard.dart';"));
    expect(myLeaveRequest, contains("import '../res/utilities/permission_guard.dart';"));

    expect(hourAccount, contains('guardedPermissionGet('));
    expect(attendanceOverview, contains('guardedPermissionGet('));
    expect(leaveRequest, contains('guardedPermissionGet('));
    expect(leaveTypes, contains('guardedPermissionGet('));
    expect(home, contains('guardedPermissionGet('));
    expect(myLeaveRequest, contains('guardedPermissionGet('));
    expect(attendanceRequest, contains('permissionGuardMessageForStatus('));
    expect(attendanceRequest, contains('permissionNoticeTile(_permissionStatusMessage'));

    expect(hourAccount, contains('if (result.isAllowed)'));
    expect(leaveRequest, contains('if (result.isAllowed)'));
    expect(home, contains('if (result.isAllowed)'));
    expect(leaveTypes, contains('if (result.isAllowed)'));

    expect(hourAccount, isNot(contains("import '../res/permission_guard.dart';")));
    expect(leaveRequest, isNot(contains("import '../res/permission_guard.dart';")));
    expect(home, isNot(contains("import '../res/permission_guard.dart';")));
  });

  test('leave screens expose specific guarded-access retry notice', () {
    final selectedLeaveType = File('lib/horilla_leave/selected_leave_type.dart').readAsStringSync();
    final leaveOverview = File('lib/horilla_leave/leave_overview.dart').readAsStringSync();

    expect(selectedLeaveType, contains('permissionNoticeTile(_permissionStatusMessage'));
    expect(leaveOverview, contains('permissionNoticeTile(_permissionStatusMessage'));
    expect(selectedLeaveType, contains('_retryPermissionChecks'));
  });

  test('canonical permission guard helper lives only under lib/res/utilities', () {
    final canonical = File('lib/res/utilities/permission_guard.dart');
    final shim = File('lib/res/permission_guard.dart');

    expect(canonical.existsSync(), isTrue);
    expect(canonical.readAsStringSync(), contains('class PermissionGuardResult'));
    expect(shim.existsSync(), isFalse);
  });
}
