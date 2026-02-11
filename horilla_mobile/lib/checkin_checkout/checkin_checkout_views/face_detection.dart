import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:horilla/checkin_checkout/checkin_checkout_views/setup_imageface.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'checkin_checkout_form.dart';
import '../controllers/face_detection_controller.dart';

class FaceScanner extends StatefulWidget {
  final Map userDetails;
  final String? attendanceState;
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
  String? _employeeImageBase64;
  bool _isDetectionPaused = false;
  bool _isFetchingImage = false;

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

  Future<void> _initializeApp() async {
    try {
      await _fetchBiometricImage();
      if (_employeeImageBase64 != null && mounted) {
        await _initializeCamera();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Initialization failed: $e')),
        );
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      await _controller.initializeCamera();
      if (!mounted) return;

      setState(() => _isCameraInitialized = true);
      _startRealTimeFaceDetection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera initialization failed: $e')),
        );
      }
    }
  }

  /// Ensures `face_detection_image` exists in SharedPreferences.
  /// - If already cached -> return it
  /// - If not cached -> call GET /api/facedetection/setup/
  ///   - 200 -> read `image`, store to prefs, return it
  ///   - 404 -> user never setup -> return null (caller should show setup dialog)
  ///   - others -> throw exception
  Future<String?> _ensureFaceDetectionImageCached({
    required SharedPreferences prefs,
    required String token,
    required String baseUrl,
  }) async {
    // 1) Use cached value if exists
    final cached = prefs.getString("face_detection_image");
    if (cached != null && cached.trim().isNotEmpty) {
      return cached.trim();
    }

    // 2) Not cached -> ask server
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

        // Normalize path: ensure it starts with "/" when it's not a full URL
        if (!image.startsWith("http://") &&
            !image.startsWith("https://") &&
            !image.startsWith("/")) {
          image = "/$image";
        }

        await prefs.setString("face_detection_image", image);

        // Remove legacy key so old logic never blocks again
        await prefs.remove("imagePath");

        return image;
      } catch (_) {
        // Response is not JSON or unexpected
        return null;
      }
    }

    if (setupRes.statusCode == 404) {
      // Not registered yet
      return null;
    }

    throw Exception("Failed to fetch face setup: ${setupRes.statusCode} ${setupRes.body}");
  }


  Future<void> _fetchBiometricImage() async {
    // Prevent duplicate fetches
    if (_isFetchingImage || !mounted) return;

    setState(() => _isFetchingImage = true);

    IOClient? ioClient;
    try {
      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString("token");
      final typedServerUrl = prefs.getString("typed_url");

      // Basic validation
      if (token == null ||
          token.isEmpty ||
          typedServerUrl == null ||
          typedServerUrl.isEmpty) {
        if (mounted) showImageAlertDialog(context);
        return;
      }

      // Normalize base URL (remove trailing slash)
      final baseUrl = typedServerUrl.endsWith("/")
          ? typedServerUrl.substring(0, typedServerUrl.length - 1)
          : typedServerUrl;

      // ✅ Auto-migration happens here:
      // - If cached exists => use it
      // - If not => GET /api/facedetection/setup/ and cache it
      final faceDetectionImage = await _ensureFaceDetectionImageCached(
        prefs: prefs,
        token: token,
        baseUrl: baseUrl,
      );

      // If still null => user has never set up face image
      if (faceDetectionImage == null || faceDetectionImage.trim().isEmpty) {
        if (mounted) showImageAlertDialog(context);
        return;
      }

      // Build a safe absolute image URL
      final img = faceDetectionImage.trim();
      final String imageUrl;
      if (img.startsWith("http://") || img.startsWith("https://")) {
        imageUrl = img;
      } else if (img.startsWith("/")) {
        imageUrl = "$baseUrl$img"; // base + "/media/..."
      } else {
        imageUrl = "$baseUrl/$img";
      }

      debugPrint("🔎 Fetching biometric image: $imageUrl");

      // Optional: bypass self-signed certificate issues (common in internal servers)
      final httpClient = HttpClient();
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      httpClient.autoUncompress = false;

      ioClient = IOClient(httpClient);

      final res = await ioClient.get(
        Uri.parse(imageUrl),
        headers: {
          // Some servers don't require auth for media, but keeping this is usually safe
          "Authorization": "Bearer $token",
          "Accept": "image/*",
          "Accept-Encoding": "identity",
        },
      );

      if (!mounted) return;

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        setState(() {
          _employeeImageBase64 = base64Encode(res.bodyBytes);
        });
        debugPrint("✅ Biometric image loaded (${res.bodyBytes.length} bytes)");
      } else {
        debugPrint("❌ Failed to fetch biometric image: ${res.statusCode}");
        showImageAlertDialog(context);
      }
    } catch (e) {
      debugPrint("⚠️ Error fetching biometric image: $e");
      if (mounted) showImageAlertDialog(context);
    } finally {
      ioClient?.close();
      if (mounted) setState(() => _isFetchingImage = false);
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
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => CheckInCheckOutFormPage()),
                );
              }
            },
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final cameras = await availableCameras();
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CameraSetupPage(cameras: cameras)),
                );
              }
            },
            child: const Text("Yes"),
          ),
        ],
      ),
    );
  }

  Future<void> _startRealTimeFaceDetection() async {
    while (_isCameraInitialized && !_isDetectionPaused && mounted) {
      try {
        await Future.delayed(const Duration(milliseconds: 500)); // Increased delay

        if (!mounted || !_controller.cameraController.value.isInitialized) break;

        setState(() => _isComparing = true);
        final image = await _controller.captureImage();

        if (image == null || _employeeImageBase64 == null) {
          debugPrint('Image capture failed or no employee image');
          continue;
        }

        debugPrint('Starting face comparison...');
        final isMatched = await _controller.compareFaces(File(image.path), _employeeImageBase64!);
        debugPrint('Face comparison result: $isMatched');

        if (isMatched) {
          await _handleComparisonResult(isMatched, File(image.path));
          break;
        } else {
          setState(() => _isDetectionPaused = true);
          await _showIncorrectFaceAlert();
          setState(() => _isDetectionPaused = false);
        }
      } catch (e) {
        debugPrint('Face detection error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Face detection error. Please try again.')),
          );
        }
      } finally {
        if (mounted) setState(() => _isComparing = false);
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
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => CheckInCheckOutFormPage()),
                );
              }
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleComparisonResult(bool isMatched, File capturedFile) async {
    if (!isMatched || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");
    final geoFencing = prefs.getBool("geo_fencing") ?? false;

    if (token == null || typedServerUrl == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token / Server URL not found. Please login again.')),
      );
      return;
    }

    if (geoFencing && widget.userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location unavailable. Cannot proceed.')),
      );
      return;
    }

    try {
      final endpoint = widget.attendanceState == 'NOT_CHECKED_IN'
          ? 'api/attendance/clock-in/'
          : 'api/attendance/clock-out/';

      final base = typedServerUrl.endsWith('/')
          ? typedServerUrl.substring(0, typedServerUrl.length - 1)
          : typedServerUrl;

      final response = await _submitAttendance(
        endpoint: endpoint,
        capturedFile: capturedFile,
        baseUrl: base,
        token: token,
        geoFencing: geoFencing,
      );

      if (response.statusCode == 200 && mounted) {

        Map<String, dynamic> payload = {};
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            payload = decoded;
          }
        } catch (_) {}

        Navigator.pop(context, {
          if (widget.attendanceState == 'NOT_CHECKED_IN') 'checkedIn': true,
          if (widget.attendanceState == 'CHECKED_IN') 'checkedOut': true,
          // pass-through some useful flags
          'missing_check_in': payload['missing_check_in'] ?? false,
          'attendance_date': payload['attendance_date'],
          'first_check_in': payload['first_check_in'] ?? payload['clock_in'] ?? payload['clock_in_time'],
          'last_check_out': payload['last_check_out'],
          'worked_hours': payload['worked_hours'] ?? payload['duration'],
        });
      } else if (mounted) {
        final errorMessage = getErrorMessage(response.body);

        // If check-in is blocked due to cut-off, allow user to proceed to check-out.
        if (widget.attendanceState == 'NOT_CHECKED_IN' && _isClockInCutoffError(response.body)) {
          await _showCutoffProceedDialog(
            errorMessage: errorMessage,
            capturedFile: capturedFile,
            baseUrl: base,
            token: token,
            geoFencing: geoFencing,
          );
        } else {
          showCheckInFailedDialog(context, errorMessage);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e')),
        );
      }
    }
  }


  bool _isClockInCutoffError(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        final msg = (decoded['error'] ?? decoded['message'] ?? decoded['detail'] ?? '')
            .toString()
            .toLowerCase();
        // Be tolerant to variations:
        // "check in cut off has passed", "check-in cutoff has passed", etc.
        return msg.contains('cut') && msg.contains('off') && msg.contains('check') && msg.contains('in');
      }
    } catch (_) {}
    final lower = responseBody.toLowerCase();
    return lower.contains('cut') && lower.contains('off') && lower.contains('check') && lower.contains('in');
  }

  Future<http.Response> _submitAttendance({
    required String endpoint,
    required File capturedFile,
    required String baseUrl,
    required String token,
    required bool geoFencing,
  }) async {
    final uri = Uri.parse('$baseUrl/$endpoint');

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';

    if (geoFencing && widget.userLocation != null) {
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

  Future<void> _showCutoffProceedDialog({
    required String errorMessage,
    required File capturedFile,
    required String baseUrl,
    required String token,
    required bool geoFencing,
  }) async {
    if (!mounted) return;

    // Prevent the loop from doing anything while dialog is open
    setState(() => _isDetectionPaused = true);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Check-in Cut-off Passed'),
        content: Text(
          '$errorMessage\n\nYou can still record a check-out now (it will be marked as Missing Check-In).',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // close dialog
              if (mounted) Navigator.of(context).pop(); // close scanner
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // close dialog first
              try {
                final outRes = await _submitAttendance(
                  endpoint: 'api/attendance/clock-out/',
                  capturedFile: capturedFile,
                  baseUrl: baseUrl,
                  token: token,
                  geoFencing: geoFencing,
                );

                if (!mounted) return;

                if (outRes.statusCode == 200) {
                  Map<String, dynamic> payload = {};
                  try {
                    final decoded = jsonDecode(outRes.body);
                    if (decoded is Map<String, dynamic>) payload = decoded;
                  } catch (_) {}

                  Navigator.pop(context, {
                    'checkedOut': true,
                    'missing_check_in': payload['missing_check_in'] ?? true,
                    'attendance_date': payload['attendance_date'],
                    'first_check_in': payload['first_check_in'] ??
                        payload['clock_in'] ??
                        payload['clock_in_time'],
                    'last_check_out': payload['last_check_out'],
                    'worked_hours': payload['worked_hours'] ?? payload['duration'],
                  });
                } else {
                  final msg = getErrorMessage(outRes.body);
                  showCheckInFailedDialog(context, msg);
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Network error: $e')),
                );
              }
            },
            child: const Text('Proceed to Check-Out'),
          ),
        ],
      ),
    );

    if (mounted) setState(() => _isDetectionPaused = false);
  }

  String getErrorMessage(String responseBody) {
    try {
      final decoded = json.decode(responseBody);
      if (decoded is Map) {
        final msg = decoded['error'] ?? decoded['message'] ?? decoded['detail'];
        final lastAllowed = decoded['last_allowed'];
        if (msg != null && lastAllowed != null) {
          return '${msg.toString()} (Last allowed: ${lastAllowed.toString()})';
        }
        if (msg != null) return msg.toString();
        if (decoded.isNotEmpty) return decoded.toString();
      }
      return responseBody;
    } catch (e) {
      return 'Error parsing server response';
    }
  }

  void showCheckInFailedDialog(BuildContext context, String errorMessage) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check-in Failed'),
        content: Text(errorMessage),
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
    _isDetectionPaused = true;
    _animationController.dispose();
    _controller.dispose();
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
            if (_isFetchingImage)
              const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
