import 'package:flutter/material.dart';

String normalizeAttendanceRequestStatus(String? status) {
  return (status ?? '').trim().toUpperCase();
}

bool canShowAttendanceRequestApprovalActions({
  required bool canApproveAttendanceRequests,
  required bool isMyRequest,
}) {
  return canApproveAttendanceRequests && !isMyRequest;
}

bool canShowAttendanceRequestApproveRejectActions({
  required bool canApproveAttendanceRequests,
  required bool isMyRequest,
  required String? status,
}) {
  return canShowAttendanceRequestApprovalActions(
        canApproveAttendanceRequests: canApproveAttendanceRequests,
        isMyRequest: isMyRequest,
      ) &&
      normalizeAttendanceRequestStatus(status) == 'WAITING';
}

bool canShowAttendanceRequestCancelAction({
  required bool isMyRequest,
  required String? status,
}) {
  return isMyRequest && normalizeAttendanceRequestStatus(status) == 'WAITING';
}

bool canShowAttendanceRequestRevokeAction({
  required bool canApproveAttendanceRequests,
  required bool isMyRequest,
  required String? status,
}) {
  return canShowAttendanceRequestApprovalActions(
        canApproveAttendanceRequests: canApproveAttendanceRequests,
        isMyRequest: isMyRequest,
      ) &&
      normalizeAttendanceRequestStatus(status) == 'APPROVED';
}

class AttendanceRequestActionButtons extends StatelessWidget {
  const AttendanceRequestActionButtons({
    super.key,
    required this.status,
    required this.isMyRequest,
    required this.canApproveAttendanceRequests,
    this.onCancel,
    this.onReject,
    this.onApprove,
    this.onRevoke,
  });

  final String? status;
  final bool isMyRequest;
  final bool canApproveAttendanceRequests;
  final VoidCallback? onCancel;
  final VoidCallback? onReject;
  final VoidCallback? onApprove;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final showApproveReject = canShowAttendanceRequestApproveRejectActions(
      canApproveAttendanceRequests: canApproveAttendanceRequests,
      isMyRequest: isMyRequest,
      status: status,
    );
    final showCancel = canShowAttendanceRequestCancelAction(
      isMyRequest: isMyRequest,
      status: status,
    );
    final showRevoke = canShowAttendanceRequestRevokeAction(
      canApproveAttendanceRequests: canApproveAttendanceRequests,
      isMyRequest: isMyRequest,
      status: status,
    );

    if (!showApproveReject && !showCancel && !showRevoke) {
      return const SizedBox.shrink();
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (showCancel)
          ElevatedButton(
            onPressed: onCancel,
            child: const Text('Cancel Request'),
          ),
        if (showApproveReject) ...[
          ElevatedButton(
            onPressed: onReject,
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: onApprove,
            child: const Text('Approve'),
          ),
        ],
        if (showRevoke)
          ElevatedButton(
            onPressed: onRevoke,
            child: const Text('Revoke'),
          ),
      ],
    );
  }
}
