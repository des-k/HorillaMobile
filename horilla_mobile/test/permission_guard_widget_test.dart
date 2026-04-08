import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/res/utilities/permission_guard.dart';

void main() {
  testWidgets('401 shows session expired message in guarded notice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: permissionNoticeTile(permissionGuardMessageForStatus(401)),
        ),
      ),
    );

    expect(find.text('Session expired, please log in again.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('403 shows access denied message in guarded notice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: permissionNoticeTile(permissionGuardMessageForStatus(403)),
        ),
      ),
    );

    expect(find.text('You do not have access to this feature.'), findsOneWidget);
  });

  testWidgets('retry button re-triggers callback when present', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: permissionNoticeTile(
            permissionGuardMessageForStatus(500),
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text('Server error. Try again later.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
  });
}
