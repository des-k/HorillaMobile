import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class MobileAttachmentItem {
  final String id;
  final String name;
  final String mimeType;
  final int? size;
  final String viewUrl;
  final String downloadUrl;
  final String deleteUrl;
  final String legacyUrl;

  const MobileAttachmentItem({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.viewUrl,
    required this.downloadUrl,
    required this.deleteUrl,
    required this.legacyUrl,
  });

  bool get isInlineViewable => isInlineViewableMimeType(mimeType);

  String preferredOpenUrl() {
    if (isInlineViewable && viewUrl.trim().isNotEmpty) return viewUrl.trim();
    if (downloadUrl.trim().isNotEmpty) return downloadUrl.trim();
    if (viewUrl.trim().isNotEmpty) return viewUrl.trim();
    return legacyUrl.trim();
  }
}

String absoluteAttachmentUrl(String baseUrl, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;

  final base = baseUrl.trim();
  if (base.isEmpty) return value;
  if (base.endsWith('/') && value.startsWith('/')) {
    return '${base.substring(0, base.length - 1)}$value';
  }
  if (!base.endsWith('/') && !value.startsWith('/')) {
    return '$base/$value';
  }
  return '$base$value';
}

String sanitizeAttachmentFileName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') return 'attachment';
  final cleaned = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'attachment';
  return cleaned;
}

String attachmentFileNameFromUrl(String baseUrl, String url) {
  try {
    final uri = Uri.parse(url.startsWith('http') ? url : absoluteAttachmentUrl(baseUrl, url));
    if (uri.pathSegments.isEmpty) return 'attachment';
    return sanitizeAttachmentFileName(uri.pathSegments.last);
  } catch (_) {
    return 'attachment';
  }
}

String attachmentFileNameFromHeaders(Map<String, String> headers) {
  final entry = headers.entries.where((e) => e.key.toLowerCase() == 'content-disposition');
  if (entry.isEmpty) return 'attachment';
  final contentDisposition = entry.first.value;
  final match = RegExp(r'''filename\*?=(?:UTF-8''|utf-8''|"|')?([^"';]+)''', caseSensitive: false)
      .firstMatch(contentDisposition);
  if (match == null) return 'attachment';
  return sanitizeAttachmentFileName(Uri.decodeComponent(match.group(1) ?? 'attachment'));
}

bool isInlineViewableMimeType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  // Do not open PDFs inside an in-app webview. Many devices render them as a
  // blank white/black page. PDFs should be downloaded and opened via the
  // platform file handler instead.
  if (normalized == 'application/pdf') return false;
  return normalized.startsWith('image/');
}

String _mimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  return '';
}

String _extensionForMime(String mimeType) {
  switch (mimeType.trim().toLowerCase()) {
    case 'application/pdf':
      return '.pdf';
    case 'image/jpeg':
    case 'image/jpg':
      return '.jpg';
    case 'image/png':
      return '.png';
    case 'image/gif':
      return '.gif';
    case 'image/webp':
      return '.webp';
    case 'application/msword':
      return '.doc';
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      return '.docx';
    default:
      return '';
  }
}

String ensureAttachmentExtension(String fileName, String mimeType) {
  final safe = sanitizeAttachmentFileName(fileName);
  if (safe.contains('.') && !safe.endsWith('.')) return safe;
  final ext = _extensionForMime(mimeType);
  if (ext.isEmpty) return safe;
  return '$safe$ext';
}

Map<String, dynamic> _parseRequestedData(dynamic raw) {
  try {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return const <String, dynamic>{};
}

List<MobileAttachmentItem> extractMobileAttachments(
    Map<String, dynamic> payload, {
      required String baseUrl,
      bool includeRequestedData = false,
    }) {
  final structured = <MobileAttachmentItem>[];
  final legacy = <MobileAttachmentItem>[];

  void addOneTo(List<MobileAttachmentItem> out, dynamic item) {
    if (item == null) return;
    if (item is String) {
      final raw = item.trim();
      if (raw.isEmpty) return;
      final name = attachmentFileNameFromUrl(baseUrl, raw);
      out.add(
        MobileAttachmentItem(
          id: '',
          name: name,
          mimeType: _mimeFromName(name),
          size: null,
          viewUrl: raw,
          downloadUrl: raw,
          deleteUrl: '',
          legacyUrl: raw,
        ),
      );
      return;
    }
    if (item is! Map) return;

    final map = Map<String, dynamic>.from(item);
    final providedName = (map['name'] ?? map['file_name'] ?? map['filename'] ?? '').toString().trim();
    final viewUrl = (map['view_url'] ?? '').toString().trim();
    final downloadUrl = (map['download_url'] ?? '').toString().trim();
    final deleteUrl = (map['delete_url'] ?? '').toString().trim();
    final legacyUrl = (map['url'] ?? map['file_url'] ?? map['file'] ?? map['path'] ?? map['link'] ?? '').toString().trim();
    final seedUrl = viewUrl.isNotEmpty ? viewUrl : (downloadUrl.isNotEmpty ? downloadUrl : legacyUrl);
    if (seedUrl.isEmpty) return;

    final derivedName = providedName.isNotEmpty ? providedName : attachmentFileNameFromUrl(baseUrl, seedUrl);
    final mimeType = (map['mime_type'] ?? '').toString().trim().isNotEmpty
        ? (map['mime_type'] ?? '').toString().trim()
        : _mimeFromName(derivedName);
    final sizeValue = int.tryParse((map['size'] ?? '').toString());

    out.add(
      MobileAttachmentItem(
        id: (map['id'] ?? '').toString(),
        name: ensureAttachmentExtension(derivedName, mimeType),
        mimeType: mimeType,
        size: sizeValue,
        viewUrl: viewUrl,
        downloadUrl: downloadUrl,
        deleteUrl: deleteUrl,
        legacyUrl: legacyUrl,
      ),
    );
  }

  void addManyTo(List<MobileAttachmentItem> out, dynamic value) {
    if (value == null) return;
    if (value is List) {
      for (final item in value) {
        addOneTo(out, item);
      }
      return;
    }
    addOneTo(out, value);
  }

  List<MobileAttachmentItem> dedupe(List<MobileAttachmentItem> items) {
    final seen = <String>{};
    final deduped = <MobileAttachmentItem>[];
    for (final item in items) {
      final key = [
        item.id.trim(),
        absoluteAttachmentUrl(baseUrl, item.preferredOpenUrl()),
        absoluteAttachmentUrl(baseUrl, item.deleteUrl),
      ].join('|');
      if (seen.contains(key)) continue;
      seen.add(key);
      deduped.add(item);
    }
    return deduped;
  }

  addManyTo(structured, payload['attachments']);
  addManyTo(structured, payload['current_document_files']);
  addManyTo(structured, payload['attachment']);

  Map<String, dynamic> requestedData = const <String, dynamic>{};
  if (includeRequestedData) {
    requestedData = _parseRequestedData(payload['requested_data']);
    addManyTo(structured, requestedData['attachments']);
    addManyTo(structured, requestedData['attachment']);
  }

  final structuredDeduped = dedupe(structured);
  if (structuredDeduped.isNotEmpty) {
    return structuredDeduped;
  }

  addManyTo(legacy, payload['file_urls']);
  addManyTo(legacy, payload['attachment_urls']);
  addManyTo(legacy, payload['files']);
  addManyTo(legacy, payload['attachment_url']);
  addManyTo(legacy, payload['file_url']);

  if (includeRequestedData) {
    addManyTo(legacy, requestedData['files']);
    addManyTo(legacy, requestedData['file_urls']);
    addManyTo(legacy, requestedData['attachment_urls']);
    addManyTo(legacy, requestedData['attachment_url']);
    addManyTo(legacy, requestedData['file_url']);
  }

  return dedupe(legacy);
}

Future<String?> _mobileAuthToken() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  if (token == null || token.trim().isEmpty) return null;
  return token.trim();
}

Future<bool> _tryLaunchInlineView(String url, {String? token}) async {
  try {
    final headers = <String, String>{};
    final trimmedToken = token?.trim() ?? '';
    if (trimmedToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $trimmedToken';
    }
    return await launch(
      url,
      forceWebView: true,
      enableJavaScript: false,
      enableDomStorage: false,
      headers: headers,
    );
  } catch (_) {
    return false;
  }
}

Future<Directory> _attachmentDirectory() async {
  try {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/attachments');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  } catch (_) {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/attachments');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

Future<void> openMobileAttachment(
    BuildContext context,
    MobileAttachmentItem item, {
      required String baseUrl,
    }) async {
  try {
    final token = await _mobileAuthToken();

    final preferredUrl = absoluteAttachmentUrl(baseUrl, item.preferredOpenUrl());
    if (preferredUrl.trim().isEmpty) {
      throw Exception('Attachment URL is missing');
    }

    if (item.isInlineViewable && item.viewUrl.trim().isNotEmpty) {
      final launched = await _tryLaunchInlineView(
        absoluteAttachmentUrl(baseUrl, item.viewUrl),
        token: token,
      );
      if (launched) return;
    }

    final uri = Uri.parse(preferredUrl);
    final requestHeaders = <String, String>{'Accept': '*/*'};
    final trimmedToken = token?.trim() ?? '';
    if (trimmedToken.isNotEmpty) {
      requestHeaders['Authorization'] = 'Bearer $trimmedToken';
    }
    final response = await http.get(uri, headers: requestHeaders);

    if (response.statusCode != 200) {
      throw Exception('Attachment download failed (${response.statusCode})');
    }

    final headerName = attachmentFileNameFromHeaders(response.headers);
    final responseMime = response.headers.entries
        .where((e) => e.key.toLowerCase() == 'content-type')
        .map((e) => e.value)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
    final resolvedMime = (item.mimeType.trim().isNotEmpty ? item.mimeType : (responseMime ?? '')).trim();
    final baseName = item.name.trim().isNotEmpty
        ? item.name
        : (headerName != 'attachment' ? headerName : attachmentFileNameFromUrl(baseUrl, preferredUrl));
    final fileName = ensureAttachmentExtension(baseName, resolvedMime);

    final dir = await _attachmentDirectory();
    final prefix = item.id.trim().isNotEmpty ? item.id.trim() : DateTime.now().millisecondsSinceEpoch.toString();
    final file = File('${dir.path}/${sanitizeAttachmentFileName(prefix)}_${sanitizeAttachmentFileName(fileName)}');
    await file.writeAsBytes(response.bodyBytes, flush: true);

    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unable to open attachment: $e')),
    );
  }
}
