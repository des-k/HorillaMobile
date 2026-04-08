import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('work hours stays dash until both first check in and last check out exist', () {
    final source = File(
      'lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("if (!_hasValue(firstCheckIn) || !_hasValue(lastCheckOut)) return '-';"),
    );
    expect(
      source,
      contains("if (!_hasValue(firstCheckIn) || !_hasValue(lastCheckOut)) {\n      return Text('-', style: style);\n    }"),
    );
  });
}
