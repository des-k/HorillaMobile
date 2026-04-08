import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LocationGuardHarness extends StatefulWidget {
  final Future<void> Function() onResolveLocation;

  const _LocationGuardHarness({required this.onResolveLocation});

  @override
  State<_LocationGuardHarness> createState() => _LocationGuardHarnessState();
}

class _LocationGuardHarnessState extends State<_LocationGuardHarness> {
  String? stateText;

  void _showMessage(String message, {VoidCallback? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action == null ? null : SnackBarAction(label: 'Retry', onPressed: action),
      ),
    );
  }

  Future<void> _handleCheck() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => stateText = null);
    try {
      await widget.onResolveLocation();
      if (!mounted) {
        return;
      }
      setState(() => stateText = 'Location ready');
    } on _LocationServiceDisabledException {
      _showMessage('Location services are disabled. Please enable them.');
    } on _LocationPermissionDeniedException {
      _showMessage('Location permissions are denied.');
    } catch (error) {
      _showMessage('Failed to get location: $error', action: _handleCheck);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(onPressed: _handleCheck, child: const Text('Check location')),
          if (stateText != null) Text(stateText!),
        ],
      ),
    );
  }
}

class _LocationServiceDisabledException implements Exception {
  const _LocationServiceDisabledException();
}

class _LocationPermissionDeniedException implements Exception {
  const _LocationPermissionDeniedException();
}

void main() {
  testWidgets('service disabled shows stable fallback and does not crash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _LocationGuardHarness(onResolveLocation: () async => throw const _LocationServiceDisabledException())),
    );

    await tester.tap(find.text('Check location'));
    await tester.pumpAndSettle();

    expect(find.text('Location services are disabled. Please enable them.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission denied shows stable fallback and does not crash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _LocationGuardHarness(onResolveLocation: () async => throw const _LocationPermissionDeniedException())),
    );

    await tester.tap(find.text('Check location'));
    await tester.pumpAndSettle();

    expect(find.text('Location permissions are denied.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plugin throw is handled and retry clears stale state', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _LocationGuardHarness(
          onResolveLocation: () async {
            attempts += 1;
            if (attempts == 1) {
              throw Exception('gps failure');
            }
          },
        ),
      ),
    );

    await tester.tap(find.text('Check location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to get location:'), findsOneWidget);

    await tester.tap(find.text('Check location'));
    await tester.pumpAndSettle();

    expect(find.text('Location ready'), findsOneWidget);
    expect(find.textContaining('Failed to get location:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
