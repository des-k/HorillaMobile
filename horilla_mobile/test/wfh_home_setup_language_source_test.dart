import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WFH home setup messages use simple English', () async {
    final source = await File('lib/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart').readAsString();

    expect(source, contains("Set Up WFH Home Location"));
    expect(source, contains("Your WFH home location must be set up before you can check in or check out. Use your current location as your home location?"));
    expect(source, contains("Failed to save your WFH home location."));
    expect(source, contains("You are outside your allowed WFH home radius."));

    expect(source, isNot(contains("Setup Lokasi Rumah WFH")));
    expect(source, isNot(contains("Lokasi rumah untuk WFH wajib dikonfigurasi")));
    expect(source, isNot(contains("Gagal menyimpan lokasi rumah WFH.")));
    expect(source, isNot(contains("Anda berada di luar radius lokasi rumah yang diizinkan untuk WFH.")));
  });
}
