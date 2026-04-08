import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('check in out screen keeps duplicate punch guards wired to backend flags', () {
    final source = File(
      'lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart',
    ).readAsStringSync();

    expect(source, contains("data['can_clock_in'] ?? data['can_check_in'] ?? false"));
    expect(source, contains("data['can_clock_out'] ?? data['can_check_out'] ?? false"));
    expect(source, contains("data['can_update_clock_out'] ?? data['can_update_check_out'] ?? data['can_update_checkout'] ?? false"));
    expect(source, contains("data['has_checked_in'] ?? ((first ?? '').trim().isNotEmpty)"));
    expect(source, contains("? canInFromApi"));
    expect(source, contains("? canOutFromApi"));
  });
}
