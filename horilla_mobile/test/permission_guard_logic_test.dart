import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horilla/res/utilities/permission_guard.dart';

void main() {
  test('permission guard maps 401 403 and 5xx to specific user-facing messages', () {
    expect(permissionGuardMessageForStatus(401), 'Session expired, please log in again.');
    expect(permissionGuardMessageForStatus(403), 'You do not have access to this feature.');
    expect(permissionGuardMessageForStatus(503), 'Server error. Try again later.');
  });

  test('permission guard maps timeout and socket failures to retryable message', () {
    expect(
      permissionGuardMessageForError(TimeoutException('timeout')),
      'Could not verify access due to network/server timeout. Try again.',
    );
    expect(
      permissionGuardMessageForError(const SocketException('offline')),
      'Could not verify access due to network/server timeout. Try again.',
    );
  });

  test('PermissionGuardResult exposes forbidden/unauthorized helpers', () {
    expect(const PermissionGuardResult(isAllowed: false, statusCode: 403).isForbidden, isTrue);
    expect(const PermissionGuardResult(isAllowed: false, statusCode: 401).isUnauthorized, isTrue);
    expect(const PermissionGuardResult(isAllowed: true, statusCode: 200).isForbidden, isFalse);
  });
}
