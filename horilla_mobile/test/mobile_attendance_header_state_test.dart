import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/checkin_checkout/checkin_checkout_views/mobile_header_state.dart';

void main() {
  group('MobileAttendanceHeaderState', () {
    test('parses backend canonical header fields', () {
      final state = MobileAttendanceHeaderState.fromApi({
        'header_state_code': 'CHECKED_IN',
        'header_state_message': 'Checked In',
        'header_detail_message': 'Server verified',
      });

      expect(state.code, 'CHECKED_IN');
      expect(state.message, 'Checked In');
      expect(state.detailMessage, 'Server verified');
      expect(state.hasCanonicalMessage, isTrue);
    });

    test('resolveMainMessage prefers backend message', () {
      final state = MobileAttendanceHeaderState.fromApi({
        'header_state_message': 'Attendance recorded',
      });

      expect(
        state.resolveMainMessage('No record yet'),
        'Attendance recorded',
      );
    });

    test('resolveMainMessage safely falls back when backend fields are absent', () {
      final state = MobileAttendanceHeaderState.fromApi({});

      expect(state.code, isNull);
      expect(state.message, isNull);
      expect(state.detailMessage, isNull);
      expect(
        state.resolveMainMessage('No record yet'),
        'No record yet',
      );
      expect(state.hasCanonicalMessage, isFalse);
    });
  });
}
