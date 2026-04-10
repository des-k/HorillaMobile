import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthenticatedNetworkImage extends StatelessWidget {
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
  });

  Future<String?> _loadToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }
    _tokenFuture ??= SharedPreferences.getInstance().then((prefs) {
      final token = prefs.getString('token');
      final normalized = token?.trim() ?? '';
      if (normalized.isNotEmpty) {
        _cachedToken = normalized;
        return normalized;
      }
      return token;
    });
    return _tokenFuture!;
  }

  String? _resolveUrl() {
    final raw = imageUrl?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = (baseUrl ?? '').trim();
    if (base.isEmpty) return raw;
    final normalizedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedRaw = raw.startsWith('/') ? raw : '/$raw';
    return '$normalizedBase$normalizedRaw';
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _resolveUrl();
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return errorWidget ?? const SizedBox.shrink();
    }

    final eagerToken = (authToken?.trim().isNotEmpty ?? false) ? authToken!.trim() : _cachedToken;
    if (eagerToken != null && eagerToken.isNotEmpty) {
      primeToken(eagerToken);
      Widget child = Image.network(
        resolvedUrl,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        headers: {'Authorization': 'Bearer $eagerToken'},
        errorBuilder: errorBuilder ?? (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
        loadingBuilder: (context, widget, progress) {
          if (progress == null) return widget;
          return SizedBox(
            width: width,
            height: height,
            child: Center(child: placeholder ?? const CircularProgressIndicator()),
          );
        },
      );
      if (borderRadius != null) {
        child = ClipRRect(borderRadius: borderRadius!, child: child);
      }
      return child;
    }

    return FutureBuilder<String?>(
      future: _loadToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width,
            height: height,
            child: Center(child: placeholder ?? const CircularProgressIndicator()),
          );
        }

        final token = snapshot.data?.trim();
        if (token == null || token.isEmpty) {
          return errorWidget ?? const SizedBox.shrink();
        }
        primeToken(token);

        Widget child = Image.network(
          resolvedUrl,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          headers: {'Authorization': 'Bearer $token'},
          errorBuilder: errorBuilder ?? (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
          loadingBuilder: (context, widget, progress) {
            if (progress == null) return widget;
            return SizedBox(
              width: width,
              height: height,
              child: Center(child: placeholder ?? const CircularProgressIndicator()),
            );
          },
        );
        if (borderRadius != null) {
          child = ClipRRect(borderRadius: borderRadius!, child: child);
        }
        return child;
      },
    );
  }
}
