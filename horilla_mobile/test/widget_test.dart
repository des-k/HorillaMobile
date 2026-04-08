import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/horilla_main/home.dart';
import 'package:horilla/horilla_main/login.dart';
import 'package:horilla/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('LoginApp boots a MaterialApp with the root future page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(LoginApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(FutureBuilderPage), findsOneWidget);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(FutureBuilderPage), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('FutureBuilderPage routes authenticated users to the home page shell', (tester) async {
    SharedPreferences.setMockInitialValues({
      'token': 'cached-token',
      'typed_url': 'https://demo.example.com',
    });

    await tester.pumpWidget(LoginApp());
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(FutureBuilderPage), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('FutureBuilderPage handles invalid persisted auth state safely', (tester) async {
    SharedPreferences.setMockInitialValues({
      'token': '   ',
      'typed_url': 'https://demo.example.com',
    });

    await tester.pumpWidget(LoginApp());
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root app falls back cleanly when stored host/token is partial or corrupt', (tester) async {
    SharedPreferences.setMockInitialValues({
      'token': 'cached-token',
      'typed_url': 'not-a-valid-url',
    });

    await tester.pumpWidget(LoginApp());
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
