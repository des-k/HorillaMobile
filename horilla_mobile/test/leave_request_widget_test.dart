import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/res/utilities/leave_request_form_logic.dart';
import 'package:horilla/res/utilities/request_payloads.dart';

class _LeaveRequestDecisionHarness extends StatefulWidget {
  const _LeaveRequestDecisionHarness({
    this.status = 'requested',
    this.initialRejectReason = '',
  });

  final String status;
  final String initialRejectReason;

  @override
  State<_LeaveRequestDecisionHarness> createState() =>
      _LeaveRequestDecisionHarnessState();
}

class _LeaveRequestDecisionHarnessState extends State<_LeaveRequestDecisionHarness> {
  late final TextEditingController _rejectDescriptionController;
  String _decision = 'idle';
  Map<String, dynamic>? _lastPayload;

  @override
  void initState() {
    super.initState();
    _rejectDescriptionController =
        TextEditingController(text: widget.initialRejectReason);
  }

  @override
  void dispose() {
    _rejectDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _showRejectDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Confirmation',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Are you sure you want to Reject this Leave Request?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('leave-reject-reason-field'),
                controller: _rejectDescriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _decision = 'rejected';
                    _lastPayload = buildLeaveDecisionPayload(
                      approve: false,
                      rejectionReason: _rejectDescriptionController.text,
                    );
                  });
                  Navigator.pop(context);
                },
                style: ButtonStyle(
                  backgroundColor:
                      MaterialStateProperty.all<Color>(Colors.red),
                ),
                child: const Text('Continue', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showApproveDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Confirmation',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          content: const Text(
            'Are you sure you want to Approve this Leave Request?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontSize: 17,
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _decision = 'approved';
                    _lastPayload = buildLeaveDecisionPayload(
                      approve: true,
                      rejectionReason: _rejectDescriptionController.text,
                    );
                  });
                  Navigator.pop(context);
                },
                style: ButtonStyle(
                  backgroundColor:
                      MaterialStateProperty.all<Color>(Colors.green),
                ),
                child: const Text('Continue', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canShowActions =
        widget.status != 'rejected' && widget.status != 'cancelled';
    return Scaffold(
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${widget.status}'),
              const SizedBox(height: 12),
              if (canShowActions) ...[
                ElevatedButton(
                  onPressed: widget.status == 'approved' ? null : _showRejectDialog,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: widget.status == 'approved' ? null : _showApproveDialog,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Approve'),
                ),
              ],
              const SizedBox(height: 12),
              Text('Decision: $_decision'),
              Text('Payload: ${_lastPayload?.toString() ?? 'null'}'),
            ],
          ),
        ),
      );
  }
}

class _LeaveCreateScreenHarness extends StatefulWidget {
  const _LeaveCreateScreenHarness();

  @override
  State<_LeaveCreateScreenHarness> createState() =>
      _LeaveCreateScreenHarnessState();
}

class _LeaveCreateScreenHarnessState extends State<_LeaveCreateScreenHarness> {
  final TextEditingController _employeeController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String? _selectedLeaveId;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _startBreakdown = 'full_day';
  String? _endBreakdown = 'full_day';
  LeaveRequestValidationResult? _validation;
  bool _submitted = false;

  @override
  void dispose() {
    _employeeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final validation = validateLeaveRequestCreateForm(
      employeeText: _employeeController.text,
      selectedLeaveId: _selectedLeaveId,
      startDate: _startDate,
      startDateBreakdown: _startBreakdown,
      endDate: _endDate,
      endDateBreakdown: _endBreakdown,
      description: _descriptionController.text,
    );
    setState(() {
      _validation = validation;
      _submitted = validation.isValid;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('leave-employee-field'),
                controller: _employeeController,
                decoration: InputDecoration(
                  labelText: 'Employee',
                  errorText:
                      (_validation?.validateEmployee ?? false) ? 'Select employee' : null,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('leave-type-dropdown'),
                value: _selectedLeaveId,
                decoration: InputDecoration(
                  labelText: 'Leave Type',
                  errorText: (_validation?.validateLeaveType ?? false)
                      ? 'Select leave type'
                      : null,
                ),
                items: const [
                  DropdownMenuItem(value: 'annual', child: Text('Annual Leave')),
                  DropdownMenuItem(value: 'sick', child: Text('Sick Leave')),
                ],
                onChanged: (value) => setState(() => _selectedLeaveId = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => _startDate = DateTime(2026, 3, 20)),
                    child: const Text('Set Start Date'),
                  ),
                  const SizedBox(width: 8),
                  Text(_startDate == null ? 'Start date not set' : 'Start date ready'),
                ],
              ),
              const SizedBox(height: 12),
              LeaveBreakdownDropdown(
                label: 'Start Date Breakdown',
                selectedKey: _startBreakdown,
                hasError: _validation?.validateStartDateBreakdown ?? false,
                onChanged: (value) => setState(() => _startBreakdown = value),
              ),
              if (_validation?.validateStartDate ?? false)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Please select start date',
                      style: TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => _endDate = DateTime(2026, 3, 21)),
                    child: const Text('Set End Date'),
                  ),
                  const SizedBox(width: 8),
                  Text(_endDate == null ? 'End date not set' : 'End date ready'),
                ],
              ),
              const SizedBox(height: 12),
              LeaveBreakdownDropdown(
                label: 'End Date Breakdown',
                selectedKey: _endBreakdown,
                hasError: _validation?.validateEndDateBreakdown ?? false,
                onChanged: (value) => setState(() => _endBreakdown = value),
              ),
              if (_validation?.validateEndDate ?? false)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Please select end date',
                      style: TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('leave-description-field'),
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  errorText: (_validation?.validateDescription ?? false)
                      ? 'Enter description'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _submit, child: const Text('Save')),
              const SizedBox(height: 12),
              Text(_submitted ? 'submitted' : 'blocked'),
              Text('start:${_startBreakdown ?? '-'}'),
              Text('end:${_endBreakdown ?? '-'}'),
            ],
          ),
        ),
      );
  }
}

Future<void> _pumpHarness(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: child));
}

void main() {
  testWidgets('leave reject without reason is allowed', (tester) async {
    await _pumpHarness(tester, const _LeaveRequestDecisionHarness());

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to Reject this Leave Request?'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Decision: rejected'), findsOneWidget);
    expect(find.text("Payload: {reason: }"), findsOneWidget);
  });

  testWidgets('leave reject with reason preserves entered reason', (tester) async {
    await _pumpHarness(tester, const _LeaveRequestDecisionHarness());

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('leave-reject-reason-field')),
      '  needs docs  ',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Decision: rejected'), findsOneWidget);
    expect(find.text("Payload: {reason: needs docs}"), findsOneWidget);
  });

  testWidgets('leave approve flow does not send reject reason payload',
      (tester) async {
    await _pumpHarness(
      tester,
      const _LeaveRequestDecisionHarness(initialRejectReason: 'should be ignored'),
    );

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to Approve this Leave Request?'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Decision: approved'), findsOneWidget);
    expect(find.text('Payload: null'), findsOneWidget);
  });

  testWidgets('create leave blocks submit when required fields are empty',
      (tester) async {
    await _pumpHarness(tester, const _LeaveCreateScreenHarness());

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('blocked'), findsOneWidget);
    expect(find.text('Select employee'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('leave-employee-field')), 'John');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Select leave type'), findsOneWidget);

    await tester.tap(find.byKey(const Key('leave-type-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annual Leave').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Please select start date'), findsOneWidget);

    await tester.tap(find.text('Set Start Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Please select end date'), findsOneWidget);

    await tester.tap(find.text('Set End Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter description'), findsOneWidget);
  });

  testWidgets('half day breakdown widgets render for start and end dates',
      (tester) async {
    await _pumpHarness(tester, const _LeaveCreateScreenHarness());

    expect(find.text('Start Date Breakdown'), findsOneWidget);
    expect(find.text('End Date Breakdown'), findsOneWidget);
    expect(find.text('Full Day'), findsNWidgets(2));
  });

  testWidgets('half day breakdown selection updates chosen values',
      (tester) async {
    await _pumpHarness(tester, const _LeaveCreateScreenHarness());

    await tester.tap(find.text('Full Day').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second Half').last);
    await tester.pumpAndSettle();
    expect(find.text('start:second_half'), findsOneWidget);

    await tester.tap(find.text('Full Day').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('First Half').last);
    await tester.pumpAndSettle();
    expect(find.text('end:first_half'), findsOneWidget);
  });
}
