import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart';
import 'package:horilla/res/utilities/mobile_attendance_settings.dart';

class _QueuedPayloadSource {
  _QueuedPayloadSource(this._responses);

  final List<Future<Map<String, dynamic>> Function()> _responses;
  int _index = 0;

  Future<Map<String, dynamic>> fetch() async {
    if (_responses.isEmpty) {
      throw StateError('No queued status responses configured');
    }
    final responseIndex = _index < _responses.length ? _index : _responses.length - 1;
    _index += 1;
    return _responses[responseIndex]();
  }
}

class _QueuedFaceFlowSource {
  _QueuedFaceFlowSource(this._responses);

  final List<Future<Object?> Function()> _responses;
  int _index = 0;

  Future<Object?> launch(
    BuildContext context, {
    required bool isClockIn,
    required dynamic userLocation,
    required Map<String, dynamic> userDetails,
  }) async {
    if (_responses.isEmpty) return null;
    final responseIndex = _index < _responses.length ? _index : _responses.length - 1;
    _index += 1;
    return _responses[responseIndex]();
  }
}

Map<String, dynamic> _employeePayload() {
  return {
    'id': 7,
    'employee_first_name': 'Demo',
    'employee_last_name': 'User',
    'badge_id': 'EMP-7',
    'department_name': 'QA',
    'employee_profile': '',
    'employee_work_info_id': 42,
  };
}

Map<String, dynamic> _statusPayload({
  bool canClockIn = false,
  bool canClockOut = false,
  bool canUpdateClockOut = false,
  bool hasCheckedIn = false,
  bool hasCheckedOut = false,
  String? firstCheckIn,
  String? lastCheckOut,
  String? attendanceDate,
  String? headerStateCode,
  String? headerStateMessage,
  String? headerDetailMessage,
}) {
  return {
    'can_clock_in': canClockIn,
    'can_clock_out': canClockOut,
    'can_update_clock_out': canUpdateClockOut,
    'has_checked_in': hasCheckedIn,
    'has_checked_out': hasCheckedOut,
    'first_check_in': firstCheckIn,
    'last_check_out': lastCheckOut,
    'attendance_date': attendanceDate ?? '2026-03-24',
    'attendance_enabled': true,
    'in_work_type': 'WFO',
    'out_work_type': 'WFO',
    'requires_photo_in': false,
    'requires_photo_out': false,
    'requires_location_in': false,
    'requires_location_out': false,
    if (headerStateCode != null) 'header_state_code': headerStateCode,
    if (headerStateMessage != null) 'header_state_message': headerStateMessage,
    if (headerDetailMessage != null) 'header_detail_message': headerDetailMessage,
  };
}

Future<void> _pumpProductionWidget(
  WidgetTester tester, {
  required _QueuedPayloadSource statusSource,
  required _QueuedFaceFlowSource faceFlowSource,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CheckInCheckOutFormPage(
        testOverrides: CheckInCheckOutFormTestOverrides(
          loadToken: () async => 'token',
          loadBaseUrl: () async => 'https://example.test',
          fetchProofSettings: () async => const MobileAttendanceSettingsResult(
            faceDetectionEnabled: true,
            locationEnabled: false,
            wfhGeofencingEnabled: true,
            wfhRadiusInMeters: 250,
            requiresHomeReconfiguration: false,
            requiresFaceReenrollment: false,
            hasHomeLocationConfigured: true,
          ),
          fetchEmployeeRecord: () async => _employeePayload(),
          fetchEmployeeWorkInfoRecord: (workInfoId) async => {'shift_name': 'General Shift'},
          fetchAttendanceStatusPayload: statusSource.fetch,
          launchFaceScanner: faceFlowSource.launch,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

String _swipeLabel(WidgetTester tester) {
  final finder = find.byKey(const Key('attendance-swipe-label'), skipOffstage: false);
  if (finder.evaluate().length != 1) return '';
  final text = tester.widget<Text>(finder);
  return text.data ?? '';
}


Future<void> _pumpUntilSwipeLabelContains(
  WidgetTester tester,
  String expected,
) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (_swipeLabel(tester).contains(expected)) {
      await tester.pumpAndSettle();
      return;
    }
  }
  await tester.pumpAndSettle();
}

Future<void> _triggerSwipe(WidgetTester tester, {required bool toRight}) async {
  final pageFinder = find.byType(CheckInCheckOutFormPage);
  expect(pageFinder, findsOneWidget);

  final dynamic state = tester.state(pageFinder);
  await state.triggerAttendanceSwipeForTest(isClockIn: toRight);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('initial production widget shows check in CTA for can_clock_in state', (tester) async {
    final statusSource = _QueuedPayloadSource([
      () async => _statusPayload(
            canClockIn: true,
            headerStateMessage: 'No record yet',
            headerDetailMessage: 'Please Check In',
          ),
    ]);

    await _pumpProductionWidget(
      tester,
      statusSource: statusSource,
      faceFlowSource: _QueuedFaceFlowSource([]),
    );

    expect(find.byKey(const Key('attendance-swipe-action'), skipOffstage: false), findsOneWidget);
    expect(_swipeLabel(tester), contains('CHECK IN'));
    expect(_swipeLabel(tester), isNot(contains('CHECK OUT')));
    expect(find.byKey(const Key('attendance-header-note')), findsOneWidget);
    expect(find.text('No record yet'), findsOneWidget);
    expect(find.text('Please Check In'), findsOneWidget);
  });

  testWidgets('initial production widget shows check out CTA for checked in state', (tester) async {
    final statusSource = _QueuedPayloadSource([
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            firstCheckIn: '09:00:00',
            headerStateMessage: 'Checked In',
            headerDetailMessage: 'Earliest Check Out: 18:00',
          ),
    ]);

    await _pumpProductionWidget(
      tester,
      statusSource: statusSource,
      faceFlowSource: _QueuedFaceFlowSource([]),
    );

    expect(find.byKey(const Key('attendance-swipe-action'), skipOffstage: false), findsOneWidget);
    expect(_swipeLabel(tester), contains('CHECK OUT'));
    expect(_swipeLabel(tester), isNot(contains('CHECK IN')));
    expect(find.text('Checked In'), findsOneWidget);
    expect(find.text('Earliest Check Out: 18:00'), findsOneWidget);
  });

  testWidgets('refreshed production widget removes stale CTA after backend truth changes', (tester) async {
    final statusSource = _QueuedPayloadSource([
      () async => _statusPayload(
            canClockIn: true,
            headerStateMessage: 'No record yet',
            headerDetailMessage: 'Please Check In',
          ),
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            firstCheckIn: '09:01:00',
            headerStateMessage: 'Checked In',
            headerDetailMessage: 'Earliest Check Out: 18:00',
          ),
    ]);

    await _pumpProductionWidget(
      tester,
      statusSource: statusSource,
      faceFlowSource: _QueuedFaceFlowSource([]),
    );

    expect(_swipeLabel(tester), contains('CHECK IN'));

    final dynamic state = tester.state(find.byType(CheckInCheckOutFormPage));
    await state.refreshAttendanceStatus();
    await tester.pumpAndSettle();

    expect(_swipeLabel(tester), contains('CHECK OUT'));
    expect(_swipeLabel(tester), isNot(contains('CHECK IN')));
    expect(find.text('Checked In'), findsOneWidget);
    expect(find.text('Earliest Check Out: 18:00'), findsOneWidget);
  });

  testWidgets('face flow return with refresh updates production widget to latest backend truth', (tester) async {
    final statusSource = _QueuedPayloadSource([
      () async => _statusPayload(
            canClockIn: true,
            headerStateMessage: 'No record yet',
            headerDetailMessage: 'Please Check In',
          ),
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            firstCheckIn: '09:05:00',
            headerStateMessage: 'Checked In',
            headerDetailMessage: 'Earliest Check Out: 18:00',
          ),
    ]);

    final faceFlowSource = _QueuedFaceFlowSource([
      () async => {
            'checkedIn': true,
            'refreshStatus': true,
          },
    ]);

    await _pumpProductionWidget(
      tester,
      statusSource: statusSource,
      faceFlowSource: faceFlowSource,
    );

    await _triggerSwipe(tester, toRight: true);
    await _pumpUntilSwipeLabelContains(tester, 'CHECK OUT');

    expect(_swipeLabel(tester), contains('CHECK OUT'));
    expect(find.text('Checked In'), findsOneWidget);
    expect(find.text('Earliest Check Out: 18:00'), findsOneWidget);
  });

  testWidgets('face flow cancel keeps stable production widget state without crash', (tester) async {
    final statusSource = _QueuedPayloadSource([
      () async => _statusPayload(
            canClockIn: true,
            headerStateMessage: 'No record yet',
            headerDetailMessage: 'Please Check In',
          ),
    ]);

    final faceFlowSource = _QueuedFaceFlowSource([
      () async => {
            'refreshStatus': false,
          },
    ]);

    await _pumpProductionWidget(
      tester,
      statusSource: statusSource,
      faceFlowSource: faceFlowSource,
    );

    await _triggerSwipe(tester, toRight: true);

    expect(_swipeLabel(tester), contains('CHECK IN'));
    expect(find.text('No record yet'), findsOneWidget);
    expect(find.text('Please Check In'), findsOneWidget);
    expect(find.byKey(const Key('attendance-swipe-action'), skipOffstage: false), findsOneWidget);
  });

  testWidgets('fetch failure on production widget shows retry and retry restores correct truth', (tester) async {
    final statusSource = _QueuedPayloadSource([
      () async => throw Exception('boom'),
      () async => _statusPayload(
            canClockIn: true,
            headerStateMessage: 'No record yet',
            headerDetailMessage: 'Please Check In',
          ),
    ]);

    await _pumpProductionWidget(
      tester,
      statusSource: statusSource,
      faceFlowSource: _QueuedFaceFlowSource([]),
    );

    expect(find.byKey(const Key('attendance-status-error-card')), findsOneWidget);
    expect(find.text('Failed to fetch attendance status. Please retry.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('attendance-status-retry-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attendance-status-error-card')), findsNothing);
    expect(_swipeLabel(tester), contains('CHECK IN'));
    expect(find.text('No record yet'), findsOneWidget);
    expect(find.text('Please Check In'), findsOneWidget);
  });

  testWidgets('repeated refresh on production widget does not duplicate visible action elements', (tester) async {
    final statusSource = _QueuedPayloadSource([
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            firstCheckIn: '09:00:00',
            headerStateMessage: 'Checked In',
            headerDetailMessage: 'Earliest Check Out: 18:00',
          ),
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            firstCheckIn: '09:00:00',
            headerStateMessage: 'Checked In',
            headerDetailMessage: 'Earliest Check Out: 18:00',
          ),
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            firstCheckIn: '09:00:00',
            headerStateMessage: 'Checked In',
            headerDetailMessage: 'Earliest Check Out: 18:00',
          ),
    ]);

    await _pumpProductionWidget(
      tester,
      statusSource: statusSource,
      faceFlowSource: _QueuedFaceFlowSource([]),
    );

    final dynamic state = tester.state(find.byType(CheckInCheckOutFormPage));
    await state.refreshAttendanceStatus();
    await tester.pumpAndSettle();
    await state.refreshAttendanceStatus();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attendance-swipe-action'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('attendance-header-note')), findsOneWidget);
    expect(find.text('Checked In'), findsOneWidget);
    expect(find.text('Earliest Check Out: 18:00'), findsOneWidget);
  });

  testWidgets('production header note stays aligned with visible CTA', (tester) async {
    final statusSource = _QueuedPayloadSource([
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            firstCheckIn: '09:00:00',
            headerStateMessage: 'Checked In',
            headerDetailMessage: 'Earliest Check Out: 18:00',
          ),
    ]);

    await _pumpProductionWidget(
      tester,
      statusSource: statusSource,
      faceFlowSource: _QueuedFaceFlowSource([]),
    );

    final dynamic state = tester.state(find.byType(CheckInCheckOutFormPage));
    expect('${state.swipeDirection}', contains('CHECK OUT'));
    final label = _swipeLabel(tester);
    if (label.isNotEmpty) {
      expect(label, contains('CHECK OUT'));
    }
    expect(find.text('Checked In'), findsOneWidget);
    expect(find.text('Earliest Check Out: 18:00'), findsOneWidget);
    expect(find.byKey(const Key('attendance-header-detail-note')), findsOneWidget);
    expect(find.text('Earliest Check Out: 18:00'), findsOneWidget);
  });
}
