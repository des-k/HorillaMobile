import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main notification timer uses 20-second polling and tap handlers do not bulk read', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source.contains('Timer.periodic(const Duration(seconds: 20)'), isTrue);
    expect(source.contains('Timer.periodic(const Duration(seconds: 3)'), isFalse);

    final initHandlerMatch = RegExp(
      r'onDidReceiveNotificationResponse:\s*\(NotificationResponse details\) async \{([\s\S]*?)\n\s*\},',
    ).firstMatch(source);
    expect(initHandlerMatch, isNotNull);
    final initHandlerBody = initHandlerMatch!.group(1)!;
    expect(initHandlerBody.contains('markAllReadNotification()'), isFalse);
    expect(initHandlerBody.contains('markNotificationRead('), isTrue);

    final selectHandlerMatch = RegExp(
      r'Future<void> _onSelectNotification\(BuildContext context, \{Map<String, dynamic>\? record\}\) async \{([\s\S]*?)\n\}',
    ).firstMatch(source);
    expect(selectHandlerMatch, isNotNull);
    final selectHandlerBody = selectHandlerMatch!.group(1)!;
    expect(selectHandlerBody.contains('markAllReadNotification()'), isFalse);
    expect(selectHandlerBody.contains('markNotificationRead('), isTrue);
  });

  test('login page no longer owns notification timer', () {
    final source = File('lib/horilla_main/login.dart').readAsStringSync();
    expect(source.contains('_startNotificationTimer'), isFalse);
    expect(source.contains('Timer.periodic'), isFalse);
  });

  test('notification list and home use notification payload message', () {
    final homeSource = File('lib/horilla_main/home.dart').readAsStringSync();
    final listSource = File('lib/horilla_main/notifications_list.dart').readAsStringSync();
    expect(homeSource.contains('extractNotificationMessage(record)'), isTrue);
    expect(listSource.contains('extractNotificationMessage(record)'), isTrue);
    expect(listSource.contains('openNotificationFromRecord'), isTrue);
  });

  test('attendance and leave screens accept notification route arguments', () {
    final attendanceSource = File('lib/attendance_views/attendance_request.dart').readAsStringSync();
    final leaveSource = File('lib/horilla_leave/leave_request.dart').readAsStringSync();
    expect(attendanceSource.contains('ModalRoute.of(context)?.settings.arguments'), isTrue);
    expect(leaveSource.contains('ModalRoute.of(context)?.settings.arguments'), isTrue);
  });
}
