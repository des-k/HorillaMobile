import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MyAttendanceHarness extends StatelessWidget {
  final Map<String, dynamic> payload;

  const _MyAttendanceHarness({required this.payload});

  String _displayTimeHHMM(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null' || s.toLowerCase() == 'none') {
      return '—';
    }
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (match != null) {
      final hh = (match.group(1) ?? '0').padLeft(2, '0');
      final mm = (match.group(2) ?? '0').padLeft(2, '0');
      return '$hh:$mm';
    }
    return s;
  }

  Widget _field(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Flexible(child: Text(value?.toString() ?? '—', textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Attendances')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(payload['employee_name']?.toString() ?? 'Unknown'),
            ),
            _field('Date', payload['attendance_date'] ?? '—'),
            _field('Check-In', _displayTimeHHMM(payload['attendance_clock_in'])),
            _field('Check-Out', _displayTimeHHMM(payload['attendance_clock_out'])),
            _field('Shift', payload['shift_name'] ?? '—'),
            _field('Minimum Hour', payload['minimum_hour'] ?? '—'),
            _field('Check-In Date', payload['attendance_clock_in_date'] ?? '—'),
            _field('Check-Out Date', payload['attendance_clock_out_date'] ?? '—'),
            _field('At Work', payload['attendance_worked_hour'] ?? '—'),
          ],
        ),
      ),
    );
  }
}

Future<void> _pumpHarness(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('my attendance screen handles empty partial and refreshed payload safely', (tester) async {
    await _pumpHarness(
      tester,
      const _MyAttendanceHarness(
        payload: {
          'employee_name': 'Alya Putri',
          'attendance_date': '2026-03-20',
          'attendance_clock_in': '',
          'attendance_clock_out': null,
          'shift_name': 'Morning Shift',
          'minimum_hour': '08:00',
          'attendance_clock_in_date': '2026-03-20',
          'attendance_clock_out_date': '',
          'attendance_worked_hour': '00:00',
        },
      ),
    );

    expect(find.text('My Attendances'), findsOneWidget);
    expect(find.text('Alya Putri'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('Morning Shift'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshed my attendance payload replaces stale values deterministically', (tester) async {
    await _pumpHarness(
      tester,
      const _MyAttendanceHarness(
        payload: {
          'employee_name': 'Alya Putri',
          'attendance_date': '2026-03-20',
          'attendance_clock_in': '08:05:00',
          'attendance_clock_out': '',
          'shift_name': 'Morning Shift',
          'minimum_hour': '08:00',
          'attendance_clock_in_date': '2026-03-20',
          'attendance_clock_out_date': '',
          'attendance_worked_hour': '03:15',
        },
      ),
    );

    expect(find.text('08:05'), findsOneWidget);
    expect(find.text('03:15'), findsOneWidget);

    await _pumpHarness(
      tester,
      const _MyAttendanceHarness(
        payload: {
          'employee_name': 'Alya Putri',
          'attendance_date': '2026-03-20',
          'attendance_clock_in': '08:05:00',
          'attendance_clock_out': '17:02:00',
          'shift_name': 'Morning Shift',
          'minimum_hour': '08:00',
          'attendance_clock_in_date': '2026-03-20',
          'attendance_clock_out_date': '2026-03-20',
          'attendance_worked_hour': '08:57',
        },
      ),
    );

    expect(find.text('17:02'), findsOneWidget);
    expect(find.text('08:57'), findsOneWidget);
    expect(find.text('03:15'), findsNothing);
  });
}
