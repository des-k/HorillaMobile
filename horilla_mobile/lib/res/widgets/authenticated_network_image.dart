import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthenticatedNetworkImage extends StatefulWidget {
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

  @override
  State<AuthenticatedNetworkImage> createState() => _AuthenticatedNetworkImageState();
}

class _AuthenticatedNetworkImageState extends State<AuthenticatedNetworkImage> {
  String? _token;
  bool _loadingToken = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _token = prefs.getString('token')?.trim();
      _loadingToken = false;
    });
  }

  Widget _wrap(Widget child) {
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }

  Widget _placeholder() {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Center(child: widget.placeholder ?? const CircularProgressIndicator()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.trim().isEmpty) {
      return widget.errorWidget ?? const SizedBox.shrink();
    }

    if (_loadingToken) {
      return _wrap(_placeholder());
    }

    final token = _token;
    if (token == null || token.isEmpty) {
      return widget.errorWidget ?? const SizedBox.shrink();
    }

    return _wrap(
      Image.network(
        widget.imageUrl,
        key: ValueKey<String>('${widget.imageUrl}::$token'),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        headers: {'Authorization': 'Bearer $token'},
        errorBuilder: (_, __, ___) => widget.errorWidget ?? const SizedBox.shrink(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _placeholder();
        },
      ),
    );
  }
}
