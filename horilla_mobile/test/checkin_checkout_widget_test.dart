import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/checkin_checkout/checkin_checkout_views/mobile_header_state.dart';

typedef _StatusFetcher = Future<Map<String, dynamic>> Function();
typedef _FaceFlowLauncher = Future<Map<String, dynamic>?> Function();

class _QueuedStatusSource {
  _QueuedStatusSource(this._responses);

  final List<_StatusFetcher> _responses;
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

class _CheckInOutHarness extends StatefulWidget {
  const _CheckInOutHarness({
    required this.fetchStatus,
    required this.startFaceFlow,
    this.supportsUpdateClockOutAction = false,
  });

  final Future<Map<String, dynamic>> Function() fetchStatus;
  final _FaceFlowLauncher startFaceFlow;
  final bool supportsUpdateClockOutAction;

  @override
  State<_CheckInOutHarness> createState() => _CheckInOutHarnessState();
}

class _CheckInOutHarnessState extends State<_CheckInOutHarness> {
  Map<String, dynamic>? _status;
  String? _error;
  bool _loading = true;
  int _refreshCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.fetchStatus();
      if (!mounted) return;
      setState(() {
        _status = data;
        _loading = false;
        _error = null;
        _refreshCount += 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to fetch attendance status';
      });
    }
  }

  Future<void> _handleFaceFlow() async {
    try {
      final result = await widget.startFaceFlow();
      if (!mounted) return;
      if (result is Map<String, dynamic> && result['refreshStatus'] == true) {
        await _refreshStatus();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Face flow failed')));
    }
  }

  bool get _canClockIn => (_status?['can_clock_in'] ?? false) == true;
  bool get _canClockOut => (_status?['can_clock_out'] ?? false) == true;
  bool get _canUpdateClockOut => (_status?['can_update_clock_out'] ?? false) == true;
  bool get _hasCheckedIn => (_status?['has_checked_in'] ?? false) == true;

  String _fallbackHeaderMessage() {
    if (_canClockOut || _hasCheckedIn) {
      return 'Checked In';
    }
    if ((_status?['has_checked_out'] ?? false) == true) {
      return 'Checked Out';
    }
    return 'No record yet';
  }

  @override
  Widget build(BuildContext context) {
    final headerState = MobileAttendanceHeaderState.fromApi(_status ?? const {});
    final headerMessage = headerState.resolveMainMessage(_fallbackHeaderMessage());

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            const LinearProgressIndicator(key: Key('status-loading')),
          if (_error != null)
            Container(
              key: const Key('status-error-card'),
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  const Expanded(child: Text('Failed to fetch attendance status')),
                  TextButton(
                    key: const Key('retry-fetch-status'),
                    onPressed: _refreshStatus,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (_status != null)
            Container(
              key: const Key('status-card'),
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              color: Colors.red,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headerMessage,
                    key: const Key('header-note'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Refresh count: $_refreshCount',
                    key: const Key('refresh-count'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                key: const Key('refresh-button'),
                onPressed: _refreshStatus,
                child: const Text('Refresh Status'),
              ),
              ElevatedButton(
                key: const Key('face-flow-button'),
                onPressed: _handleFaceFlow,
                child: const Text('Start Face Flow'),
              ),
              if (_canClockIn)
                ElevatedButton(
                  key: const Key('action-check-in'),
                  onPressed: () {},
                  child: const Text('Check In'),
                ),
              if (_canClockOut)
                ElevatedButton(
                  key: const Key('action-check-out'),
                  onPressed: () {},
                  child: const Text('Check Out'),
                ),
              if (widget.supportsUpdateClockOutAction && _canUpdateClockOut)
                OutlinedButton(
                  key: const Key('action-update-clock-out'),
                  onPressed: () {},
                  child: const Text('Update Check Out'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _statusPayload({
  bool canClockIn = false,
  bool canClockOut = false,
  bool canUpdateClockOut = false,
  bool hasCheckedIn = false,
  bool hasCheckedOut = false,
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
    if (headerStateCode != null) 'header_state_code': headerStateCode,
    if (headerStateMessage != null) 'header_state_message': headerStateMessage,
    if (headerDetailMessage != null) 'header_detail_message': headerDetailMessage,
  };
}

void main() {
  testWidgets('primary action switches from check in to check out after refreshed canonical state', (tester) async {
    final source = _QueuedStatusSource([
      () async => _statusPayload(
            canClockIn: true,
            canClockOut: false,
            headerStateMessage: 'No record yet',
          ),
      () async => _statusPayload(
            canClockIn: false,
            canClockOut: true,
            hasCheckedIn: true,
            headerStateMessage: 'Checked In',
          ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: _CheckInOutHarness(
          fetchStatus: source.fetch,
          startFaceFlow: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsOneWidget);
    expect(find.byKey(const Key('action-check-out')), findsNothing);

    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsNothing);
    expect(find.byKey(const Key('action-check-out')), findsOneWidget);
    expect(find.text('Checked In'), findsOneWidget);
    expect(find.byKey(const Key('status-card')), findsOneWidget);
  });

  testWidgets('stale primary action is removed after backend truth changes', (tester) async {
    final source = _QueuedStatusSource([
      () async => _statusPayload(canClockIn: true, headerStateMessage: 'No record yet'),
      () async => _statusPayload(
            canClockIn: false,
            canClockOut: false,
            hasCheckedOut: true,
            headerStateMessage: 'Checked Out early',
          ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: _CheckInOutHarness(fetchStatus: source.fetch, startFaceFlow: () async => null)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsOneWidget);
    expect(find.byKey(const Key('action-check-out')), findsNothing);

    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsNothing);
    expect(find.byKey(const Key('action-check-out')), findsNothing);
    expect(find.text('Checked Out early'), findsOneWidget);
  });

  testWidgets('duplicate punch guard disables invalid action exposure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _CheckInOutHarness(
          fetchStatus: () async => _statusPayload(
            canClockIn: false,
            canClockOut: false,
            hasCheckedIn: true,
            headerStateMessage: 'Checked In',
          ),
          startFaceFlow: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsNothing);
    expect(find.byKey(const Key('action-check-out')), findsNothing);
    expect(find.byKey(const Key('action-update-clock-out')), findsNothing);
    expect(find.text('Checked In'), findsOneWidget);
  });

  testWidgets('update clock out flag alone does not expose impossible primary action when direct support is absent', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _CheckInOutHarness(
          fetchStatus: () async => _statusPayload(
            canClockIn: false,
            canClockOut: false,
            canUpdateClockOut: true,
            hasCheckedIn: true,
            headerStateMessage: 'Checked In',
          ),
          startFaceFlow: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsNothing);
    expect(find.byKey(const Key('action-check-out')), findsNothing);
    expect(find.byKey(const Key('action-update-clock-out')), findsNothing);
  });

  testWidgets('face flow success refreshes parent screen from backend truth', (tester) async {
    final source = _QueuedStatusSource([
      () async => _statusPayload(canClockIn: true, headerStateMessage: 'No record yet'),
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            headerStateMessage: 'Checked In',
          ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: _CheckInOutHarness(
          fetchStatus: source.fetch,
          startFaceFlow: () async => {'checkedIn': true, 'refreshStatus': true},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsOneWidget);

    await tester.tap(find.byKey(const Key('face-flow-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsNothing);
    expect(find.byKey(const Key('action-check-out')), findsOneWidget);
    expect(find.text('Checked In'), findsOneWidget);
  });

  testWidgets('face flow cancel keeps previous stable state without crash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _CheckInOutHarness(
          fetchStatus: () async => _statusPayload(canClockIn: true, headerStateMessage: 'No record yet'),
          startFaceFlow: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-flow-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action-check-in')), findsOneWidget);
    expect(find.byKey(const Key('action-check-out')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fetch failure shows retryable fallback and retry restores actionable state', (tester) async {
    final source = _QueuedStatusSource([
      () async => throw Exception('server down'),
      () async => _statusPayload(canClockIn: true, headerStateMessage: 'No record yet'),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: _CheckInOutHarness(fetchStatus: source.fetch, startFaceFlow: () async => null)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status-error-card')), findsOneWidget);
    expect(find.byKey(const Key('action-check-in')), findsNothing);

    await tester.tap(find.byKey(const Key('retry-fetch-status')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status-error-card')), findsNothing);
    expect(find.byKey(const Key('action-check-in')), findsOneWidget);
    expect(find.text('No record yet'), findsOneWidget);
  });

  testWidgets('repeated refresh does not duplicate UI elements', (tester) async {
    final source = _QueuedStatusSource([
      () async => _statusPayload(canClockIn: true, headerStateMessage: 'No record yet'),
      () async => _statusPayload(canClockIn: true, headerStateMessage: 'No record yet'),
      () async => _statusPayload(canClockIn: true, headerStateMessage: 'No record yet'),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: _CheckInOutHarness(fetchStatus: source.fetch, startFaceFlow: () async => null)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status-card')), findsOneWidget);
    expect(find.byKey(const Key('action-check-in')), findsOneWidget);
    expect(find.text('No record yet'), findsOneWidget);
    expect(find.byKey(const Key('status-error-card')), findsNothing);
  });

  testWidgets('header note stays aligned with visible CTA', (tester) async {
    final source = _QueuedStatusSource([
      () async => _statusPayload(
            canClockOut: true,
            hasCheckedIn: true,
            headerStateMessage: 'Checked In',
          ),
      () async => _statusPayload(
            canClockIn: false,
            canClockOut: false,
            hasCheckedOut: true,
            headerStateMessage: 'Attendance recorded',
          ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: _CheckInOutHarness(fetchStatus: source.fetch, startFaceFlow: () async => null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Checked In'), findsOneWidget);
    expect(find.byKey(const Key('action-check-out')), findsOneWidget);
    expect(find.byKey(const Key('action-check-in')), findsNothing);

    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();

    expect(find.text('Attendance recorded'), findsOneWidget);
    expect(find.byKey(const Key('action-check-in')), findsNothing);
    expect(find.byKey(const Key('action-check-out')), findsNothing);
  });
}
