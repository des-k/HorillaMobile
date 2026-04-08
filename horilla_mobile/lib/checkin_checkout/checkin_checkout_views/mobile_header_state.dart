class MobileAttendanceHeaderState {
  final String? code;
  final String? message;
  final String? detailMessage;

  const MobileAttendanceHeaderState({
    this.code,
    this.message,
    this.detailMessage,
  });

  static String? _clean(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  factory MobileAttendanceHeaderState.fromApi(Map<String, dynamic> data) {
    return MobileAttendanceHeaderState(
      code: _clean(data['header_state_code']),
      message: _clean(data['header_state_message']),
      detailMessage: _clean(data['header_detail_message']),
    );
  }

  bool get hasCanonicalMessage => _clean(message) != null;

  String resolveMainMessage(String fallbackMessage) {
    return _clean(message) ?? fallbackMessage.trim();
  }
}
