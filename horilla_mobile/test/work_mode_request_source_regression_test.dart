import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source() => File(
        'lib/attendance_views/work_mode_request.dart',
      ).readAsStringSync();

  test('detail screen still reads backend permission flags for work mode actions', () {
    final text = source();

    expect(text, contains("final bool canApproveAction = r['can_approve'] == true;"));
    expect(text, contains("final bool canRejectAction = r['can_reject'] == true;"));
    expect(text, contains("final bool canRevokeAction = r['can_revoke'] == true;"));
    expect(text, contains("final bool canVerifyDocument = r['can_verify_document'] == true;"));
    expect(text, contains("final bool canReopenDocument = r['can_reopen_document'] == true;"));
    expect(text, contains("final bool canUploadLetter = r['can_upload_document'] == true ||"));
  });

  test('detail screen keeps On Duty document workflow messaging and status summary', () {
    final text = source();

    expect(text, contains("_modeText(r) == 'ON DUTY'"));
    expect(text, contains(r'Document: ${_documentStatusText(r)}'));
    expect(text, contains('Document Status'));
    expect(text, contains('On Duty Workflow'));
    expect(
      text,
      contains('On Duty follows approval and document verification workflow.'),
    );
  });

  test('document review actions still route through remark dialogs and request actions', () {
    final text = source();

    expect(text, contains('_showActionRemarkDialog('));
    expect(
      text,
      contains("_requestDocumentAction(id, 'reject-document', remark: remark)"),
    );
    expect(
      text,
      contains("_requestDocumentAction(id, 'reopen-document', remark: remark)"),
    );
    expect(
      text,
      contains("_requestDocumentAction(id, 'revoke', remark: remark)"),
    );
    expect(
      text,
      contains(
        "if (canVerifyDocument && (docStatus == 'Submitted' || docStatus == 'Pending Verification'))",
      ),
    );
    expect(
      text,
      contains(
        "if (canReopenDocument && (docStatus == 'Verified' || docStatus == 'Rejected'))",
      ),
    );
  });

  test('create dialog still validates On Duty fields and attachment constraints', () {
    final text = source();

    expect(text, contains('Duty Destination Location is required for On Duty requests.'));
    expect(text, contains('_validatePickedFiles(_pickedFiles)'));
    expect(
      text,
      contains("_pickedFiles.isEmpty ? 'Attach files' : 'Attachments ("),
    );
    expect(text, contains('allowMultiple: true'));
  });

  test('request creation still supports multipart upload for picked files', () {
    final text = source();

    expect(text, contains('Future<_CreateResult> _createWorkModeRequest('));
    expect(text, contains("final req = http.MultipartRequest('POST', uri);"));
    expect(
      text,
      contains("req.files.add(await http.MultipartFile.fromPath('files', f.path!));"),
    );
    expect(text, contains(r"'Authorization': 'Bearer $token'"));
  });

  test('detail dialog still exposes attachments and guarded action sections', () {
    final text = source();

    expect(text, contains("final attachmentEntries = _attachmentEntries(r);"));
    expect(text, contains("if (attachmentEntries.isEmpty) return <Widget>[];"));
    expect(text, contains("'Attachments'"));
    expect(
      text,
      contains(
        'if (!isMyList && !isOwner && isApproved && isOnDuty && (canVerifyDocument || canReopenDocument || canRevokeAction)) ...[',
      ),
    );
    expect(text, contains("final bool canCancel = (status == 'PENDING' || status == 'WAITING') && isMyList;"));
  });
}
