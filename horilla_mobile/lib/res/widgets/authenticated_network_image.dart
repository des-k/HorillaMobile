import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthenticatedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;
  final Widget? placeholder;

  const AuthenticatedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorWidget,
    this.placeholder,
  });

  Future<String?> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Widget _wrap(Widget child) {
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return errorWidget ?? const SizedBox.shrink();
    }

    return FutureBuilder<String?>(
      future: _loadToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _wrap(
            SizedBox(
              width: width,
              height: height,
              child: Center(
                child: placeholder ?? const CircularProgressIndicator(),
              ),
            ),
          );
        }

        final token = snapshot.data;
        final headers = token == null || token.isEmpty
            ? null
            : {'Authorization': 'Bearer $token'};
        final child = Image.network(
          imageUrl,
          key: ValueKey<String>('${imageUrl}|${token ?? ''}'),
          width: width,
          height: height,
          fit: fit,
          headers: headers,
          errorBuilder: (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
          loadingBuilder: (context, widget, progress) {
            if (progress == null) return widget;
            return SizedBox(
              width: width,
              height: height,
              child: Center(child: placeholder ?? const CircularProgressIndicator()),
            );
          },
        );
        return _wrap(child);
      },
    );
  }
}
