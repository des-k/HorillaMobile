import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/attendance_views/attendance_punching_history.dart';

void main() {
  group('PunchingHistoryItem.fromJson', () {
    test('normalizes numeric and nullable fields from mixed mobile/biometric payloads', () {
      final item = PunchingHistoryItem.fromJson({
        'id': '42',
        'punch_date': '2026-03-20',
        'punch_time': '08:01',
        'source': 'biometric',
        'decision_status': 'accepted',
        'decision_source': 'final_reconciliation',
        'work_mode': 'wfo',
        'device_info': 'ZKTeco K40',
        'photo_url': '',
        'latitude': '1.2345',
        'longitude': 103.9876,
        'location_display': 'Office Gate',
        'google_maps_url': 'https://maps.example.test',
        'accepted_to_attendance': true,
        'reason': '',
      });

      expect(item.id, 42);
      expect(item.source, 'biometric');
      expect(item.deviceInfo, 'ZKTeco K40');
      expect(item.photoUrl, isNull);
      expect(item.latitude, closeTo(1.2345, 0.00001));
      expect(item.longitude, closeTo(103.9876, 0.00001));
      expect(item.googleMapsUrl, 'https://maps.example.test');
      expect(item.acceptedToAttendance, isTrue);
      expect(item.reason, '-');
    });

    test('treats blank and null-like values as safe placeholders', () {
      final item = PunchingHistoryItem.fromJson({
        'id': null,
        'punch_date': null,
        'punch_time': ' ',
        'source': 'null',
        'decision_status': null,
        'decision_source': null,
        'work_mode': '',
        'device_info': null,
        'photo_url': '-',
        'location_display': '',
        'accepted_to_attendance': false,
        'reason': null,
      });

      expect(item.id, 0);
      expect(item.punchDate, '-');
      expect(item.punchTime, '-');
      expect(item.source, '-');
      expect(item.decisionStatus, '-');
      expect(item.decisionSource, '-');
      expect(item.workMode, '-');
      expect(item.deviceInfo, '-');
      expect(item.photoUrl, isNull);
      expect(item.locationDisplay, '-');
      expect(item.acceptedToAttendance, isFalse);
      expect(item.reason, '-');
    });
  });
}
