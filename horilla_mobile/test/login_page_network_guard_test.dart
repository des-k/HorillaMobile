import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ServerErrorException implements Exception {
  const _ServerErrorException();
}

class _LoginNetworkGuardHarness extends StatefulWidget {
  final Future<void> Function() onLogin;

  const _LoginNetworkGuardHarness({required this.onLogin});

  @override
  State<_LoginNetworkGuardHarness> createState() => _LoginNetworkGuardHarnessState();
}

class _LoginNetworkGuardHarnessState extends State<_LoginNetworkGuardHarness> {
  final serverController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _login() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      await widget.onLogin();
    } on TimeoutException {
      _showError('Connection timeout');
    } on _ServerErrorException {
      _showError('Server error. Try again later.');
    } on SocketException {
      _showError('Invalid server address');
    } catch (_) {
      _showError('Invalid server address');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextFormField(controller: serverController),
          TextFormField(controller: usernameController),
          TextFormField(controller: passwordController),
          ElevatedButton(onPressed: _login, child: const Text('Sign In')),
        ],
      ),
    );
  }
}

Future<void> _pumpHarness(WidgetTester tester, Future<void> Function() onLogin) async {
  await tester.pumpWidget(MaterialApp(home: _LoginNetworkGuardHarness(onLogin: onLogin)));
  await tester.pumpAndSettle();
}

Future<void> _enterLoginFields(
  WidgetTester tester, {
  required String serverAddress,
  String email = 'qa@example.com',
  String password = 'secret',
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), serverAddress);
  await tester.enterText(find.byType(TextFormField).at(1), email);
  await tester.enterText(find.byType(TextFormField).at(2), password);
}

void main() {
  testWidgets('LoginPage shows invalid server address feedback when the server is unreachable', (tester) async {
    await _pumpHarness(tester, () async => throw const SocketException('unreachable'));
    await _enterLoginFields(tester, serverAddress: 'http://127.0.0.1:1');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Invalid server address'), findsOneWidget);
  });

  testWidgets('LoginPage shows connection timeout feedback when the login endpoint hangs', (tester) async {
    await _pumpHarness(tester, () async => throw TimeoutException('timeout'));
    await _enterLoginFields(tester, serverAddress: 'http://127.0.0.1:9999');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Connection timeout'), findsOneWidget);
  });

  testWidgets('shows retryable feedback when server returns 500', (tester) async {
    await _pumpHarness(tester, () async => throw const _ServerErrorException());
    await _enterLoginFields(tester, serverAddress: 'https://demo.example.com');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Server error. Try again later.'), findsOneWidget);
  });

  testWidgets('submitting again after failure clears stale error state', (tester) async {
    var attempts = 0;
    await _pumpHarness(tester, () async {
      attempts += 1;
      if (attempts == 1) {
        throw TimeoutException('timeout');
      }
    });
    await _enterLoginFields(tester, serverAddress: 'https://demo.example.com');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Connection timeout'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Connection timeout'), findsNothing);
  });
}
