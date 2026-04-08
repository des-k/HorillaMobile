Map<String, dynamic> buildLeaveRejectPayload(String? reason) {
  return {'reason': (reason ?? '').trim()};
}

Map<String, dynamic> buildWorkModeRejectPayload({String? comment}) {
  final normalized = (comment ?? '').trim();
  return normalized.isEmpty ? <String, dynamic>{} : <String, dynamic>{'comment': normalized};
}

Map<String, dynamic> buildWorkModeDocumentActionPayload({String? remark}) {
  final normalized = (remark ?? '').trim();
  return normalized.isEmpty
      ? <String, dynamic>{}
      : <String, dynamic>{'remark': normalized, 'reason': normalized};
}


Map<String, dynamic>? buildLeaveDecisionPayload({
  required bool approve,
  String? rejectionReason,
}) {
  if (approve) {
    return null;
  }
  return buildLeaveRejectPayload(rejectionReason);
}
