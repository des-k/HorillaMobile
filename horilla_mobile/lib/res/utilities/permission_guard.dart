import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PermissionGuardResult {
  final bool isAllowed;
  final String? message;
  final int? statusCode;

  const PermissionGuardResult({required this.isAllowed, this.message, this.statusCode});

  bool get isForbidden => statusCode == 403;
  bool get isUnauthorized => statusCode == 401;
}

final Map<String, PermissionGuardResult> _permissionGuardCache = <String, PermissionGuardResult>{};

String _permissionGuardCacheKey(Uri uri, Map<String, String> headers) =>
    "${headers['Authorization'] ?? ''}|${uri.toString()}";

void clearPermissionGuardCache() {
  _permissionGuardCache.clear();
}

String permissionGuardMessageForStatus(int statusCode) {
  if (statusCode == 401) {
    return 'Session expired, please log in again.';
  }
  if (statusCode == 403) {
    return 'You do not have access to this feature.';
  }
  if (statusCode >= 500) {
    return 'Server error. Try again later.';
  }
  return 'Could not verify access due to network/server timeout. Try again.';
}

String permissionGuardMessageForError(Object error) {
  if (error is TimeoutException || error is SocketException) {
    return 'Could not verify access due to network/server timeout. Try again.';
  }
  return 'Server error. Try again later.';
}

Future<PermissionGuardResult> guardedPermissionGet(
  Uri uri, {
  required Map<String, String> headers,
  Duration timeout = const Duration(seconds: 12),
  bool allowCached = true,
}) async {
  final cacheKey = _permissionGuardCacheKey(uri, headers);
  if (allowCached) {
    final cached = _permissionGuardCache[cacheKey];
    if (cached != null) {
      return cached;
    }
  }

  try {
    final response = await http.get(uri, headers: headers).timeout(timeout);
    final result = response.statusCode == 200
        ? PermissionGuardResult(isAllowed: true, statusCode: response.statusCode)
        : PermissionGuardResult(
            isAllowed: false,
            message: permissionGuardMessageForStatus(response.statusCode),
            statusCode: response.statusCode,
          );

    if (response.statusCode == 200 || response.statusCode == 401 || response.statusCode == 403) {
      _permissionGuardCache[cacheKey] = result;
    }
    return result;
  } catch (error) {
    return PermissionGuardResult(
      isAllowed: false,
      message: permissionGuardMessageForError(error),
    );
  }
}

Widget permissionNoticeTile(String? message, {VoidCallback? onRetry}) {
  if (message == null || message.trim().isEmpty) {
    return const SizedBox.shrink();
  }
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: Colors.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
      ],
    ),
  );
}
