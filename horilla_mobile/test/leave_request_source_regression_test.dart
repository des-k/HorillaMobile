import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leave request screen keeps multipart attachment upload and half-day breakdown fields', () {
    final source = File('lib/horilla_leave/leave_request.dart').readAsStringSync();

    expect(source, contains("http.MultipartRequest("));
    expect(source, contains("Uri.parse('\$typedServerUrl/api/leave/request/')"));
    expect(source, contains("request.fields['start_date_breakdown']"));
    expect(source, contains("request.fields['end_date_breakdown']"));
    expect(source, contains("http.MultipartFile.fromPath('attachment', filePath)"));
  });

  test('leave request screen keeps client-side validations for core production fields', () {
    final source = File('lib/horilla_leave/leave_request.dart').readAsStringSync();

    expect(source, contains("_validateLeaveType = true"));
    expect(source, contains("_validateDate = true"));
    expect(source, contains("_validateStartDateBreakdown = true"));
    expect(source, contains("_validateEndDateBreakdown = true"));
    expect(source, contains("_validateDescription = true"));
    expect(source, contains("Please select a leave type"));
    expect(source, contains("Please select a start date"));
  });

  test('leave request screen still separates requested approved cancelled and rejected tabs', () {
    final source = File('lib/horilla_leave/leave_request.dart').readAsStringSync();

    expect(source, contains('requestedRecords'));
    expect(source, contains('approvedRecords'));
    expect(source, contains('cancelledRecords'));
    expect(source, contains('rejectedRecords'));
    expect(source, contains('buildApprovedTabContent'));
    expect(source, contains('buildCancelledTabContent'));
    expect(source, contains('buildRejectedTabContent'));
  });


  test('leave reject flow keeps optional reason payload aligned with backend audit metadata', () {
    final source = File('lib/horilla_leave/leave_request.dart').readAsStringSync();

    expect(source, contains("Future<void> rejectRequest(int rejectId, String rejectionReason)"));
    expect(source, contains("body: jsonEncode(buildLeaveRejectPayload(rejectionReason))"));
    expect(source, contains("request['reject_reason'] = rejectionReason"));
  });

}
