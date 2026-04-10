import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthenticatedNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final String? baseUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;
  final Widget? placeholder;
  final ImageErrorWidgetBuilder? errorBuilder;

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
  });

  Future<String?> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
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

        final token = snapshot.data;
        if (token == null || token.isEmpty) {
          return errorWidget ?? const SizedBox.shrink();
        }

        Widget child = Image.network(
          resolvedUrl,
          width: width,
          height: height,
          fit: fit,
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
