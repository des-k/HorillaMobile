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

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return errorWidget ?? const SizedBox.shrink();
    }

    return FutureBuilder<String?>(
      future: _loadToken(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        Widget child = Image.network(
          imageUrl,
          width: width,
          height: height,
          fit: fit,
          headers: token == null || token.isEmpty
              ? null
              : {'Authorization': 'Bearer $token'},
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
        if (borderRadius != null) {
          child = ClipRRect(borderRadius: borderRadius!, child: child);
        }
        return child;
      },
    );
  }
}
