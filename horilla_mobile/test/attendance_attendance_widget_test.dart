import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/attendance_views/attendance_attendance.dart';

class _AttendanceRecapHarness extends StatefulWidget {
  final Map<String, _HarnessPayload> payloads;
  final String initialEmployee;
  final String initialMonth;

  const _AttendanceRecapHarness({
    required this.payloads,
    required this.initialEmployee,
    required this.initialMonth,
  });

  @override
  State<_AttendanceRecapHarness> createState() => _AttendanceRecapHarnessState();
}

class _AttendanceRecapHarnessState extends State<_AttendanceRecapHarness> {
  late String _employee;
  late String _month;
  bool _error = false;
  int _refreshCount = 0;
  late List<MonthlyAttendanceRow> _rows;
  late MonthlyAttendanceSummary _summary;

  @override
  void initState() {
    super.initState();
    _employee = widget.initialEmployee;
    _month = widget.initialMonth;
    _applyPayload();
  }

  _HarnessPayload get _currentPayload => widget.payloads['$_employee|$_month']!;

  void _applyPayload() {
    final payload = _currentPayload;
    _error = payload.error;
    _rows = payload.rows;
    _summary = payload.summary;
  }

  void _changeEmployee(String employee) {
    setState(() {
      _employee = employee;
      _refreshCount += 1;
      _applyPayload();
    });
  }

  void _changeMonth(String month) {
    setState(() {
      _month = month;
      _refreshCount += 1;
      _applyPayload();
    });
  }

  void _retry() {
    setState(() {
      _error = false;
      _refreshCount += 1;
      final payload = _currentPayload.afterRetry ?? _currentPayload;
      _rows = payload.rows;
      _summary = payload.summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Employee: $_employee'),
          Text('Month: $_month'),
          Text('Refresh count: $_refreshCount'),
          Row(
            children: [
              TextButton(
                onPressed: () => _changeEmployee('Other User'),
                child: const Text('Switch Employee'),
              ),
              TextButton(
                onPressed: () => _changeMonth('2026-04'),
                child: const Text('Switch Month'),
              ),
            ],
          ),
          if (_error) ...[
            const SizedBox(height: 24),
            const Text('Failed to load (HTTP 500)'),
            ElevatedButton(onPressed: _retry, child: const Text('Retry')),
          ] else ...[
            _SummaryCard(label: 'LATE', value: _summary.lateMinutes),
            _SummaryCard(label: 'EARLY OUT', value: _summary.earlyOutMinutes),
            _SummaryCard(label: 'TOTAL LATE + EARLY OUT', value: _summary.totalMinutes),
            if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('No data'),
              )
            else
              ..._rows.map((row) => _AttendanceRowCard(row: row)),
          ],
        ],
      ),
    );
  }
}

class _HarnessPayload {
  final List<MonthlyAttendanceRow> rows;
  final MonthlyAttendanceSummary summary;
  final bool error;
  final _HarnessPayload? afterRetry;

  const _HarnessPayload({
    required this.rows,
    required this.summary,
    this.error = false,
    this.afterRetry,
  });
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text('$value Minutes'),
      ),
    );
  }
}

class _AttendanceRowCard extends StatelessWidget {
  final MonthlyAttendanceRow row;

  const _AttendanceRowCard({required this.row});

  String _safe(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return '-';
    }
    return trimmed;
  }

  String _penaltyText(String minuteValue, String legacyValue) {
    final trimmedMinute = minuteValue.trim();
    if (trimmedMinute.isNotEmpty) {
      return '$trimmedMinute Minutes';
    }
    return _safe(legacyValue);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('${row.no ?? '-'} • ${row.date}'),
        subtitle: Text(row.workType.isEmpty ? '-' : row.workType),
        children: [
          ListTile(title: const Text('Check In'), subtitle: Text(_safe(row.checkIn))),
          ListTile(title: const Text('Check Out'), subtitle: Text(_safe(row.checkOut))),
          ListTile(title: const Text('Late'), subtitle: Text(_penaltyText(row.lateMinutes, row.late))),
          ListTile(title: const Text('Early Out'), subtitle: Text(_penaltyText(row.earlyOutMinutes, row.earlyOut))),
          ListTile(
            title: const Text('Shift'),
            subtitle: Text(row.shiftInformation.isEmpty ? 'No Shift Information' : row.shiftInformation),
          ),
          if (row.note.trim().isNotEmpty)
            ListTile(title: const Text('Note'), subtitle: Text(row.note.trim())),
        ],
      ),
    );
  }
}

MonthlyAttendanceRow _row(Map<String, dynamic> json) => MonthlyAttendanceRow.fromJson(json);
MonthlyAttendanceSummary _summary(Map<String, dynamic> json) => MonthlyAttendanceSummary.fromJson(json);

Future<void> _pumpHarness(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  final partialRow = _row({
    'no': 1,
    'date': '2026-03-20',
    'shift_information': '',
    'check_in': '',
    'check_out': '2026-03-21T05:30:00',
    'work_type': null,
    'late': null,
    'early_out': '',
    'late_minutes': null,
    'early_out_minutes': null,
    'note': '',
    'is_off': false,
  });

  final refreshedRow = _row({
    'no': 2,
    'date': '2026-04-01',
    'shift_information': 'Night Shift',
    'check_in': '2026-04-01T21:00:00',
    'check_out': '2026-04-02T05:30:00',
    'work_type': 'WFO',
    'late': '5',
    'early_out': '0',
    'late_minutes': '5.5',
    'early_out_minutes': '0',
    'note': 'Biometric + mobile mix',
    'is_off': false,
  });

  final otherEmployeeRow = _row({
    'no': 3,
    'date': '2026-04-02',
    'shift_information': 'Morning Shift',
    'check_in': '08:05',
    'check_out': '17:00',
    'work_type': 'WFH',
    'late': '0',
    'early_out': '10',
    'late_minutes': '0',
    'early_out_minutes': '10.5',
    'note': 'Manual review complete',
    'is_off': false,
  });

  testWidgets('empty overview payload renders stable placeholder without crash', (tester) async {
    await _pumpHarness(
      tester,
      _AttendanceRecapHarness(
        initialEmployee: 'Current User',
        initialMonth: '2026-03',
        payloads: {
          'Current User|2026-03': _HarnessPayload(
            rows: const [],
            summary: const MonthlyAttendanceSummary(),
          ),
        },
      ),
    );

    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('No data'), findsOneWidget);
    expect(find.text('LATE'), findsOneWidget);
    expect(find.text('EARLY OUT'), findsOneWidget);
    expect(find.text('TOTAL LATE + EARLY OUT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial attendance row metadata does not break overview card rendering', (tester) async {
    await _pumpHarness(
      tester,
      _AttendanceRecapHarness(
        initialEmployee: 'Current User',
        initialMonth: '2026-03',
        payloads: {
          'Current User|2026-03': _HarnessPayload(
            rows: [partialRow],
            summary: _summary({
              'late_minutes': null,
              'early_out_minutes': -5,
              'total_minutes': '0',
            }),
          ),
        },
      ),
    );

    expect(find.text('1 • 2026-03-20'), findsOneWidget);
    await tester.tap(find.text('1 • 2026-03-20'));
    await tester.pumpAndSettle();

    expect(find.text('No Shift Information'), findsOneWidget);
    expect(find.text('Check In'), findsOneWidget);
    expect(find.text('Check Out'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Early Out'), findsOneWidget);
    expect(find.text('-'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry after overview fetch error restores list without stale error', (tester) async {
    await _pumpHarness(
      tester,
      _AttendanceRecapHarness(
        initialEmployee: 'Current User',
        initialMonth: '2026-03',
        payloads: {
          'Current User|2026-03': _HarnessPayload(
            error: true,
            rows: const [],
            summary: const MonthlyAttendanceSummary(),
            afterRetry: _HarnessPayload(
              rows: [refreshedRow],
              summary: _summary({
                'late_minutes': 5,
                'early_out_minutes': 0,
                'total_minutes': 5,
              }),
            ),
          ),
        },
      ),
    );

    expect(find.text('Failed to load (HTTP 500)'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load (HTTP 500)'), findsNothing);
    expect(find.text('2 • 2026-04-01'), findsOneWidget);
    expect(find.text('Refresh count: 1'), findsOneWidget);
  });

  testWidgets('changing filters replaces stale rows deterministically', (tester) async {
    await _pumpHarness(
      tester,
      _AttendanceRecapHarness(
        initialEmployee: 'Current User',
        initialMonth: '2026-03',
        payloads: {
          'Current User|2026-03': _HarnessPayload(
            rows: [partialRow],
            summary: _summary({
              'late_minutes': 0,
              'early_out_minutes': 0,
              'total_minutes': 0,
            }),
          ),
          'Other User|2026-03': _HarnessPayload(
            rows: [otherEmployeeRow],
            summary: _summary({
              'late_minutes': 0,
              'early_out_minutes': 10,
              'total_minutes': 10,
            }),
          ),
          'Other User|2026-04': _HarnessPayload(
            rows: [refreshedRow],
            summary: _summary({
              'late_minutes': 5,
              'early_out_minutes': 0,
              'total_minutes': 5,
            }),
          ),
        },
      ),
    );

    expect(find.text('1 • 2026-03-20'), findsOneWidget);
    await tester.tap(find.text('Switch Employee'));
    await tester.pumpAndSettle();
    expect(find.text('1 • 2026-03-20'), findsNothing);
    expect(find.text('3 • 2026-04-02'), findsOneWidget);

    await tester.tap(find.text('Switch Month'));
    await tester.pumpAndSettle();
    expect(find.text('3 • 2026-04-02'), findsNothing);
    expect(find.text('2 • 2026-04-01'), findsOneWidget);
    expect(find.text('Refresh count: 2'), findsOneWidget);
  });

  test('summary parser preserves decimal minute strings', () {
    final summary = _summary({
      'late_minutes': '225.5',
      'early_out_minutes': '30.5',
      'total_minutes': '256.0',
    });

    expect(summary.lateMinutes, '225.5');
    expect(summary.earlyOutMinutes, '30.5');
    expect(summary.totalMinutes, '256');
  });

  test('row parser preserves decimal minute strings and keeps legacy fallback', () {
    final row = _row({
      'no': 9,
      'date': '2026-03-31',
      'shift_information': 'General Shift',
      'check_in': '08:00',
      'check_out': '17:00',
      'work_type': 'WFO',
      'late': '00:10',
      'early_out': '00:00',
      'late_minutes': '10.5',
      'early_out_minutes': '0',
      'note': '',
      'is_off': false,
    });

    expect(row.lateMinutes, '10.5');
    expect(row.earlyOutMinutes, '0');
    expect(row.late, '00:10');
  });

  testWidgets('summary header stays aligned with rendered attendance rows', (tester) async {
    await _pumpHarness(
      tester,
      _AttendanceRecapHarness(
        initialEmployee: 'Current User',
        initialMonth: '2026-03',
        payloads: {
          'Current User|2026-03': _HarnessPayload(
            rows: [partialRow, refreshedRow],
            summary: _summary({
              'late_minutes': 5,
              'early_out_minutes': 0,
              'total_minutes': 5,
            }),
          ),
        },
      ),
    );

    expect(find.text('5 Minutes'), findsNWidgets(2));
    expect(find.text('0 Minutes'), findsOneWidget);
    expect(find.text('1 • 2026-03-20'), findsOneWidget);
    expect(find.text('2 • 2026-04-01'), findsOneWidget);
  });

  testWidgets('decimal minute payload renders without truncation in summary and row details', (tester) async {
    final decimalRow = _row({
      'no': 4,
      'date': '2026-03-31',
      'shift_information': 'General Shift',
      'check_in': '08:00',
      'check_out': '16:00',
      'work_type': 'WFO',
      'late': '00:00',
      'early_out': '01:00',
      'late_minutes': '0',
      'early_out_minutes': '30.5',
      'note': 'Decimal evidence-based penalty',
      'is_off': false,
    });

    await _pumpHarness(
      tester,
      _AttendanceRecapHarness(
        initialEmployee: 'Current User',
        initialMonth: '2026-03',
        payloads: {
          'Current User|2026-03': _HarnessPayload(
            rows: [decimalRow],
            summary: _summary({
              'late_minutes': '225.5',
              'early_out_minutes': '30.5',
              'total_minutes': '256',
            }),
          ),
        },
      ),
    );

    expect(find.text('225.5 Minutes'), findsOneWidget);
    expect(find.text('30.5 Minutes'), findsOneWidget);
    await tester.tap(find.text('4 • 2026-03-31'));
    await tester.pumpAndSettle();
    expect(find.text('30.5 Minutes'), findsWidgets);
  });
}
