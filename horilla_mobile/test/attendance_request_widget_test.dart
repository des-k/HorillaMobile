import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/res/utilities/attendance_request_ui.dart';
import 'package:horilla/res/utilities/permission_guard.dart';

class _AttendanceRequestScreenHarness extends StatefulWidget {
  const _AttendanceRequestScreenHarness({
    required this.status,
    required this.isMyRequest,
    required this.canApproveAttendanceRequests,
    this.permissionStatusCode,
    this.retryPermissionStatusCode,
    this.retryCanApproveAttendanceRequests,
  });

  final String status;
  final bool isMyRequest;
  final bool canApproveAttendanceRequests;
  final int? permissionStatusCode;
  final int? retryPermissionStatusCode;
  final bool? retryCanApproveAttendanceRequests;

  @override
  State<_AttendanceRequestScreenHarness> createState() =>
      _AttendanceRequestScreenHarnessState();
}

class _AttendanceRequestScreenHarnessState
    extends State<_AttendanceRequestScreenHarness> {
  String _actionState = 'idle';
  String _rejectReason = '-';
  late String _currentStatus;
  late bool _currentCanApproveAttendanceRequests;
  late int? _currentPermissionStatusCode;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _currentCanApproveAttendanceRequests = widget.canApproveAttendanceRequests;
    _currentPermissionStatusCode = widget.permissionStatusCode;
  }

  @override
  void didUpdateWidget(covariant _AttendanceRequestScreenHarness oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status ||
        oldWidget.canApproveAttendanceRequests != widget.canApproveAttendanceRequests ||
        oldWidget.permissionStatusCode != widget.permissionStatusCode) {
      _currentStatus = widget.status;
      _currentCanApproveAttendanceRequests = widget.canApproveAttendanceRequests;
      _currentPermissionStatusCode = widget.permissionStatusCode;
      _actionState = 'idle';
      _rejectReason = '-';
    }
  }

  void _retryPermissionCheck() {
    setState(() {
      _currentPermissionStatusCode = widget.retryPermissionStatusCode;
      _currentCanApproveAttendanceRequests =
          widget.retryCanApproveAttendanceRequests ??
              widget.canApproveAttendanceRequests;
      _actionState = 'idle';
    });
  }

  void _simulateApprovedRefresh() {
    setState(() {
      _currentStatus = 'APPROVED';
      _actionState = 'idle';
    });
  }

  Future<void> _showRejectReasonDialog() async {
    final controller = TextEditingController();
    String? localError;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Reject Request',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('attendance-reject-reason-field'),
                    controller: controller,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 8),
                    Text(localError!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final reason = controller.text.trim();
                    if (reason.isEmpty) {
                      setLocalState(() {
                        localError = 'Reject reason is required.';
                      });
                      return;
                    }
                    setState(() {
                      _actionState = 'rejected';
                      _rejectReason = reason;
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Reject', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attendance Request Detail',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Status: $_currentStatus'),
            Text('Request owner: ${widget.isMyRequest ? 'mine' : 'approval queue'}'),
            const SizedBox(height: 12),
            if (_currentPermissionStatusCode != null)
              permissionNoticeTile(
                permissionGuardMessageForStatus(_currentPermissionStatusCode!),
              ),
            AttendanceRequestActionButtons(
              status: _currentStatus,
              isMyRequest: widget.isMyRequest,
              canApproveAttendanceRequests: _currentCanApproveAttendanceRequests,
              onCancel: () => setState(() => _actionState = 'cancelled'),
              onReject: _showRejectReasonDialog,
              onApprove: () => setState(() => _actionState = 'approved'),
              onRevoke: () => setState(() => _actionState = 'revoked'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _retryPermissionCheck,
                  child: const Text('Retry Permission Check'),
                ),
                ElevatedButton(
                  onPressed: _simulateApprovedRefresh,
                  child: const Text('Simulate Approved Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Last action: $_actionState'),
            Text('Reject reason: $_rejectReason'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('approval actions hidden when permission is not allowed',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'WAITING',
        isMyRequest: false,
        canApproveAttendanceRequests: false,
      )),
    );

    expect(find.text('Attendance Request Detail'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Revoke'), findsNothing);
    expect(find.text('Cancel Request'), findsNothing);
  });

  testWidgets('approval actions visible when permission is allowed',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'WAITING',
        isMyRequest: false,
        canApproveAttendanceRequests: true,
      )),
    );

    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Revoke'), findsNothing);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Last action: approved'), findsOneWidget);
  });

  testWidgets('reject flow shows explicit confirmation dialog',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'WAITING',
        isMyRequest: false,
        canApproveAttendanceRequests: true,
      )),
    );

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Reject Request'), findsOneWidget);
    expect(find.byKey(const Key('attendance-reject-reason-field')), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject').last);
    await tester.pumpAndSettle();
    expect(find.text('Reject reason is required.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('attendance-reject-reason-field')),
      'Need manager review',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject').last);
    await tester.pumpAndSettle();

    expect(find.text('Reject Request'), findsNothing);
    expect(find.text('Last action: rejected'), findsOneWidget);
    expect(find.text('Reject reason: Need manager review'), findsOneWidget);
  });

  testWidgets('cancel action visible only for cancellable statuses',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'WAITING',
        isMyRequest: true,
        canApproveAttendanceRequests: false,
      )),
    );
    expect(find.text('Cancel Request'), findsOneWidget);

    await tester.tap(find.text('Cancel Request'));
    await tester.pumpAndSettle();
    expect(find.text('Last action: cancelled'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'APPROVED',
        isMyRequest: true,
        canApproveAttendanceRequests: false,
      )),
    );
    await tester.pump();
    expect(find.text('Cancel Request'), findsNothing);
  });

  testWidgets('revoke action visible only for revokable statuses',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'APPROVED',
        isMyRequest: false,
        canApproveAttendanceRequests: true,
      )),
    );
    expect(find.text('Revoke'), findsOneWidget);

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    expect(find.text('Last action: revoked'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'WAITING',
        isMyRequest: false,
        canApproveAttendanceRequests: true,
      )),
    );
    await tester.pump();
    expect(find.text('Revoke'), findsNothing);
  });

  testWidgets('guarded notice shown when permission check fails',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'WAITING',
        isMyRequest: false,
        canApproveAttendanceRequests: false,
        permissionStatusCode: 403,
      )),
    );

    expect(find.text('You do not have access to this feature.'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Last action: idle'), findsOneWidget);
  });

  testWidgets('permission failure followed by retry success restores actionable controls',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'WAITING',
        isMyRequest: false,
        canApproveAttendanceRequests: false,
        permissionStatusCode: 403,
        retryCanApproveAttendanceRequests: true,
      )),
    );

    expect(find.text('You do not have access to this feature.'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);

    await tester.tap(find.text('Retry Permission Check'));
    await tester.pumpAndSettle();

    expect(find.text('You do not have access to this feature.'), findsNothing);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('approved read-only request hides destructive actions consistently',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'APPROVED',
        isMyRequest: true,
        canApproveAttendanceRequests: false,
      )),
    );

    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Cancel Request'), findsNothing);
    expect(find.text('Revoke'), findsNothing);
    expect(find.text('Last action: idle'), findsOneWidget);
  });

  testWidgets('status change does not leave stale dialog or error state',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _AttendanceRequestScreenHarness(
        status: 'WAITING',
        isMyRequest: false,
        canApproveAttendanceRequests: true,
      )),
    );

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reject').last);
    await tester.pumpAndSettle();
    expect(find.text('Reject reason is required.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Reject Request'), findsNothing);

    await tester.tap(find.text('Simulate Approved Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Status: APPROVED'), findsOneWidget);
    expect(find.text('Reject reason is required.'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Revoke'), findsOneWidget);
  });
}
