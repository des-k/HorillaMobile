import 'dart:convert';

import 'package:flutter/material.dart';

class NotificationRouteTarget {
  final String route;
  final Map<String, dynamic>? arguments;

  const NotificationRouteTarget(this.route, {this.arguments});
}

Map<String, dynamic>? notificationDataFromRecord(Map<String, dynamic>? record) {
  if (record == null) return null;
  final raw = record['data'];
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }
  return null;
}

String extractNotificationMessage(Map<String, dynamic> record) {
  final data = notificationDataFromRecord(record);
  final message = data?['message'];
  if (message is String && message.trim().isNotEmpty) return message.trim();
  return (record['verb'] ?? 'Notification').toString();
}

NotificationRouteTarget notificationTargetFromPayload(Map<String, dynamic>? payload) {
  if (payload == null || payload.isEmpty) {
    return const NotificationRouteTarget('/notifications_list');
  }

  final String category = (payload['category'] ?? '').toString().trim().toLowerCase();
  final String route = (payload['mobile_route'] ?? '').toString().trim();
  final rawArgs = payload['mobile_args'];
  Map<String, dynamic>? args;
  if (rawArgs is Map<String, dynamic>) {
    args = rawArgs;
  } else if (rawArgs is Map) {
    args = Map<String, dynamic>.from(rawArgs);
  }

  if (route.isNotEmpty) {
    return NotificationRouteTarget(route, arguments: args);
  }

  switch (category) {
    case 'attendance':
      return NotificationRouteTarget('/attendance_request', arguments: {
        'tab': 'attendance_request',
        ...?args,
      });
    case 'work_mode':
      return NotificationRouteTarget('/attendance_request', arguments: {
        'tab': 'work_mode_request',
        ...?args,
      });
    case 'leave':
      return NotificationRouteTarget('/leave_request', arguments: args);
    default:
      return const NotificationRouteTarget('/notifications_list');
  }
}

NotificationRouteTarget notificationTargetFromRecord(Map<String, dynamic> record) {
  return notificationTargetFromPayload(notificationDataFromRecord(record));
}

Future<void> openNotificationFromPayload(
  BuildContext context,
  Map<String, dynamic>? payload,
) async {
  final target = notificationTargetFromPayload(payload);
  await Navigator.pushNamed(context, target.route, arguments: target.arguments);
}

Future<void> openNotificationFromRecord(
  BuildContext context,
  Map<String, dynamic> record,
) async {
  final target = notificationTargetFromRecord(record);
  await Navigator.pushNamed(context, target.route, arguments: target.arguments);
}

Map<String, dynamic>? notificationRecordFromSerializedPayload(String? payload) {
  if (payload == null || payload.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return null;
  }
  return null;
}
