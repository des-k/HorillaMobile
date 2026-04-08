import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source() => File('lib/attendance_views/attendance_request.dart').readAsStringSync();

  test('attendance request mobile flow keeps approval guarded and retains explicit reject dialog behavior', () {
    final text = source();

    expect(text, contains("import '../res/utilities/permission_guard.dart';"));

    expect(text, contains('Future<void> updateAttendanceRequest'));
    expect(text, contains('Future<void> revokeAttendanceRequest'));
    expect(text, contains('Future<void> _showRejectReasonDialog'));

    expect(text, contains("permissionGuardMessageForStatus("));
    expect(text, contains("permissionGuardMessageForError("));
    expect(text, contains("permissionNoticeTile(_permissionStatusMessage"));
    expect(text, contains("permissionChecks();"));
    expect(text, contains('Future<void> _deleteAttendanceAttachment'));
    expect(text, contains('rejectAttendanceRequest(record, {required String reason})'));
    expect(text, contains('body: jsonEncode({"reason": reason})'));
    expect(text, isNot(contains('attendance-request-view-comment')));

    expect(text, contains("if (isMyRequest && (detailStatus ?? '').toUpperCase() == 'WAITING')"));
    expect(text, contains("Delete attachment"));
    expect(text, contains("if (showApprovalActions && (detailStatus ?? '').toUpperCase() == 'WAITING')"));
    expect(text, contains("if (showApprovalActions && (detailStatus ?? '').toUpperCase() == 'APPROVED')"));
    expect(text, contains("'Cancel Request'"));
    expect(text, contains("'Reject'"));
    expect(text, contains("'Approve'"));
    expect(text, contains("'Revoke'"));
    expect(text, contains("'Reject reason is required.'"));
  });

  test('attendance correction mobile payload uses canonical reason field for create and edit', () {
    final text = source();

    expect(text, contains("payload['reason'] = note;"));
    expect(text, contains("'reason': requestDescriptionController.text.trim(),"));
    expect(text, isNot(contains("payload['request_description'] = note;")));
    expect(text, isNot(contains("'request_description': requestDescriptionController.text.trim(),")));
  });



  test('attendance correction scope display uses explicit backend scope instead of inferred final punch values', () {
    final text = source();

    expect(text, contains("String _scopeLabelForRecord(Map<String, dynamic> record)"));
    expect(text, contains("record['scope_label'] ??"));
    expect(text, contains("record['scope'] ??"));
    expect(text, contains("final String displayScope = _scopeLabelForRecord(record);"));
    expect(text, isNot(contains("final String displayScope = _scopeLabel(displayCheckIn, displayCheckOut);")));
  });

  test('attendance request list and detail reuse the same cached shift/flex resolver', () {
    final text = source();

    expect(text, contains("final Map<String, Future<Map<String, String>>> _shiftFlexInfoFutureCache = {};"));
    expect(text, contains('Future<Map<String, String>> _resolvedShiftFlexInfoForRecord(Map<String, dynamic> record)'));
    expect(text, contains('_shiftFlexInfoFutureCache.putIfAbsent(key, () async {'));
    expect(text, contains("future: _resolvedShiftFlexInfoForRecord(record),"));
    expect(text, contains("final shiftFlex = await _resolvedShiftFlexInfoForRecord(record);"));
  });

  test('non-approver users must treat all attendance request rows as my requests', () {
    final text = source();

    expect(
      text.contains('if (!canApproveAttendanceRequests) return true;'),
      isTrue,
      reason: 'Regular employees should not lose newly-created requests because of a fragile ownership split.',
    );
  });

}
