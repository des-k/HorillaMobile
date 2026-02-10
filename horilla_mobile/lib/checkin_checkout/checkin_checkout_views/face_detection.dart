import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:horilla/checkin_checkout/checkin_checkout_views/setup_imageface.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

import 'checkin_checkout_form.dart';
import '../controllers/face_detection_controller.dart';

class FaceScanner extends StatefulWidget {
  final Map userDetails;
  final String? attendanceState; // 'NOT_CHECKED_IN' or 'CHECKED_IN'
  final Position? userLocation;

  const FaceScanner({
    Key? key,
    required this.userDetails,
    required this.attendanceState,
    required this.userLocation,
  }) : super(key: key);

  @override
  _FaceScannerState createState() => _FaceScannerState();
}

class _FaceScannerState extends State<FaceScanner> with SingleTickerProviderStateMixin {
  late FaceScannerController _controller;

  bool _isCameraInitialized = false;
  bool _isComparing = false;
  bool _isDetectionPaused = false;
  bool _isFetchingImage = false;

  String? _employeeImageBase64;

  // lifecycle / cancellation
  bool _stopRequested = false;

  late AnimationController _animationController;
  late Animation _rotationAnimation;
  late Animation _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = FaceScannerController();
    _setupAnimations();
    _initializeApp();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _rotationAnimation = Tween(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
    _scaleAnimation = Tween(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _stopRequested) return;
    setState(fn);
  }

  Future<void> _initializeApp() async {
    try {
      await _fetchBiometricImage();
      if (!mounted || _stopRequested) return;

      if (_employeeImageBase64 != null) {
        await _initializeCamera();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Initialization failed: $e')),
      );
    }
  }

  Future<void> _initializeCamera() async {
    try {
      await _controller.initializeCamera();
      if (!mounted || _stopRequested) return;

      _safeSetState(() => _isCameraInitialized = true);
      _startRealTimeFaceDetection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera initialization failed: $e')),
      );
    }
  }

  /// Ensures `face_detection_image` exists in SharedPreferences.
  /// - If already cached -> return it
  /// - If not cached -> call GET /api/facedetection/setup/
  Future<String?> _ensureFaceDetectionImageCached({
    required SharedPreferences prefs,
    required String token,
    required String baseUrl,
  }) async {
    final cached = prefs.getString("face_detection_image");
    if (cached != null && cached.trim().isNotEmpty) {
      return cached.trim();
    }

    final setupUri = Uri.parse("$baseUrl/api/facedetection/setup/");
    final setupRes = await http.get(
      setupUri,
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
      },
    );

    if (setupRes.statusCode >= 200 && setupRes.statusCode < 300) {
      try {
        final data = jsonDecode(setupRes.body);
        var image = (data["image"] ?? "").toString().trim();

        if (image.isEmpty) return null;

        if (!image.startsWith("http://") &&
            !image.startsWith("https://") &&
            !image.startsWith("/")) {
          image = "/$image";
        }

        await prefs.setString("face_detection_image", image);
        await prefs.remove("imagePath"); // remove legacy key
        return image;
      } catch (_) {
        return null;
      }
    }

    if (setupRes.statusCode == 404) {
      return null;
    }

    throw Exception("Failed to fetch face setup: ${setupRes.statusCode} ${setupRes.body}");
  }

  Future<void> _fetchBiometricImage() async {
    if (_isFetchingImage || !mounted || _stopRequested) return;

    _safeSetState(() => _isFetchingImage = true);

    IOClient? ioClient;
    try {
      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString("token");
      final typedServerUrl = prefs.getString("typed_url");

      if (token == null || token.isEmpty || typedServerUrl == null || typedServerUrl.isEmpty) {
        if (mounted) showImageAlertDialog(context);
        return;
      }

      final baseUrl = typedServerUrl.endsWith("/")
          ? typedServerUrl.substring(0, typedServerUrl.length - 1)
          : typedServerUrl;

      final faceDetectionImage = await _ensureFaceDetectionImageCached(
        prefs: prefs,
        token: token,
        baseUrl: baseUrl,
      );

      if (faceDetectionImage == null || faceDetectionImage.trim().isEmpty) {
        if (mounted) showImageAlertDialog(context);
        return;
      }

      final img = faceDetectionImage.trim();
      final String imageUrl;
      if (img.startsWith("http://") || img.startsWith("https://")) {
        imageUrl = img;
      } else if (img.startsWith("/")) {
        imageUrl = "$baseUrl$img";
      } else {
        imageUrl = "$baseUrl/$img";
      }

      debugPrint("🔎 Fetching biometric image: $imageUrl");

      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      httpClient.autoUncompress = false;

      ioClient = IOClient(httpClient);

      final res = await ioClient.get(
        Uri.parse(imageUrl),
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "image/*",
          "Accept-Encoding": "identity",
        },
      );

      if (!mounted || _stopRequested) return;

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        _safeSetState(() {
          _employeeImageBase64 = base64Encode(res.bodyBytes);
        });
        debugPrint("✅ Biometric image loaded (${res.bodyBytes.length} bytes)");
      } else {
        debugPrint("❌ Failed to fetch biometric image: ${res.statusCode}");
        if (mounted) showImageAlertDialog(context);
      }
    } catch (e) {
      debugPrint("⚠️ Error fetching biometric image: $e");
      if (mounted) showImageAlertDialog(context);
    } finally {
      try {
        ioClient?.close();
      } catch (_) {}
      _safeSetState(() => _isFetchingImage = false);
    }
  }

  void showImageAlertDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Employee Image Not Set"),
        content: const Text("Setup a New FaceImage?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => CheckInCheckOutFormPage()),
              );
            },
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final cameras = await availableCameras();
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CameraSetupPage(cameras: cameras)),
              );
            },
            child: const Text("Yes"),
          ),
        ],
      ),
    );
  }

  Future<void> _startRealTimeFaceDetection() async {
    // Run a soft loop with cancellation checks
    while (mounted && !_stopRequested && _isCameraInitialized && !_isDetectionPaused) {
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted || _stopRequested) break;

        if (!_controller.cameraController.value.isInitialized) break;

        _safeSetState(() => _isComparing = true);

        final image = await _controller.captureImage();
        if (!mounted || _stopRequested) break;

        if (image == null || _employeeImageBase64 == null) {
          debugPrint('Image capture failed or no employee image');
          continue;
        }

        debugPrint('Starting face comparison...');
        final isMatched = await _controller.compareFaces(File(image.path), _employeeImageBase64!);
        if (!mounted || _stopRequested) break;

        debugPrint('Face comparison result: $isMatched');

        if (isMatched) {
          await _handleComparisonResult(File(image.path));
          break;
        } else {
          _safeSetState(() => _isDetectionPaused = true);
          await _showIncorrectFaceAlert();
          _safeSetState(() => _isDetectionPaused = false);
        }
      } catch (e) {
        debugPrint('Face detection error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Face detection error. Please try again.')),
          );
        }
      } finally {
        _safeSetState(() => _isComparing = false);
      }
    }
  }

  Future<void> _showIncorrectFaceAlert() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Incorrect Face"),
        content: const Text("The detected face does not match. Please try again."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => CheckInCheckOutFormPage()),
              );
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _tryDecodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _shouldOfferProceedToCheckout({
    required bool wasClockInAttempt,
    required Map<String, dynamic>? data,
    required String rawBody,
  }) {
    if (!wasClockInAttempt) return false;

    // Strong signals from backend
    final suggested = (data?['suggested_action'] ?? '').toString().toLowerCase();
    final canClockOut = data?['can_clock_out'] == true;

    if (suggested == 'clock_out' && canClockOut) return true;

    final code = (data?['code'] ?? '').toString().toUpperCase();
    if (code == 'CHECKIN_CUTOFF_PASSED' && canClockOut) return true;

    // Fallback heuristic for older backends
    final msg = (data?['error'] ?? data?['message'] ?? data?['detail'] ?? rawBody).toString().toLowerCase();
    if (msg.contains('cut') && msg.contains('off') && msg.contains('check in')) {
      // if backend says you can still clock-out OR we assume yes
      return canClockOut || true;
    }

    return false;
  }

  String _composeErrorMessage(String responseBody) {
    final data = _tryDecodeMap(responseBody);
    if (data != null) {
      final msg = data['error'] ?? data['message'] ?? data['detail'];
      final lastAllowed = data['last_allowed'] ?? data['check_in_last_allowed'] ?? data['check_out_last_allowed'];
      if (msg != null && lastAllowed != null) {
        return '${msg.toString()} (Last allowed: ${lastAllowed.toString()})';
      }
      if (msg != null) return msg.toString();
      if (data.isNotEmpty) return data.toString();
    }
    // if not JSON
    return responseBody.isNotEmpty ? responseBody : 'Error parsing server response';
  }

  Future<void> _shutdownCameraSafely() async {
    _stopRequested = true;
    _isDetectionPaused = true;
    _isCameraInitialized = false;

    try {
      if (_controller.cameraController.value.isInitialized) {
        await _controller.cameraController.dispose();
      }
    } catch (_) {}
  }

  Future<http.Response> _postAttendance({
    required String endpoint,
    required String token,
    required String baseUrl,
    required File capturedFile,
    required bool geoFencing,
  }) async {
    final uri = Uri.parse('$baseUrl/$endpoint');

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';

    if (geoFencing) {
      request.fields['latitude'] = widget.userLocation!.latitude.toString();
      request.fields['longitude'] = widget.userLocation!.longitude.toString();
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        capturedFile.path,
        filename: p.basename(capturedFile.path),
      ),
    );

    final streamed = await request.send();
    return http.Response.fromStream(streamed);
  }

  Future<void> _handleComparisonResult(File capturedFile) async {
    if (!mounted || _stopRequested) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");
    final geoFencing = prefs.getBool("geo_fencing") ?? false;

    if (token == null || token.isEmpty || typedServerUrl == null || typedServerUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token / Server URL not found. Please login again.')),
      );
      return;
    }

    if (geoFencing && widget.userLocation == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location unavailable. Cannot proceed.')),
      );
      return;
    }

    final baseUrl = typedServerUrl.endsWith('/')
        ? typedServerUrl.substring(0, typedServerUrl.length - 1)
        : typedServerUrl;

    final bool isClockInAttempt = widget.attendanceState == 'NOT_CHECKED_IN';

    // Decide default endpoint
    final defaultEndpoint = isClockInAttempt
        ? 'api/attendance/clock-in/'
        : 'api/attendance/clock-out/';

    try {
      // 1) Try default action
      final res = await _postAttendance(
        endpoint: defaultEndpoint,
        token: token,
        baseUrl: baseUrl,
        capturedFile: capturedFile,
        geoFencing: geoFencing,
      );

      if (!mounted || _stopRequested) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        Map<String, dynamic> payload = _tryDecodeMap(res.body) ?? {};

        // Close camera cleanly BEFORE leaving this screen (reduces "dead thread" warning)
        await _shutdownCameraSafely();
        if (!mounted) return;

        Navigator.pop(context, {
          if (isClockInAttempt) 'checkedIn': true,
          if (!isClockInAttempt) 'checkedOut': true,
          'missing_check_in': payload['missing_check_in'] ?? false,
          'attendance_date': payload['attendance_date'],
          'first_check_in': payload['first_check_in'] ?? payload['clock_in'] ?? payload['clock_in_time'],
          'last_check_out': payload['last_check_out'],
          'worked_hours': payload['worked_hours'] ?? payload['duration'],
        });
        return;
      }

      // 2) Not success: decide whether to offer "Proceed to Check-Out"
      final data = _tryDecodeMap(res.body);
      final rawBody = res.body;

      final offerProceed = _shouldOfferProceedToCheckout(
        wasClockInAttempt: isClockInAttempt,
        data: data,
        rawBody: rawBody,
      );

      final errorMessage = _composeErrorMessage(res.body);

      if (!mounted) return;

      if (offerProceed) {
        await _showProceedToCheckoutDialog(
          errorMessage: errorMessage,
          onProceed: () async {
            // Try clock-out using same captured image (missing check-in flow)
            final outRes = await _postAttendance(
              endpoint: 'api/attendance/clock-out/',
              token: token,
              baseUrl: baseUrl,
              capturedFile: capturedFile,
              geoFencing: geoFencing,
            );

            if (!mounted || _stopRequested) return;

            if (outRes.statusCode >= 200 && outRes.statusCode < 300) {
              final outPayload = _tryDecodeMap(outRes.body) ?? {};

              await _shutdownCameraSafely();
              if (!mounted) return;

              Navigator.pop(context, {
                'checkedOut': true,
                'missing_check_in': true, // force missing check-in display
                'attendance_date': outPayload['attendance_date'],
                'first_check_in': outPayload['first_check_in'] ?? '-',
                'last_check_out': outPayload['last_check_out'],
                'worked_hours': outPayload['worked_hours'] ?? outPayload['duration'],
              });
              return;
            }

            // Clock-out also failed
            final outErr = _composeErrorMessage(outRes.body);
            if (!mounted) return;
            _showSimpleFailedDialog(title: 'Check-out Failed', message: outErr);
          },
        );
      } else {
        _showSimpleFailedDialog(title: 'Check-in Failed', message: errorMessage);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e')),
      );
    }
  }

  Future<void> _showProceedToCheckoutDialog({
    required String errorMessage,
    required Future<void> Function() onProceed,
  }) async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check-in Failed'),
        content: Text(
          '$errorMessage\n\nYou can still check-out (Missing Check-In). Proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // close FaceScanner screen
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onProceed();
            },
            child: const Text('Proceed to Check-Out'),
          ),
        ],
      ),
    );
  }

  void _showSimpleFailedDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopRequested = true;
    _isDetectionPaused = true;

    try {
      _animationController.stop();
      _animationController.dispose();
    } catch (_) {}

    try {
      if (_controller.cameraController.value.isInitialized) {
        _controller.cameraController.dispose();
      }
    } catch (_) {}

    super.dispose();
  }

  Widget _buildImageContainer(double screenHeight, double screenWidth) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _isComparing ? _scaleAnimation.value : 1.0,
              child: Container(
                height: screenHeight * 0.4,
                width: screenWidth * 0.7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _isCameraInitialized && _controller.cameraController.value.isInitialized
                      ? CameraPreview(_controller.cameraController)
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
            );
          },
        ),
        if (_isComparing)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotationAnimation.value,
                        child: const Icon(Icons.face_retouching_natural, color: Colors.white, size: 50),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Detecting Faces...',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Face Detection'),
        backgroundColor: Colors.red,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          children: [
            SizedBox(height: screenHeight * 0.1),
            _buildImageContainer(screenHeight, screenWidth),
            SizedBox(height: screenHeight * 0.05),
            if (_isFetchingImage) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
