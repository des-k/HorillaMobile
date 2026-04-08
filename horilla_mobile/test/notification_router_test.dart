import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/horilla_main/notification_router.dart';

void main() {
  test('attendance payload resolves to attendance request route', () {
    final target = notificationTargetFromPayload({
      'category': 'attendance',
      'mobile_route': '/attendance_request',
      'mobile_args': {'tab': 'attendance_request', 'request_id': 10}
    });

    expect(target.route, '/attendance_request');
    expect(target.arguments?['tab'], 'attendance_request');
    expect(target.arguments?['request_id'], 10);
  });

  test('work mode payload resolves to work mode tab', () {
    final target = notificationTargetFromPayload({
      'category': 'work_mode',
      'mobile_args': {'request_id': 88}
    });

    expect(target.route, '/attendance_request');
    expect(target.arguments?['tab'], 'work_mode_request');
    expect(target.arguments?['request_id'], 88);
  });

  test('leave payload resolves to leave request route', () {
    final target = notificationTargetFromPayload({
      'category': 'leave',
      'mobile_route': '/leave_request',
      'mobile_args': {'request_id': 55}
    });

    expect(target.route, '/leave_request');
    expect(target.arguments?['request_id'], 55);
  });

  test('invalid payload falls back to notifications list', () {
    final target = notificationTargetFromPayload({'category': 'unknown'});
    expect(target.route, '/notifications_list');
  });
}
