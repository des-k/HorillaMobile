import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivateImageCacheService {
  static final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};

  static Future<File?> getOrFetch({
    required String cacheKey,
    required String imageUrl,
    required String version,
    required String token,
  }) async {
    final normalizedKey = cacheKey.trim();
    final normalizedUrl = imageUrl.trim();
    final normalizedVersion = version.trim();
    final normalizedToken = token.trim();

    if (normalizedKey.isEmpty ||
        normalizedUrl.isEmpty ||
        normalizedVersion.isEmpty ||
        normalizedToken.isEmpty) {
      return null;
    }

    final inFlightKey = '$normalizedKey|$normalizedVersion|$normalizedUrl';
    final existing = _inFlight[inFlightKey];
    if (existing != null) {
      return existing;
    }

    final future = _getOrFetchInternal(
      cacheKey: normalizedKey,
      imageUrl: normalizedUrl,
      version: normalizedVersion,
      token: normalizedToken,
    );
    _inFlight[inFlightKey] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(inFlightKey);
    }
  }

  static Future<File?> _getOrFetchInternal({
    required String cacheKey,
    required String imageUrl,
    required String version,
    required String token,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final versionKey = 'private_image_cache.version.$cacheKey';
      final pathKey = 'private_image_cache.path.$cacheKey';
      final urlKey = 'private_image_cache.url.$cacheKey';

      final existingVersion = (prefs.getString(versionKey) ?? '').trim();
      final existingPath = (prefs.getString(pathKey) ?? '').trim();
      final existingUrl = (prefs.getString(urlKey) ?? '').trim();

      if (existingVersion == version &&
          existingUrl == imageUrl &&
          existingPath.isNotEmpty) {
        final cachedFile = File(existingPath);
        if (await cachedFile.exists()) {
          return cachedFile;
        }
      }

      final stalePath = existingPath;

      final response = await http.get(
        Uri.parse(imageUrl),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }

      final cacheDir = await _cacheDirectory();
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final extension = _detectExtension(imageUrl, response.headers['content-type']);
      final versionedName = '${_safeFileName(cacheKey)}__${_safeFileName(version)}';
      final targetPath = '${cacheDir.path}/$versionedName$extension';
      final file = File(targetPath);
      await file.writeAsBytes(response.bodyBytes, flush: true);

      if (stalePath.isNotEmpty && stalePath != file.path) {
        try {
          final oldFile = File(stalePath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (_) {}
      }

      await prefs.setString(versionKey, version);
      await prefs.setString(pathKey, file.path);
      await prefs.setString(urlKey, imageUrl);
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<void> invalidate({required String cacheKey}) async {
    final normalizedKey = cacheKey.trim();
    if (normalizedKey.isEmpty) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final versionKey = 'private_image_cache.version.$normalizedKey';
      final pathKey = 'private_image_cache.path.$normalizedKey';
      final urlKey = 'private_image_cache.url.$normalizedKey';
      final existingPath = (prefs.getString(pathKey) ?? '').trim();
      if (existingPath.isNotEmpty) {
        try {
          final oldFile = File(existingPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (_) {}
      }
      await prefs.remove(versionKey);
      await prefs.remove(pathKey);
      await prefs.remove(urlKey);
    } catch (_) {
      return;
    }
  }

  static Future<Directory> _cacheDirectory() async {
    final base = await getTemporaryDirectory();
    return Directory('${base.path}/private_image_cache');
  }

  static String _safeFileName(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }

  static String _detectExtension(String imageUrl, String? contentType) {
    final uri = Uri.tryParse(imageUrl);
    final path = uri?.path ?? '';
    final lastDot = path.lastIndexOf('.');
    if (lastDot >= 0 && lastDot < path.length - 1) {
      final ext = path.substring(lastDot);
      if (ext.length <= 10) {
        return ext;
      }
    }

    final type = (contentType ?? '').toLowerCase();
    if (type.contains('png')) return '.png';
    if (type.contains('jpeg') || type.contains('jpg')) return '.jpg';
    if (type.contains('webp')) return '.webp';
    if (type.contains('gif')) return '.gif';
    return '.img';
  }
}
