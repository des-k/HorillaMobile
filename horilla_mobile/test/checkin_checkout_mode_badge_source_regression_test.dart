import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('check in/out mode badges only appear when visible mode is request-driven', () {
    final source = File(
      'lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart',
    ).readAsStringSync();

    expect(source, contains('bool _shouldShowRequestBadge({'));
    expect(source, contains("if (rs != 'APPROVED') return false;"));
    expect(source, contains("if (source == 'approved_request' || source == 'request')"));
    expect(source, contains('requestedMode: inRequestedMode,'));
    expect(source, contains('requestedMode: outRequestedMode,'));
    expect(source, contains("final String? inModeSourceRaw = (data['in_work_type_source']"));
    expect(source, contains("final String? outRequestedModeRaw = (data['out_requested_work_type']"));
  });
}
