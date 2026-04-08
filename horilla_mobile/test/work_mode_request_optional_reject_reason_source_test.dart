import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main work mode reject dialog keeps reason optional', () {
    final source = File('lib/attendance_views/work_mode_request.dart').readAsStringSync();
    final rejectBlock = source.split('Future<void> _showRejectDialog')[1].split('Future<void> _showActionRemarkDialog')[0];

    expect(rejectBlock, contains('await _reject(id, comment: comment);'));
    expect(rejectBlock, isNot(contains('Reason / Note is required.')));
  });

  test('document reject dialog still requires a remark', () {
    final source = File('lib/attendance_views/work_mode_request.dart').readAsStringSync();
    expect(source, contains("requiredRemark: true"));
    expect(source, contains("title: 'Reject Document'"));
  });
}
