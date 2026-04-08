import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/attendance_views/attendance_punching_history.dart';

class _PunchHistoryHarness extends StatefulWidget {
  final List<PunchingHistoryItem> initialItems;
  final List<PunchingHistoryItem> filteredItems;
  final bool startWithError;

  const _PunchHistoryHarness({
    required this.initialItems,
    required this.filteredItems,
    this.startWithError = false,
  });

  @override
  State<_PunchHistoryHarness> createState() => _PunchHistoryHarnessState();
}

class _PunchHistoryHarnessState extends State<_PunchHistoryHarness> {
  late List<PunchingHistoryItem> _items;
  late bool _error;
  bool _otherEmployeeSelected = false;
  String _selectedSource = 'All';
  int refreshCount = 0;

  @override
  void initState() {
    super.initState();
    _error = widget.startWithError;
    _items = widget.initialItems;
  }

  void _applyFilters() {
    final baseItems = _otherEmployeeSelected ? widget.filteredItems : widget.initialItems;
    final nextItems = _selectedSource == 'All'
        ? baseItems
        : baseItems.where((item) => item.source == _selectedSource).toList();
    setState(() {
      _items = nextItems;
      refreshCount += 1;
    });
  }

  void retry() {
    setState(() {
      _error = false;
      _otherEmployeeSelected = false;
      _selectedSource = 'All';
      _items = widget.initialItems;
      refreshCount += 1;
    });
  }

  void selectOtherEmployee() {
    _otherEmployeeSelected = true;
    _applyFilters();
  }

  void selectSource(String source) {
    _selectedSource = source;
    _applyFilters();
  }

  Future<void> _openEmployeeDialog(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Employee'),
        content: ListTile(
          title: const Text('Other User'),
          onTap: () => Navigator.of(context).pop('2'),
        ),
      ),
    );
    if (selected != null) {
      selectOtherEmployee();
    }
  }

  Future<void> _openSourceDialog(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All Sources'),
              onTap: () => Navigator.of(context).pop('All'),
            ),
            ListTile(
              title: const Text('Mobile'),
              onTap: () => Navigator.of(context).pop('Mobile'),
            ),
            ListTile(
              title: const Text('Biometric'),
              onTap: () => Navigator.of(context).pop('Biometric'),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      selectSource(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Scaffold(
        body: Column(
          children: [
            const SizedBox(height: 64),
            const Text('Failed to load (HTTP 500)'),
            ElevatedButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Punching History')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const Key('employee-filter-field'),
            readOnly: true,
            onTap: () => _openEmployeeDialog(context),
            decoration: const InputDecoration(
              hintText: 'Select Employee',
              suffixIcon: Icon(Icons.search),
            ),
          ),
          TextFormField(
            key: const Key('source-filter-field'),
            readOnly: true,
            onTap: () => _openSourceDialog(context),
            decoration: const InputDecoration(
              hintText: 'Select Source',
              suffixIcon: Icon(Icons.filter_alt_outlined),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Refresh count: $refreshCount • Source: $_selectedSource'),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('No punching history found for selected filters'))
                : ListView(
                    children: _items
                        .map((item) => Card(
                              child: ExpansionTile(
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${item.punchDate} • ${item.punchTime}'),
                                    Text(item.source),
                                    Text(item.decisionStatus),
                                  ],
                                ),
                                children: [
                                  ListTile(title: const Text('Reason'), subtitle: Text(item.reason)),
                                  ListTile(title: const Text('Decision Source'), subtitle: Text(item.decisionSource)),
                                  ListTile(title: const Text('Work Mode'), subtitle: Text(item.workMode)),
                                  ListTile(title: const Text('Device Info'), subtitle: Text(item.deviceInfo)),
                                  ListTile(title: const Text('Location'), subtitle: Text(item.locationDisplay)),
                                  ListTile(title: const Text('Photo'), subtitle: Text(item.photoUrl ?? '-')),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

PunchingHistoryItem _item(Map<String, dynamic> json) => PunchingHistoryItem.fromJson(json);

Future<void> _pumpHarness(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

Future<void> _selectSource(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('source-filter-field')));
  await tester.pumpAndSettle();
  final sourceDialog = find.byType(AlertDialog);
  await tester.tap(
    find.descendant(
      of: sourceDialog,
      matching: find.widgetWithText(ListTile, label),
    ).last,
  );
  await tester.pumpAndSettle();
}

Future<void> _selectOtherEmployee(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('employee-filter-field')));
  await tester.pumpAndSettle();
  final employeeDialog = find.byType(AlertDialog);
  await tester.tap(
    find.descendant(
      of: employeeDialog,
      matching: find.widgetWithText(ListTile, 'Other User'),
    ).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  final mobileItem = _item({
    'id': 101,
    'punch_date': '2026-03-20',
    'punch_time': '08:00',
    'source': 'Mobile',
    'decision_status': 'SUPERSEDED',
    'decision_source': null,
    'work_mode': null,
    'device_info': null,
    'photo_url': null,
    'latitude': null,
    'longitude': null,
    'location_display': null,
    'google_maps_url': null,
    'accepted_to_attendance': false,
    'reason': null,
  });
  final biometricItem = _item({
    'id': 102,
    'punch_date': '2026-03-20',
    'punch_time': '17:05',
    'source': 'Biometric',
    'decision_status': 'ACCEPTED',
    'decision_source': 'Biometric sync',
    'work_mode': 'WFO',
    'device_info': 'Gate A',
    'photo_url': null,
    'latitude': null,
    'longitude': null,
    'location_display': 'HQ Lobby',
    'google_maps_url': null,
    'accepted_to_attendance': true,
    'reason': 'Used as final Check-Out',
  });
  final otherEmployeeItem = _item({
    'id': 202,
    'punch_date': '2026-03-21',
    'punch_time': '09:15',
    'source': 'Biometric',
    'decision_status': 'ACCEPTED',
    'decision_source': 'Biometric sync',
    'work_mode': 'WFO',
    'device_info': 'Gate B',
    'photo_url': null,
    'latitude': null,
    'longitude': null,
    'location_display': '-',
    'google_maps_url': null,
    'accepted_to_attendance': true,
    'reason': 'Used as final Check-In',
  });
  final partialMetadataItem = _item({
    'id': 303,
    'punch_date': '2026-03-22',
    'punch_time': '08:45',
    'source': 'Mobile',
    'decision_status': 'PENDING',
    'decision_source': null,
    'work_mode': '',
    'device_info': null,
    'photo_url': null,
    'latitude': null,
    'longitude': null,
    'location_display': null,
    'google_maps_url': null,
    'accepted_to_attendance': false,
    'reason': null,
  });

  testWidgets('biometric and mobile source badges render correctly', (tester) async {
    await _pumpHarness(
      tester,
      _PunchHistoryHarness(initialItems: [mobileItem, biometricItem], filteredItems: [otherEmployeeItem]),
    );

    expect(find.text('Mobile'), findsOneWidget);
    expect(find.text('Biometric'), findsOneWidget);
    expect(find.text('SUPERSEDED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('null-safe metadata renders without crashing when expanding a record', (tester) async {
    await _pumpHarness(
      tester,
      _PunchHistoryHarness(initialItems: [mobileItem, biometricItem], filteredItems: [otherEmployeeItem]),
    );

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Reason'), findsOneWidget);
    expect(find.text('Decision Source'), findsOneWidget);
    expect(find.text('Work Mode'), findsOneWidget);
    expect(find.text('Device Info'), findsOneWidget);
    expect(find.text('-'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing employee filter refreshes displayed records', (tester) async {
    await _pumpHarness(
      tester,
      _PunchHistoryHarness(initialItems: [mobileItem, biometricItem], filteredItems: [otherEmployeeItem]),
    );

    expect(find.text('SUPERSEDED'), findsOneWidget);
    expect(find.text('Other User'), findsNothing);

    await _selectOtherEmployee(tester);

    expect(find.text('SUPERSEDED'), findsNothing);
    expect(find.text('Used as final Check-In'), findsNothing);
    expect(find.text('Biometric'), findsWidgets);
  });

  testWidgets('failed history load shows retry and recovers when backend is restored', (tester) async {
    final harness = _PunchHistoryHarness(
      initialItems: [mobileItem, biometricItem],
      filteredItems: [otherEmployeeItem],
      startWithError: true,
    );
    await _pumpHarness(tester, harness);

    expect(find.text('Failed to load (HTTP 500)'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load (HTTP 500)'), findsNothing);
    expect(find.text('Mobile'), findsOneWidget);
  });

  testWidgets('empty state with valid filters renders stable placeholder', (tester) async {
    await _pumpHarness(
      tester,
      _PunchHistoryHarness(initialItems: [mobileItem, biometricItem], filteredItems: [otherEmployeeItem]),
    );

    await _selectOtherEmployee(tester);
    await _selectSource(tester, 'Mobile');

    expect(find.text('No punching history found for selected filters'), findsOneWidget);
    expect(find.text('Refresh count: 2 • Source: Mobile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial metadata row does not break expanded card rendering', (tester) async {
    await _pumpHarness(
      tester,
      _PunchHistoryHarness(initialItems: [partialMetadataItem], filteredItems: [otherEmployeeItem]),
    );

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('Decision Source'), findsOneWidget);
    expect(find.text('Reason'), findsOneWidget);
    expect(find.text('-'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing source filter and employee filter together refreshes deterministically', (tester) async {
    await _pumpHarness(
      tester,
      _PunchHistoryHarness(initialItems: [mobileItem, biometricItem], filteredItems: [otherEmployeeItem]),
    );

    await _selectSource(tester, 'Biometric');
    expect(find.text('SUPERSEDED'), findsNothing);
    expect(find.text('Refresh count: 1 • Source: Biometric'), findsOneWidget);

    await _selectOtherEmployee(tester);

    expect(find.text('Refresh count: 2 • Source: Biometric'), findsOneWidget);
    expect(find.text('Biometric'), findsWidgets);
    expect(find.text('Mobile'), findsNothing);
    expect(find.text('SUPERSEDED'), findsNothing);
  });

  testWidgets('retry after error returns list correctly', (tester) async {
    await _pumpHarness(
      tester,
      _PunchHistoryHarness(
        initialItems: [mobileItem, biometricItem],
        filteredItems: [otherEmployeeItem],
        startWithError: true,
      ),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load (HTTP 500)'), findsNothing);
    expect(find.text('Refresh count: 1 • Source: All'), findsOneWidget);
    expect(find.text('Mobile'), findsOneWidget);
    expect(find.text('Biometric'), findsOneWidget);
  });
}
