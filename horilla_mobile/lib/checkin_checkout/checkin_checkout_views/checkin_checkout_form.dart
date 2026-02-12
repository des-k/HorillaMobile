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

  // Server-driven action flags (from /api/attendance/checking-in)
  bool serverCanClockIn = false;
  bool serverCanClockOut = false;
  bool checkInCutoffPassed = false;

  String attendanceDate = ''; // yyyy-mm-dd (resolved)
  String? firstCheckIn;
  String? lastCheckOut;
  String workedHours = '00:00:00';

  // Optional status helpers from backend (safe defaults if missing)
  String? minimumWorkingHour;
  bool workHoursBelowMinimum = false;
  String? workHoursShortfall;
  bool checkedOutEarly = false;
  String? checkInImage;
  String? checkOutImage;

  // Location
  Position? userLocation;

  // Server time (display only)
  // The app doesn't poll the server every second; instead it keeps an offset computed from
  // `server_now` + RTT/2 so the displayed server time keeps running smoothly.
  Duration _serverOffset = Duration.zero;
  bool _hasServerTime = false;
  int _lastRttMs = 0;

  // Bottom nav
  final _controller = NotchBottomBarController(index: 1);

  String get swipeDirection {
    if (canCheckIn) return 'Swipe ➜ CHECK IN';
    if (canCheckOut) {
      return (lastCheckOut != null)
          ? 'Swipe ⇦ UPDATE CHECK OUT'
          : 'Swipe ⇦ CHECK OUT';
    }
    return 'Attendance action not available';
  }

  /// Can the user clock-in now?
  /// Prefer server flags, fallback to legacy behavior.
  bool get canCheckIn =>
      serverCanClockIn || (!hasAttendance && !checkInCutoffPassed);

  /// Can the user clock-out now?
  /// In single-session mode: allow multiple check-outs (update last check-out).
  /// Also allow check-out when check-in cut-off has passed (missing check-in scenario).
  bool get canCheckOut =>
      serverCanClockOut || (hasAttendance || missingCheckIn || checkInCutoffPassed);

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

    // Measure round-trip time (RTT) so we can compensate for network delay
    // when displaying server time.
    final t0 = DateTime.now();
    final uri = Uri.parse('$typedServerUrl/api/attendance/checking-in');
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });
    final t1 = DateTime.now();
    final rttMs = t1.difference(t0).inMilliseconds;

    if (response.statusCode != 200) {
      debugPrint('Failed to fetch attendance status: ${response.statusCode} ${response.body}');
      return;
    }

    final data = jsonDecode(response.body);

    // Optional: server time (ISO datetime). Used for a live, minute-ticking display.
    // We estimate server time *at the moment the response is received* by adding RTT/2.
    bool hasServerTime = false;
    Duration computedOffset = _serverOffset;
    final serverNowRaw = data['server_now']?.toString();
    if (serverNowRaw != null && serverNowRaw.trim().isNotEmpty) {
      try {
        final serverNow = DateTime.parse(serverNowRaw).toLocal();
        final serverAtReceive = serverNow.add(Duration(milliseconds: (rttMs / 2).round()));
        computedOffset = serverAtReceive.difference(t1);
        hasServerTime = true;
      } catch (_) {
        hasServerTime = false;
      }
    }

    final bool statusFlag = (data['status'] ?? false) == true;
    final bool hasAttendanceFlag = (data['has_attendance'] ?? false) == true;

    // Optional newer API fields (server-driven)
    final bool cutoffPassed = (data['check_in_cutoff_passed'] ??
        data['check_in_cutoff_has_passed'] ??
        false) ==
        true;

    final String suggestedAction =
    (data['suggested_action'] ?? data['action'] ?? '').toString().toLowerCase();

    final bool canInFromApi =
        (data['can_clock_in'] ?? data['can_check_in'] ?? false) == true;
    final bool canOutFromApi =
        (data['can_clock_out'] ?? data['can_check_out'] ?? false) == true;

    final String? first =
    (data['first_check_in'] ?? data['clock_in'] ?? data['clock_in_time'])
        ?.toString();
    final String? last = (data['last_check_out'])?.toString();

    final String hours =
    (data['worked_hours'] ?? data['duration'] ?? '00:00:00').toString();

// Optional hints (may not exist depending on backend)
    final String? minWorkRaw = (data['minimum_working_hour'] ??
        data['minimum_work_hours'] ??
        data['min_working_hour'])
        ?.toString();

    final String? shortfallRaw = (data['work_hours_shortfall'] ??
        data['work_hours_remaining'] ??
        data['shortfall'])
        ?.toString();

    final bool belowMin = (data['work_hours_below_minimum'] ??
        data['below_minimum_work_hours'] ??
        false) ==
        true;

    final bool earlyOut = (data['checked_out_early'] ??
        data['early_check_out'] ??
        false) ==
        true;

    final String? inImgRaw = (data['check_in_image'] ??
        data['clock_in_image'] ??
        data['attendance_clock_in_image'])
        ?.toString();
    final String? outImgRaw = (data['check_out_image'] ??
        data['clock_out_image'] ??
        data['attendance_clock_out_image'])
        ?.toString();

    final String attDate = (data['attendance_date'] ?? '').toString();

    final bool hasIn =
        (data['has_checked_in'] ?? ((first ?? '').trim().isNotEmpty)) == true;

    // Missing check-in can be explicitly returned by API, OR inferred when cut-off
    // has passed and there's no check-in yet.
    final bool missingIn = (data['missing_check_in'] ?? false) == true ||
        (cutoffPassed && !hasIn);

    // Decide which actions should be enabled:
    // - Prefer explicit API flags when present
    // - If suggested_action says clock_out, allow clock-out even when no attendance exists yet.
    final bool canClockIn =
    (data.containsKey('can_clock_in') || data.containsKey('can_check_in'))
        ? canInFromApi
        : (!hasAttendanceFlag && !cutoffPassed);

    bool canClockOut =
    (data.containsKey('can_clock_out') || data.containsKey('can_check_out'))
        ? canOutFromApi
        : (hasAttendanceFlag || cutoffPassed || missingIn);

    if (suggestedAction == 'clock_out') {
      canClockOut = true;
    }

    setState(() {
      isCurrentlyCheckedIn = statusFlag;

      checkInCutoffPassed = cutoffPassed;
      serverCanClockIn = canClockIn;
      serverCanClockOut = canClockOut;

      hasAttendance = hasAttendanceFlag ||
          ((first ?? '').trim().isNotEmpty) ||
          ((last ?? '').trim().isNotEmpty);

      hasCheckedIn = hasIn;
      missingCheckIn = missingIn;

      attendanceDate = attDate;
      firstCheckIn = (first != null && first.trim().isNotEmpty) ? first : null;
      lastCheckOut = (last != null &&
          last.trim().isNotEmpty &&
          last.trim().toLowerCase() != 'null')
          ? last
          : null;

      workedHours = hours;
      minimumWorkingHour = _toHHMM(minWorkRaw);
      workHoursBelowMinimum = belowMin;
      checkedOutEarly = earlyOut;
      workHoursShortfall = _toHHMM(shortfallRaw);
      checkInImage = _cleanNullablePath(inImgRaw);
      checkOutImage = _cleanNullablePath(outImgRaw);

      _lastRttMs = rttMs;
      _hasServerTime = hasServerTime;
      if (hasServerTime) {
        _serverOffset = computedOffset;
      }
    });
  }

  bool _hasValue(String? v) {
    if (v == null) return false;
    final s = v.toString().trim();
    if (s.isEmpty) return false;
    if (s.toLowerCase() == 'null') return false;
    return true;
  }

  String? _toHHMM(String? hhmmss) {
    if (!_hasValue(hhmmss)) return null;
    final s = hhmmss!.trim();
    final parts = s.split(':');
    if (parts.length >= 2) {
      final h = parts[0].padLeft(2, '0');
      final m = parts[1].padLeft(2, '0');
      return '$h:$m';
    }
    return s;
  }

  String _toHHMMOrDash(String? hhmmss) {
    final v = _toHHMM(hhmmss);
    return _hasValue(v) ? v! : '--:--';
  }

  String _statusNote() {
    final hasIn = _hasValue(firstCheckIn);
    final hasOut = _hasValue(lastCheckOut);

    // No record yet
    if (!hasAttendance && !missingCheckIn) {
      if (checkInCutoffPassed && serverCanClockOut) {
        return 'Check-in cut-off passed. You can check out.';
      }
      return 'No record yet. Swipe to check in.';
    }

    // Forgot check-in (cutoff passed), but can still check out
    if (missingCheckIn) {
      if (hasOut) {
        return 'Checked out. Submit a request to add your check-in.';
      }
      return 'Missing check-in. You can check out now.';
    }

    // Normal flows
    if (hasIn && !hasOut) {
      return "Checked in. Don't forget to check out.";
    }

    if (hasIn && hasOut) {
      if (workHoursBelowMinimum) {
        if (_hasValue(workHoursShortfall)) {
          return 'Work hours short by ${workHoursShortfall!}.';
        }
        if (_hasValue(minimumWorkingHour)) {
          return 'Work hours below minimum (${minimumWorkingHour!}).';
        }
        return 'Work hours below minimum.';
      }

      if (checkedOutEarly) {
        return 'Checked out early. Submit a request if needed.';
      }

      return 'Attendance saved for today.';
    }

    // Edge: out exists without in (server didn’t flag missing check-in)
    if (!hasIn && hasOut) {
      return 'Checked out. Submit a request to add your check-in.';
    }

    return 'Attendance updated.';
  }


  String? _cleanNullablePath(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'null' || lower == 'none') return null;

    if (s.startsWith('http://') || s.startsWith('https://')) return s;

    // Normalize relative path so it can be joined with base URL
    if (!s.startsWith('/')) return '/$s';
    return s;
  }

  String? _buildMediaUrl(String? path) {
    if (path == null) return null;
    final p = path.trim();
    if (p.isEmpty) return null;

    if (p.startsWith('http://') || p.startsWith('https://')) return p;

    final b = baseUrl.trim();
    if (b.isEmpty) return p;

    return p.startsWith('/') ? '$b$p' : '$b/$p';
  }

  Widget _buildPhotoTile({required String label, required String? url}) {
    final fullUrl = _buildMediaUrl(url);
    final headers = getToken.isNotEmpty
        ? <String, String>{'Authorization': 'Bearer $getToken'}
        : <String, String>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey.shade100,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: fullUrl == null
                ? const Center(child: Text('-'))
                : Image.network(
              fullUrl,
              headers: headers,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Center(child: Text('-'));
              },
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ),
      ],
    );
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

      if (result != null) {
        final bool didIn = result['checkedIn'] == true;
        final bool didOut = result['checkedOut'] == true;

        if (didIn || didOut) {
          await refreshAttendanceStatus();
        }

        if (didOut && mounted) {
          // This happens when check-in cut-off has passed and user proceeds to check-out.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Check-out recorded but check-in is missing. Please submit an attendance request.',
              ),
            ),
          );
        }
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
    final checkInText = firstCheckIn ?? '-';
    final checkOutText = lastCheckOut ?? '-';
    final note = _statusNote().trim();

    return Container(
      color: Colors.red,
      padding: const EdgeInsets.all(16.0),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min, // Adaptive height (no empty space)
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Attendance',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                Text(dateLabel, style: const TextStyle(color: Colors.white70)),
              ],
            ),

            // Server time (minutes only), centered and continuously updated
            if (_hasServerTime) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: StreamBuilder<int>(
                  // Light refresh so minute rollover updates quickly
                  stream: Stream.periodic(const Duration(seconds: 5), (i) => i),
                  builder: (context, _) {
                    final serverNow = DateTime.now().add(_serverOffset);
                    return Text(
                      'Waktu Server • ${DateFormat('HH:mm').format(serverNow)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Stats row
            Row(
              children: [
                _headerStat(
                  label: 'First Check-In',
                  value: Text(
                    checkInText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                _headerStat(
                  label: 'Last Check-Out',
                  value: Text(
                    checkOutText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                _headerStat(
                  label: 'Work Hours',
                  value: Text(
                    _toHHMMOrDash(workedHours),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),

            // Centered note, only shown when not empty
            if (note.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: Text(
                  note,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    // Avatar
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
                                  headers: {'Authorization': 'Bearer $getToken'},
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, exception, stackTrace) =>
                                  const Icon(Icons.person, color: Colors.grey),
                                ),
                              ),
                            ),
                          if (requestsEmpProfile.isEmpty)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey[400],
                                ),
                                child: const Icon(Icons.person),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Name is always vertically centered relative to the avatar
                    Expanded(
                      child: SizedBox(
                        height: 40.0, // Same as the avatar height
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '$requestsEmpMyFirstName $requestsEmpMyLastName',
                            style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                            maxLines: 2, // Up to 2 lines
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
                      const Text('First Check-In'),
                      Text(firstCheckIn ?? '-'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Last Check-Out'),
                      Text(lastCheckOut ?? '-'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Shift'),
                      Flexible(
                        child: Text(
                          requestsEmpMyShiftName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildPhotoTile(
                        label: 'Check-In Photo',
                        url: checkInImage,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPhotoTile(
                        label: 'Check-Out Photo',
                        url: checkOutImage,
                      ),
                    ),
                  ],
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
            color: canCheckIn ? Colors.green : (canCheckOut ? Colors.red : Colors.grey),
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
