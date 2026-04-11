import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utilities/private_image_cache.dart';

class AuthenticatedNetworkImage extends StatefulWidget {
  static String? _cachedToken;
  static Future<String?>? _tokenFuture;

  static void primeToken(String? token) {
    final value = token?.trim() ?? '';
    if (value.isEmpty) return;
    _cachedToken = value;
    _tokenFuture = Future<String?>.value(value);
  }

  final String? imageUrl;
  final String? baseUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;
  final Widget? placeholder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final String? authToken;
  final String? cacheKey;
  final String? cacheVersion;
  final int? memCacheWidth;
  final int? memCacheHeight;

  const AuthenticatedNetworkImage({
    super.key,
    required this.imageUrl,
    this.baseUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorWidget,
    this.placeholder,
    this.errorBuilder,
    this.authToken,
    this.cacheKey,
    this.cacheVersion,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  State<AuthenticatedNetworkImage> createState() => _AuthenticatedNetworkImageState();
}

class _ResolvedAuthenticatedImage {
  final File? file;
  final String? url;
  final String? token;

  const _ResolvedAuthenticatedImage({this.file, this.url, this.token});
}

class _AuthenticatedNetworkImageState extends State<AuthenticatedNetworkImage> {
  Future<_ResolvedAuthenticatedImage?>? _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _resolveImage();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.authToken != widget.authToken ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cacheVersion != widget.cacheVersion ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.fit != widget.fit ||
        oldWidget.memCacheWidth != widget.memCacheWidth ||
        oldWidget.memCacheHeight != widget.memCacheHeight) {
      _imageFuture = _resolveImage();
    }
  }

  Future<String?> _loadToken() async {
    if (AuthenticatedNetworkImage._cachedToken != null &&
        AuthenticatedNetworkImage._cachedToken!.isNotEmpty) {
      return AuthenticatedNetworkImage._cachedToken;
    }
    AuthenticatedNetworkImage._tokenFuture ??=
        SharedPreferences.getInstance().then((prefs) {
      final token = prefs.getString('token');
      final normalized = token?.trim() ?? '';
      if (normalized.isNotEmpty) {
        AuthenticatedNetworkImage._cachedToken = normalized;
        return normalized;
      }
      return token;
    });
    return AuthenticatedNetworkImage._tokenFuture!;
  }

  String? _resolveUrl() {
    final raw = widget.imageUrl?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = (widget.baseUrl ?? '').trim();
    if (base.isEmpty) return raw;
    final normalizedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedRaw = raw.startsWith('/') ? raw : '/$raw';
    return '$normalizedBase$normalizedRaw';
  }

  bool get _canUseDiskCache {
    final cacheKey = widget.cacheKey?.trim() ?? '';
    final cacheVersion = widget.cacheVersion?.trim() ?? '';
    return cacheKey.isNotEmpty && cacheVersion.isNotEmpty;
  }

  Future<_ResolvedAuthenticatedImage?> _resolveImage() async {
    final resolvedUrl = _resolveUrl();
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }

    final eagerToken = (widget.authToken?.trim().isNotEmpty ?? false)
        ? widget.authToken!.trim()
        : AuthenticatedNetworkImage._cachedToken;
    final token = eagerToken?.isNotEmpty == true ? eagerToken : await _loadToken();
    final normalizedToken = token?.trim() ?? '';
    if (normalizedToken.isEmpty) {
      return _ResolvedAuthenticatedImage(url: resolvedUrl, token: null);
    }

    AuthenticatedNetworkImage.primeToken(normalizedToken);

    if (_canUseDiskCache) {
      final file = await PrivateImageCacheService.getOrFetch(
        cacheKey: widget.cacheKey!.trim(),
        imageUrl: resolvedUrl,
        version: widget.cacheVersion!.trim(),
        token: normalizedToken,
      );
      if (file != null) {
        return _ResolvedAuthenticatedImage(file: file, url: resolvedUrl, token: normalizedToken);
      }
    }

    return _ResolvedAuthenticatedImage(url: resolvedUrl, token: normalizedToken);
  }

  Widget _wrap(Widget child) {
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }

  Widget _buildNetworkImage(String resolvedUrl, String token) {
    return _wrap(
      Image.network(
        resolvedUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.memCacheWidth,
        cacheHeight: widget.memCacheHeight,
        gaplessPlayback: true,
        headers: <String, String>{'Authorization': 'Bearer $token'},
        errorBuilder: widget.errorBuilder ?? (_, __, ___) => widget.errorWidget ?? const SizedBox.shrink(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Center(child: widget.placeholder ?? const CircularProgressIndicator()),
          );
        },
      ),
    );
  }

  Widget _buildFileImage(File file) {
    return _wrap(
      Image.file(
        file,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.memCacheWidth,
        cacheHeight: widget.memCacheHeight,
        gaplessPlayback: true,
        errorBuilder: widget.errorBuilder ?? (_, __, ___) => widget.errorWidget ?? const SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _resolveUrl();
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return widget.errorWidget ?? const SizedBox.shrink();
    }

    return FutureBuilder<_ResolvedAuthenticatedImage?>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Center(child: widget.placeholder ?? const CircularProgressIndicator()),
          );
        }

        final data = snapshot.data;
        if (data?.file != null) {
          return _buildFileImage(data!.file!);
        }

        final token = data?.token?.trim() ?? '';
        if (token.isEmpty) {
          return widget.errorWidget ?? const SizedBox.shrink();
        }
        return _buildNetworkImage(data?.url ?? resolvedUrl, token);
      },
    );
  }
}
