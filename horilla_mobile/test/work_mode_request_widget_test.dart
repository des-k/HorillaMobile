import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/res/utilities/request_payloads.dart';

class _WorkModeHarness extends StatefulWidget {
  final List<Map<String, dynamic>> approvals;
  final List<Map<String, dynamic>> myRequests;

  const _WorkModeHarness({required this.approvals, required this.myRequests});

  @override
  State<_WorkModeHarness> createState() => _WorkModeHarnessState();
}

class _WorkModeHarnessState extends State<_WorkModeHarness> {
  final List<Map<String, dynamic>> rejectBodies = [];
  final List<Map<String, dynamic>> documentBodies = [];
  late List<Map<String, dynamic>> approvals;

  @override
  void initState() {
    super.initState();
    approvals = List<Map<String, dynamic>>.from(widget.approvals);
  }

  String _employeeName(Map<String, dynamic> r) => '${r['employee_first_name']} ${r['employee_last_name']}';
  String _statusText(Map<String, dynamic> r) {
    final raw = (r['status'] ?? '').toString().toUpperCase();
    if (raw == 'WAITING_FOR_APPROVAL') return 'WAITING';
    return raw;
  }
  String _modeText(Map<String, dynamic> r) => (r['work_type'] ?? '').toString().toUpperCase();
  bool _isOnDuty(Map<String, dynamic> r) => _modeText(r) == 'ON DUTY';
  String _documentStatusText(Map<String, dynamic> r) => (r['document_status'] ?? '-').toString();

  void _updateApprovalRequest(int requestId, Map<String, dynamic> Function(Map<String, dynamic>) transform) {
    setState(() {
      approvals = approvals
          .map((e) => e['id'] == requestId ? transform(Map<String, dynamic>.from(e)) : e)
          .toList();
    });
  }

  String? _documentGuidance(Map<String, dynamic> r) {
    final status = _statusText(r);
    final docStatus = _documentStatusText(r);
    if (!_isOnDuty(r) || status != 'APPROVED') return null;
    if (docStatus == 'Rejected') {
      return 'Document rejected. Attendance effect is not final until document review is verified.';
    }
    if (docStatus == 'Verified') {
      return 'Document verified. Final attendance effect is active.';
    }
    if (docStatus == 'Submitted' || docStatus == 'Pending Verification') {
      return 'Document review pending. Attendance effect is not final yet.';
    }
    return null;
  }

  Future<void> _openRejectDialog(BuildContext context, Map<String, dynamic> r) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Request'),
        content: TextField(controller: controller),
        actions: [
          ElevatedButton(
            onPressed: () {
              rejectBodies.add(buildWorkModeRejectPayload(comment: controller.text.trim().isEmpty ? null : controller.text.trim()));
              Navigator.of(ctx).pop();
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _openActionRemarkDialog(BuildContext context, {required int requestId, required String title, required bool requiredRemark, required String action}) async {
    final controller = TextEditingController();
    String? error;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: controller),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          ]),
          actions: [
            ElevatedButton(
              onPressed: () {
                final remark = controller.text.trim();
                if (requiredRemark && remark.isEmpty) {
                  setState(() => error = 'Remark is required');
                  return;
                }
                documentBodies.add(buildWorkModeDocumentActionPayload(remark: remark.isEmpty ? null : remark));
                if (action == 'revoke') {
                  _updateApprovalRequest(requestId, (e) => {
                        ...e,
                        'status': 'revoked',
                        'can_approve': false,
                        'can_reject': false,
                        'can_revoke': false,
                        'can_verify_document': false,
                        'can_reopen_document': false,
                        'action_type': 'REVOKE',
                      });
                } else if (action == 'reopen-document') {
                  _updateApprovalRequest(requestId, (e) => {
                        ...e,
                        'document_status': 'Pending Verification',
                        'can_verify_document': true,
                        'can_reopen_document': false,
                        'action_type': 'REOPEN_DOCUMENT_REVIEW',
                      });
                } else if (action == 'reject-document') {
                  _updateApprovalRequest(requestId, (e) => {
                        ...e,
                        'document_status': 'Rejected',
                        'can_verify_document': false,
                        'can_reopen_document': true,
                        'action_type': 'REJECT_DOCUMENT',
                      });
                }
                Navigator.of(ctx).pop();
              },
              child: Text(action == 'reopen-document' ? 'Reopen' : action == 'revoke' ? 'Revoke' : 'Reject'),
            ),
          ],
        );
      }),
    );
  }

  void _openDetail(BuildContext context, Map<String, dynamic> r) {
    final status = _statusText(r);
    final isWaiting = status == 'WAITING';
    final isApproved = status == 'APPROVED';
    final isOwner = false;
    final isMyList = false;
    final canApproveAction = r['can_approve'] == true;
    final canRejectAction = r['can_reject'] == true;
    final canRevokeAction = r['can_revoke'] == true;
    final canVerifyDocument = r['can_verify_document'] == true;
    final canReopenDocument = r['can_reopen_document'] == true;
    final isOnDuty = _isOnDuty(r);
    final docStatus = _documentStatusText(r);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Work Type Request'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Employee'),
          Text(_employeeName(r)),
          Text('Status'),
          Text(status),
          if (_isOnDuty(r)) ...[
            const SizedBox(height: 8),
            const Text('Document Status'),
            Text(docStatus),
          ],
          if (_documentGuidance(r) != null) ...[
            const SizedBox(height: 8),
            Text(_documentGuidance(r)!),
          ],
        ]),
        actions: [
          if (!isMyList && !isOwner && canApproveAction && isWaiting)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _openRejectDialog(context, r);
              },
              child: const Text('Reject'),
            ),
          if (!isMyList && !isOwner && canApproveAction && isWaiting)
            ElevatedButton(onPressed: () {}, child: const Text('Approve')),
          if (!isMyList && !isOwner && isApproved && isOnDuty && canVerifyDocument && (docStatus == 'Submitted' || docStatus == 'Pending Verification'))
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _openActionRemarkDialog(context, requestId: r['id'] as int, title: 'Reject Document', requiredRemark: true, action: 'reject-document');
              },
              child: const Text('Reject Document'),
            ),
          if (!isMyList && !isOwner && isApproved && isOnDuty && canReopenDocument && (docStatus == 'Verified' || docStatus == 'Rejected'))
            OutlinedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _openActionRemarkDialog(context, requestId: r['id'] as int, title: 'Reopen Document Review', requiredRemark: false, action: 'reopen-document');
              },
              child: const Text('Reopen Document Review'),
            ),
          if (!isMyList && !isOwner && isApproved && isOnDuty && canRevokeAction)
            OutlinedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _openActionRemarkDialog(context, requestId: r['id'] as int, title: 'Revoke Request', requiredRemark: false, action: 'revoke');
              },
              child: const Text('Revoke Request'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(bottom: const TabBar(tabs: [Tab(text: 'My Requests'), Tab(text: 'Approvals')])),
        body: TabBarView(
          children: [
            const SizedBox.shrink(),
            ListView(
              children: approvals.map((r) => ListTile(
                title: Text(_employeeName(r)),
                onTap: () => _openDetail(context, r),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _request({
  required int id,
  required int employeeId,
  required String status,
  required String workType,
  String scope = 'full',
  String queueType = 'approval',
  String? documentStatus,
  bool canApprove = false,
  bool canReject = false,
  bool canRevoke = false,
  bool canVerifyDocument = false,
  bool canReopenDocument = false,
  String firstName = 'Approver',
  String lastName = 'Target',
  String? actionType,
  String? actionByName,
  String? actionAt,
}) {
  return {
    'id': id,
    'employee_id': employeeId,
    'employee_first_name': firstName,
    'employee_last_name': lastName,
    'status': status,
    'work_type': workType,
    'scope': scope,
    'start_date': '2026-03-20',
    'end_date': '2026-03-20',
    'queue_type': queueType,
    'can_approve': canApprove,
    'can_reject': canReject,
    'can_revoke': canRevoke,
    'can_verify_document': canVerifyDocument,
    'can_reopen_document': canReopenDocument,
    if (documentStatus != null) 'document_status': documentStatus,
    if (actionType != null) 'action_type': actionType,
    if (actionByName != null) 'action_by_name': actionByName,
    if (actionAt != null) 'action_at': actionAt,
  };
}

Future<void> _pumpHarness(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('requested work mode shows actionable controls', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [
          _request(id: 2, employeeId: 2, status: 'waiting_for_approval', workType: 'wfa', canApprove: true, canReject: true),
        ],
      ),
    );

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();

    expect(find.text('Work Type Request'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject Document'), findsNothing);
  });

  testWidgets('main work mode reject reason is optional and persists when entered', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [_request(id: 2, employeeId: 2, status: 'waiting_for_approval', workType: 'wfa', canApprove: true, canReject: true)],
      ),
    );
    final state = tester.state<_WorkModeHarnessState>(find.byType(_WorkModeHarness));

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject').first);
    await tester.pumpAndSettle();
    expect(find.text('Reject Request'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject').last);
    await tester.pumpAndSettle();
    expect(state.rejectBodies.single, isEmpty);

    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Need supporting note');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject').last);
    await tester.pumpAndSettle();
    expect(state.rejectBodies.last, {'comment': 'Need supporting note'});
  });

  testWidgets('document reject requires a remark before submit', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [_request(id: 2, employeeId: 2, status: 'approved', workType: 'on duty', documentStatus: 'Submitted', canVerifyDocument: true)],
      ),
    );
    final state = tester.state<_WorkModeHarnessState>(find.byType(_WorkModeHarness));

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject Document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Remark is required'), findsOneWidget);
    expect(state.documentBodies, isEmpty);

    await tester.enterText(find.byType(TextField).last, 'Document is incomplete');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject'));
    await tester.pumpAndSettle();
    expect(state.documentBodies.single, {'remark': 'Document is incomplete', 'reason': 'Document is incomplete'});
  });

  testWidgets('approved or rejected work mode hides invalid actions', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [
          _request(id: 2, employeeId: 2, status: 'approved', workType: 'wfa'),
          _request(id: 3, employeeId: 3, status: 'rejected', workType: 'wfa'),
        ],
      ),
    );

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target').first);
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    Navigator.of(tester.element(find.text('Work Type Request'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approver Target').last);
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('revoke request sends revoke remark and removes invalid approval controls', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [_request(id: 2, employeeId: 2, status: 'approved', workType: 'on duty', documentStatus: 'Verified', canRevoke: true)],
      ),
    );
    final state = tester.state<_WorkModeHarnessState>(find.byType(_WorkModeHarness));

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Revoke Request'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Request no longer applies');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Revoke'));
    await tester.pumpAndSettle();

    expect(state.documentBodies.single, {'remark': 'Request no longer applies', 'reason': 'Request no longer applies'});
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('reopen document review sends remark for supported on-duty workflow', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [_request(id: 2, employeeId: 2, status: 'approved', workType: 'on duty', documentStatus: 'Rejected', canReopenDocument: true)],
      ),
    );
    final state = tester.state<_WorkModeHarnessState>(find.byType(_WorkModeHarness));

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reopen Document Review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Need another verification pass');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reopen'));
    await tester.pumpAndSettle();

    expect(state.documentBodies.single, {'remark': 'Need another verification pass', 'reason': 'Need another verification pass'});
  });


  testWidgets('rejected document state shows explicit not-final messaging', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [_request(id: 2, employeeId: 2, status: 'approved', workType: 'on duty', documentStatus: 'Rejected', canReopenDocument: true)],
      ),
    );

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();

    expect(find.text('Document Status'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Document rejected. Attendance effect is not final until document review is verified.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reopen Document Review'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Reject Document'), findsNothing);
  });

  testWidgets('verified state shows final effect messaging', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [_request(id: 2, employeeId: 2, status: 'approved', workType: 'on duty', documentStatus: 'Verified', canRevoke: true, canReopenDocument: true)],
      ),
    );

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();

    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Document verified. Final attendance effect is active.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Revoke Request'), findsOneWidget);
  });

  testWidgets('revoke after verify refreshes visible state without stale action buttons', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [_request(id: 2, employeeId: 2, status: 'approved', workType: 'on duty', documentStatus: 'Verified', canRevoke: true, canReopenDocument: true)],
      ),
    );

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Revoke Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Revoke'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();

    expect(find.text('REVOKED'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Revoke Request'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reopen Document Review'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Reject Document'), findsNothing);
  });

  testWidgets('button visibility follows latest document state after reopen', (tester) async {
    await _pumpHarness(
      tester,
      _WorkModeHarness(
        myRequests: const [],
        approvals: [_request(id: 2, employeeId: 2, status: 'approved', workType: 'on duty', documentStatus: 'Rejected', canReopenDocument: true)],
      ),
    );

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reopen Document Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reopen'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approver Target'));
    await tester.pumpAndSettle();

    expect(find.text('Pending Verification'), findsOneWidget);
    expect(find.text('Document review pending. Attendance effect is not final yet.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reopen Document Review'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Reject Document'), findsOneWidget);
  });
}
