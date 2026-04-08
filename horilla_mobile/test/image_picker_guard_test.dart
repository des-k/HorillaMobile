import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImagePickerGuardHarness extends StatefulWidget {
  final Future<void> Function() onCapture;

  const _ImagePickerGuardHarness({required this.onCapture});

  @override
  State<_ImagePickerGuardHarness> createState() => _ImagePickerGuardHarnessState();
}

class _ImagePickerGuardHarnessState extends State<_ImagePickerGuardHarness> {
  String? status;

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capture() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => status = null);
    try {
      await widget.onCapture();
      if (!mounted) {
        return;
      }
      setState(() => status = 'Photo ready');
    } catch (error) {
      _showMessage('Failed to open camera: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(onPressed: _capture, child: const Text('Capture selfie')),
          if (status != null) Text(status!),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('camera/plugin throw is surfaced without crashing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _ImagePickerGuardHarness(onCapture: () async => throw Exception('camera unavailable'))),
    );

    await tester.tap(find.text('Capture selfie'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to open camera:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry after capture failure clears stale message', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _ImagePickerGuardHarness(
          onCapture: () async {
            attempts += 1;
            if (attempts == 1) {
              throw Exception('camera unavailable');
            }
          },
        ),
      ),
    );

    await tester.tap(find.text('Capture selfie'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to open camera:'), findsOneWidget);

    await tester.tap(find.text('Capture selfie'));
    await tester.pumpAndSettle();

    expect(find.text('Photo ready'), findsOneWidget);
    expect(find.textContaining('Failed to open camera:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
