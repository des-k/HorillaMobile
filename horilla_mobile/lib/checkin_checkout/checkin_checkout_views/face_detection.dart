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

  Future<void> _fetchBiometricImage() async {
    if (_isFetchingImage) return;
    setState(() => _isFetchingImage = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");
    final faceDetectionImage = prefs.getString("face_detection_image");
    final imagePath = prefs.getString("imagePath");

    if (token == null || typedServerUrl == null || faceDetectionImage == '' || imagePath == null) {
      if (mounted) showImageAlertDialog(context);
      return;
    }

    try {
      // --- Build image URL ---
      String? imageUrl;
      final cleanedServerUrl = typedServerUrl.endsWith('/')
          ? typedServerUrl.substring(0, typedServerUrl.length - 1)
          : typedServerUrl;

      if (faceDetectionImage != null) {
        final cleanedPath = faceDetectionImage.startsWith('/')
            ? faceDetectionImage.substring(1)
            : faceDetectionImage;
        imageUrl = '$cleanedServerUrl/$cleanedPath';
      } else if (imagePath != null) {
        final cleanedPath = imagePath.startsWith('/')
            ? imagePath.substring(1)
            : imagePath;
        imageUrl = '$cleanedServerUrl/media/$cleanedPath';
      }

      if (imageUrl == null) {
        if (mounted) showImageAlertDialog(context);
        return;
      }

      debugPrint("🔎 Fetching biometric image: $imageUrl");

      // --- Correct usage of HttpClient + IOClient ---
      final httpClient = HttpClient();
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      httpClient.autoUncompress = false;

      final ioClient = IOClient(httpClient);

      final response = await ioClient.get(
        Uri.parse(imageUrl),
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "image/*",
          "Accept-Encoding": "identity",
          "User-Agent": "FlutterApp/1.0",
          "Connection": "keep-alive",
        },
      );

      print('cfcfccf');

      debugPrint("📥 Status: ${response.statusCode}");
      debugPrint("📥 Headers: ${response.headers}");

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        setState(() {
          _employeeImageBase64 = base64Encode(response.bodyBytes);
        });
        debugPrint("✅ Image downloaded: ${response.bodyBytes.length} bytes");
      } else {
        debugPrint("❌ Invalid response or empty image data");
        if (mounted) showImageAlertDialog(context);
      }

      ioClient.close();
    } catch (e) {
      debugPrint("⚠️ Error fetching biometric image: $e");
      if (mounted) showImageAlertDialog(context);
    } finally {
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
            onPressed: () => Navigator.of(ctx).pop(),
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

      final uri = Uri.parse('$base/$endpoint');

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
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200 && mounted) {
        Navigator.pop(context, {
          if (widget.attendanceState == 'NOT_CHECKED_IN') 'checkedIn': true,
          if (widget.attendanceState == 'CHECKED_IN') 'checkedOut': true,
        });
      } else if (mounted) {
        final errorMessage = getErrorMessage(response.body);
        showCheckInFailedDialog(context, errorMessage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e')),
        );
      }
    }
  }

  String getErrorMessage(String responseBody) {
    try {
      final Map decoded = json.decode(responseBody);
      return decoded['message'] ?? 'Unknown error occurred';
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
    _animationController.dispose();
    _isDetectionPaused = true;
    if (_controller.cameraController.value.isInitialized) {
      _controller.cameraController.dispose();
    }
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
