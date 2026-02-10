import 'dart:async';
import 'dart:convert';

import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' as appSettings;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import 'face_detection.dart';
import 'stopwatch.dart';

class CheckInCheckOutFormPage extends StatefulWidget {
  const CheckInCheckOutFormPage({super.key});

  @override
  _CheckInCheckOutFormPageState createState() => _CheckInCheckOutFormPageState();
}

class _CheckInCheckOutFormPageState extends State<CheckInCheckOutFormPage> {
  // UI state
  bool isLoading = true;
  bool _isProcessingDrag = false;
  bool _locationSnackBarShown = false;
  bool _locationUnavailableSnackBarShown = false;

  // API / user
  late String baseUrl = '';
  late String getToken = '';
  Map<String, dynamic> arguments = {};

  // Employee card
  late String requestsEmpMyFirstName = '';
  late String requestsEmpMyLastName = '';
  late String requestsEmpMyBadgeId = '';
  late String requestsEmpMyDepartment = '';
  late String requestsEmpProfile = '';
  late String requestsEmpMyWorkInfoId = '';
  late String requestsEmpMyShiftName = '';

  // Attendance status (single-session)
  bool hasAttendance = false; // attendance record exists for resolved attendance_date
  bool hasCheckedIn = false; // first check-in exists
  bool isCurrentlyCheckedIn = false; // checked-in but not checked-out
  bool missingCheckIn = false; // checked-out exists but check-in missing

  String attendanceDate = ''; // yyyy-mm-dd (resolved)
  String? firstCheckIn;
  String? lastCheckOut;
  String workedHours = '00:00:00';

  // Location
  Position? userLocation;

  // Timer
  final StopwatchManager stopwatchManager = StopwatchManager();

  // Bottom nav
  final _controller = NotchBottomBarController(index: 1);

  String get swipeDirection => canCheckIn ? 'Swipe to Check-In' : 'Swipe to Check-out';
  bool get canCheckIn => !hasAttendance;
  bool get canCheckOut => hasAttendance; // allow updating last checkout multiple times

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      await fetchToken();

      // Initialize feature flags
      final faceDetectionEnabled = await getFaceDetection();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('face_detection', faceDetectionEnabled);

      await _initializeLocation();

      await Future.wait<void>([
        getBaseUrl(),
        prefetchData(),
        getLoginEmployeeRecord(),
        refreshAttendanceStatus(),
      ]);

      if (!mounted) return;
      setState(() => isLoading = false);
    } catch (e) {
      debugPrint('Error initializing data: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize data: $e')),
      );
    }
  }

  Future<void> fetchToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    setState(() => getToken = token ?? '');
  }

  Future<void> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final typedServerUrl = prefs.getString('typed_url');
    setState(() => baseUrl = (typedServerUrl ?? '').trim());
  }

  Future<void> prefetchData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');
    final employeeId = prefs.getInt('employee_id');

    if (token == null || typedServerUrl == null || employeeId == null) return;

    final uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      arguments = {
        'employee_id': responseData['id'],
        'employee_name': '${responseData['employee_first_name']} ${responseData['employee_last_name']}',
        'badge_id': responseData['badge_id'],
        'email': responseData['email'],
        'phone': responseData['phone'],
        'date_of_birth': responseData['dob'],
        'gender': responseData['gender'],
        'address': responseData['address'],
        'country': responseData['country'],
        'state': responseData['state'],
        'city': responseData['city'],
        'qualification': responseData['qualification'],
        'experience': responseData['experience'],
        'marital_status': responseData['marital_status'],
        'children': responseData['children'],
        'emergency_contact': responseData['emergency_contact'],
        'emergency_contact_name': responseData['emergency_contact_name'],
        'employee_work_info_id': responseData['employee_work_info_id'],
        'employee_bank_details_id': responseData['employee_bank_details_id'],
        'employee_profile': responseData['employee_profile'],
      };
    }
  }

  Future<void> getLoginEmployeeRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');
    final employeeId = prefs.getInt('employee_id');

    if (token == null || typedServerUrl == null || employeeId == null) return;

    final uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      setState(() {
        requestsEmpMyFirstName = responseBody['employee_first_name'] ?? '';
        requestsEmpMyLastName = responseBody['employee_last_name'] ?? '';
        requestsEmpMyBadgeId = responseBody['badge_id'] ?? '';
        requestsEmpMyDepartment = responseBody['department_name'] ?? '';
        requestsEmpProfile = responseBody['employee_profile'] ?? '';
        requestsEmpMyWorkInfoId = (responseBody['employee_work_info_id'] ?? '').toString();
      });

      if (requestsEmpMyWorkInfoId.isNotEmpty) {
        await getLoginEmployeeWorkInfoRecord(requestsEmpMyWorkInfoId);
      }
    }
  }

  Future<void> getLoginEmployeeWorkInfoRecord(String workInfoId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    if (token == null || typedServerUrl == null) return;

    final uri = Uri.parse('$typedServerUrl/api/employee/employee-work-information/$workInfoId');
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      setState(() {
        requestsEmpMyShiftName = (responseBody['shift_name'] ?? 'None').toString();
      });
    }
  }

  Future<void> _initializeLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final geoFencing = prefs.getBool('geo_fencing') ?? false;
    if (!geoFencing) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!_locationSnackBarShown && mounted) {
          _locationSnackBarShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location services are disabled. Please enable them.'),
              action: SnackBarAction(
                label: 'Enable',
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permissions are permanently denied.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => appSettings.openAppSettings(),
            ),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => userLocation = position);
    } catch (e) {
      debugPrint('Error fetching location: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location: $e')),
      );
    }
  }

  Future<bool> getFaceDetection() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    if (token == null || typedServerUrl == null) return false;

    final uri = Uri.parse('$typedServerUrl/api/facedetection/config/');
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['start'] ?? false) == true;
    }

    return false;
  }

  Future<void> refreshAttendanceStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    if (token == null || typedServerUrl == null) return;

    final uri = Uri.parse('$typedServerUrl/api/attendance/checking-in');
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode != 200) {
      debugPrint('Failed to fetch attendance status: ${response.statusCode} ${response.body}');
      return;
    }

    final data = jsonDecode(response.body);

    final bool statusFlag = (data['status'] ?? false) == true;
    final bool hasAttendanceFlag = (data['has_attendance'] ?? false) == true;

    final String? first = (data['first_check_in'] ?? data['clock_in'] ?? data['clock_in_time'])?.toString();
    final String? last = (data['last_check_out'])?.toString();

    final String hours = (data['worked_hours'] ?? data['duration'] ?? '00:00:00').toString();
    final String attDate = (data['attendance_date'] ?? '').toString();

    final bool missingIn = (data['missing_check_in'] ?? false) == true;
    final bool hasIn = (data['has_checked_in'] ?? ((first ?? '').trim().isNotEmpty)) == true;

    setState(() {
      isCurrentlyCheckedIn = statusFlag;
      hasAttendance = hasAttendanceFlag || ((first ?? '').trim().isNotEmpty) || ((last ?? '').trim().isNotEmpty);
      hasCheckedIn = hasIn;
      missingCheckIn = missingIn;
      attendanceDate = attDate;
      firstCheckIn = (first != null && first.trim().isNotEmpty) ? first : null;
      lastCheckOut = (last != null && last.trim().isNotEmpty && last.trim().toLowerCase() != 'null') ? last : null;
      workedHours = hours;
    });

    // Sync stopwatch
    final initial = _parseDuration(workedHours);
    if (isCurrentlyCheckedIn) {
      stopwatchManager.resetStopwatch();
      stopwatchManager.startStopwatch(initialTime: initial);
    } else {
      stopwatchManager.resetStopwatch();
    }
  }

  Duration _parseDuration(String durationString) {
    try {
      final raw = durationString.trim();
      if (raw.isEmpty) return Duration.zero;
      final parts = raw.split(':');
      if (parts.length < 2) return Duration.zero;
      final int hours = int.tryParse(parts[0]) ?? 0;
      final int minutes = int.tryParse(parts[1]) ?? 0;
      int seconds = 0;
      if (parts.length >= 3) {
        seconds = int.tryParse(parts[2].split('.').first) ?? 0;
      }
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    } catch (_) {
      return Duration.zero;
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  String _extractErrorMessage(String responseBody) {
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
    } catch (_) {
      return responseBody;
    }
  }

  void showActionFailedDialog(BuildContext context, String title, String errorMessage) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(errorMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _postClock({required bool isClockIn}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');
    final geoFencing = prefs.getBool('geo_fencing') ?? false;

    if (token == null || typedServerUrl == null) return null;

    final endpoint = isClockIn ? '/api/attendance/clock-in/' : '/api/attendance/clock-out/';
    final uri = Uri.parse('$typedServerUrl$endpoint');

    Map<String, dynamic> body = {};
    if (geoFencing) {
      if (userLocation == null) {
        if (!_locationUnavailableSnackBarShown && mounted) {
          _locationUnavailableSnackBarShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location unavailable. Cannot proceed.')),
          );
        }
        return null;
      }
      body = {
        'latitude': userLocation!.latitude,
        'longitude': userLocation!.longitude,
      };
    }

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return {};
      }
    }

    if (!mounted) return null;
    showActionFailedDialog(context, isClockIn ? 'Check-in Failed' : 'Check-out Failed', _extractErrorMessage(response.body));
    return null;
  }

  Future<void> _doClockIn() async {
    if (!canCheckIn) return;

    final prefs = await SharedPreferences.getInstance();
    final faceDetection = prefs.getBool('face_detection') ?? false;

    if (faceDetection) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FaceScanner(
            userLocation: userLocation,
            userDetails: arguments,
            attendanceState: 'NOT_CHECKED_IN',
          ),
        ),
      );

      if (result != null && result['checkedIn'] == true) {
        await refreshAttendanceStatus();
      }
      return;
    }

    final res = await _postClock(isClockIn: true);
    if (res != null) {
      await refreshAttendanceStatus();
    }
  }

  Future<void> _doClockOut() async {
    if (!canCheckOut) return;

    final prefs = await SharedPreferences.getInstance();
    final faceDetection = prefs.getBool('face_detection') ?? false;

    if (faceDetection) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FaceScanner(
            userLocation: userLocation,
            userDetails: arguments,
            attendanceState: 'CHECKED_IN',
          ),
        ),
      );

      if (result != null && result['checkedOut'] == true) {
        final bool missing = (result['missing_check_in'] ?? false) == true;
        await refreshAttendanceStatus();
        if (missing && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Check-out recorded but check-in is missing. Please submit an attendance request.')),
          );
        }
      }
      return;
    }

    final res = await _postClock(isClockIn: false);
    if (res != null) {
      final bool missing = (res['missing_check_in'] ?? false) == true;
      await refreshAttendanceStatus();
      if (missing && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-out recorded but check-in is missing. Please submit an attendance request.')),
        );
      }
    }
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Widget _buildLoadingWidget() {
    return ListView(
      children: [
        Container(
          color: Colors.red,
          height: MediaQuery.of(context).size.height * 0.25,
          child: const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Attendance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                Text('00:00:00', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerStat({required String label, required Widget value}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            value,
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    DateTime? parsedDate;
    if (attendanceDate.trim().isNotEmpty) {
      try {
        parsedDate = DateTime.parse(attendanceDate);
      } catch (_) {}
    }

    final dateLabel = DateFormat('EEE, d MMM yyyy').format(parsedDate ?? DateTime.now());
    final checkInText = firstCheckIn ?? '--:--';
    final checkOutText = lastCheckOut ?? '--:--';

    return Container(
      color: Colors.red,
      height: MediaQuery.of(context).size.height * 0.25,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Attendance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                Text(dateLabel, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _headerStat(
                  label: 'First Check-In',
                  value: Text(checkInText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                _headerStat(
                  label: 'Last Check-Out',
                  value: Text(checkOutText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                _headerStat(
                  label: 'Work Hours',
                  value: isCurrentlyCheckedIn
                      ? StreamBuilder<int>(
                          stream: Stream.periodic(const Duration(seconds: 1), (_) => stopwatchManager.elapsed.inSeconds),
                          builder: (context, snapshot) {
                            final d = stopwatchManager.elapsed;
                            return Text(
                              _formatDuration(d),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            );
                          },
                        )
                      : Text(
                          workedHours,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (missingCheckIn)
              const Text(
                'Missing check-in detected. Please submit an attendance request to fix it.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            if (!missingCheckIn && !hasAttendance)
              const Text(
                'No attendance record yet for today.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 0.0),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade50.withOpacity(0.3),
              spreadRadius: 7,
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        width: MediaQuery.of(context).size.width * 0.50,
        child: Card(
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Colors.white, width: 0.0),
            borderRadius: BorderRadius.circular(10.0),
          ),
          color: Colors.white,
          elevation: 0.1,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 40.0,
                      height: 40.0,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey, width: 1.0),
                      ),
                      child: Stack(
                        children: [
                          if (requestsEmpProfile.isNotEmpty)
                            Positioned.fill(
                              child: ClipOval(
                                child: Image.network(
                                  baseUrl + requestsEmpProfile,
                                  headers: {
                                    'Authorization': 'Bearer $getToken',
                                  },
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, exception, stackTrace) => const Icon(Icons.person, color: Colors.grey),
                                ),
                              ),
                            ),
                          if (requestsEmpProfile.isEmpty)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[400]),
                                child: const Icon(Icons.person),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.01),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$requestsEmpMyFirstName $requestsEmpMyLastName',
                            style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(requestsEmpMyBadgeId, style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.normal)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Department'),
                      Flexible(child: Text(requestsEmpMyDepartment, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('First Check-In'),
                      Text(firstCheckIn ?? '--:--'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Last Check-Out'),
                      Text(lastCheckOut ?? '--:--'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Shift'),
                      Flexible(child: Text(requestsEmpMyShiftName, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeAction() {
    return GestureDetector(
      onPanUpdate: (details) async {
        if (_isProcessingDrag) return;
        if (details.delta.dx.abs() <= details.delta.dy.abs() || details.delta.dx.abs() <= 10) return;

        _isProcessingDrag = true;

        if (details.delta.dx > 0) {
          // Swipe right => check-in
          await _doClockIn();
        } else {
          // Swipe left => check-out
          await _doClockOut();
        }
      },
      onPanEnd: (_) {
        _isProcessingDrag = false;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.07,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.0),
            color: canCheckIn ? Colors.green : Colors.red,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (canCheckIn)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.12,
                    height: MediaQuery.of(context).size.height * 0.06,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10.0), color: Colors.white),
                    child: const Icon(Icons.arrow_forward, color: Colors.green, size: 30.0),
                  ),
                ),
              Expanded(
                child: Center(
                  child: Text(
                    swipeDirection,
                    style: const TextStyle(color: Colors.white, fontSize: 15.0, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (!canCheckIn)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.12,
                    height: MediaQuery.of(context).size.height * 0.06,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10.0), color: Colors.white),
                    child: const Icon(Icons.arrow_back, color: Colors.red, size: 30.0),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInCheckoutWidget() {
    return ListView(
      children: [
        _buildHeader(),
        SizedBox(height: MediaQuery.of(context).size.height * 0.02),
        _buildEmployeeCard(),
        SizedBox(height: MediaQuery.of(context).size.height * 0.02),
        _buildSwipeAction(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await clearToken();
              stopwatchManager.resetStopwatch();
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: isLoading ? _buildLoadingWidget() : _buildCheckInCheckoutWidget(),
      bottomNavigationBar: AnimatedNotchBottomBar(
        notchBottomBarController: _controller,
        color: Colors.red,
        showLabel: true,
        notchColor: Colors.red,
        kBottomRadius: 28.0,
        kIconSize: 24.0,
        removeMargins: false,
        bottomBarWidth: MediaQuery.of(context).size.width,
        durationInMilliSeconds: 500,
        bottomBarItems: const [
          BottomBarItem(
            inActiveItem: Icon(Icons.home_filled, color: Colors.white),
            activeItem: Icon(Icons.home_filled, color: Colors.white),
          ),
          BottomBarItem(
            inActiveItem: Icon(Icons.update_outlined, color: Colors.white),
            activeItem: Icon(Icons.update_outlined, color: Colors.white),
          ),
          BottomBarItem(
            inActiveItem: Icon(Icons.person, color: Colors.white),
            activeItem: Icon(Icons.person, color: Colors.white),
          ),
        ],
        onTap: (index) async {
          switch (index) {
            case 0:
              Future.delayed(const Duration(milliseconds: 300), () {
                Navigator.pushNamed(context, '/home');
              });
              break;
            case 1:
              Future.delayed(const Duration(milliseconds: 300), () {
                Navigator.pushNamed(context, '/employee_checkin_checkout');
              });
              break;
            case 2:
              Future.delayed(const Duration(milliseconds: 300), () {
                Navigator.pushNamed(context, '/employees_form', arguments: arguments);
              });
              break;
          }
        },
      ),
    );
  }
}

class Home extends StatelessWidget {
  const Home({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pushNamed(context, '/home'));
    return Container(color: Colors.white, child: const Center(child: Text('Page 1')));
  }
}

class Overview extends StatelessWidget {
  const Overview({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.white, child: const Center(child: Text('Page 2')));
  }
}

class User extends StatelessWidget {
  const User({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pushNamed(context, '/user'));
    return Container(color: Colors.white, child: const Center(child: Text('Page 1')));
  }
}
