import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/res/utilities/request_payloads.dart';

void main() {
  test('work mode main reject payload keeps reason optional', () {
    expect(buildWorkModeRejectPayload(comment: null), isEmpty);
    expect(buildWorkModeRejectPayload(comment: '  policy mismatch  '), {'comment': 'policy mismatch'});
  });

  test('document reject payload requires explanation when present', () {
    expect(buildWorkModeDocumentActionPayload(remark: null), isEmpty);
    expect(
      buildWorkModeDocumentActionPayload(remark: '  blurry letter  '),
      {'remark': 'blurry letter', 'reason': 'blurry letter'},
    );
  });
}
