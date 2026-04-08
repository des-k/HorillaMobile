import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FaceBiometricHarness extends StatefulWidget {
  final Future<void> Function() onStart;

  const _FaceBiometricHarness({required this.onStart});

  @override
  State<_FaceBiometricHarness> createState() => _FaceBiometricHarnessState();
}

class _FaceBiometricHarnessState extends State<_FaceBiometricHarness> {
  String? status;

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => status = null);
    try {
      await widget.onStart();
      if (!mounted) {
        return;
      }
      setState(() => status = 'Face flow ready');
    } catch (error) {
      _showMessage('Initialization failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(onPressed: _start, child: const Text('Start face flow')),
          if (status != null) Text(status!),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('face entry initialization failure is handled without crashing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _FaceBiometricHarness(onStart: () async => throw Exception('camera permission not granted'))),
    );

    await tester.tap(find.text('Start face flow'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Initialization failed:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry after face initialization failure clears stale state', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _FaceBiometricHarness(
          onStart: () async {
            attempts += 1;
            if (attempts == 1) {
              throw Exception('camera permission not granted');
            }
          },
        ),
      ),
    );

    await tester.tap(find.text('Start face flow'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Initialization failed:'), findsOneWidget);

    await tester.tap(find.text('Start face flow'));
    await tester.pumpAndSettle();

    expect(find.text('Face flow ready'), findsOneWidget);
    expect(find.textContaining('Initialization failed:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
