import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification router handles JSON decode and fallback message extraction', () {
    final source = File('lib/horilla_main/notification_router.dart').readAsStringSync();
    expect(source.contains('jsonDecode(raw)'), isTrue);
    expect(source.contains("record['verb'] ?? 'Notification'"), isTrue);
    expect(source.contains("return const NotificationRouteTarget('/notifications_list');"), isTrue);
  });

  test('notification list opens one notification via router after mark read', () {
    final source = File('lib/horilla_main/notifications_list.dart').readAsStringSync();
    expect(source.contains('await markReadNotification(notificationId);'), isTrue);
    expect(source.contains('await openNotificationFromRecord(context, record);'), isTrue);
    expect(source.contains('extractNotificationMessage(record)'), isTrue);
  });
}
