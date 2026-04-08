import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/horilla_main/notification_router.dart';

void main() {
  test('notificationDataFromRecord decodes JSON string payload safely', () {
    final payload = notificationDataFromRecord({
      'data': '{"category":"work_mode","mobile_route":"/attendance_request","mobile_args":{"tab":"work_mode_request","request_id":99}}'
    });

    expect(payload?['category'], 'work_mode');
    expect(payload?['mobile_args']['tab'], 'work_mode_request');
    expect(payload?['mobile_args']['request_id'], 99);
  });

  test('notificationDataFromRecord returns null for malformed JSON string', () {
    final payload = notificationDataFromRecord({'data': '{not-json'});
    expect(payload, isNull);
  });

  test('extractNotificationMessage prefers payload message and falls back to verb', () {
    expect(
      extractNotificationMessage({
        'verb': 'Fallback verb',
        'data': {'message': 'Payload message'}
      }),
      'Payload message',
    );

    expect(
      extractNotificationMessage({'verb': 'Fallback verb', 'data': null}),
      'Fallback verb',
    );
  });

  test('serialized payload helper returns null on blank input', () {
    expect(notificationRecordFromSerializedPayload(null), isNull);
    expect(notificationRecordFromSerializedPayload('  '), isNull);
  });

  test('unknown payload falls back safely to notifications list', () {
    final target = notificationTargetFromPayload({'category': 'mystery'});
    expect(target.route, '/notifications_list');
    expect(target.arguments, isNull);
  });
}
