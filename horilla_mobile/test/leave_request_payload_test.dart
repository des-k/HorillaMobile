import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/res/utilities/request_payloads.dart';

void main() {
  test('leave reject payload handles optional reason correctly', () {
    expect(buildLeaveRejectPayload(null), {'reason': ''});
    expect(buildLeaveRejectPayload('  needs docs  '), {'reason': 'needs docs'});
  });
}
