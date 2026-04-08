import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance form prefers backend canonical header and refreshes after remote failures', () {
    final source = File(
      'lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart',
    ).readAsStringSync();

    expect(source, contains("import 'mobile_header_state.dart';"));
    expect(source, contains('MobileAttendanceHeaderState.fromApi(data)'));
    expect(source, contains('if (_hasValue(backendHeaderStateMessage))'));
    expect(source, contains('return backendHeaderStateMessage!.trim();'));
    expect(source, contains('await _refreshCanonicalStatusAfterRemoteAttempt();'));
  });

  test('face detection returns refreshStatus so main screen re-reads backend truth', () {
    final source = File(
      'lib/checkin_checkout/checkin_checkout_views/face_detection.dart',
    ).readAsStringSync();

    expect(source, contains("'refreshStatus': true"));
    expect(source, contains("'checkedIn': true"));
    expect(source, contains("'checkedOut': true"));
  });
}
