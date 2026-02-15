// checkin_checkout_form.dart (REVISED)
// - Server-driven actions (can_clock_in/out/update) + proof requirements from backend
// - Server Time shows ONLY when a swipe action is available
// - Work Hours shows ONLY as final value after check-out (no running timer)
// - Hide Server Time + Proof (photos/locations) when IN/OUT modes are both WFO (device-only day)
// - Show proof (photo + location) only for mobile modes (WFA / ON_DUTY) after the relevant punch exists
// - Keeps photo portrait safe (BoxFit.contain, no crop)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' as appSettings;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
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
  bool isCurrentlyCheckedIn = false; // legacy fallback
  bool missingCheckIn = false; // checked-out exists but check-in missing

  bool isPresenceOnly = false; // On Duty presence-only (no work hours)

  // Server-driven action flags (from /api/attendance/checking-in)
  bool serverCanClockIn = false;
  bool serverCanClockOut = false;
  bool serverCanUpdateClockOut = false;
  bool checkInCutoffPassed = false;

  // Proof requirements (from backend)
  bool requiresPhotoIn = false;
  bool requiresPhotoOut = false;
  bool requiresLocationIn = false;
  bool requiresLocationOut = false;

  String attendanceDate = ''; // yyyy-mm-dd (resolved)
  String? firstCheckIn;
  String? lastCheckOut;

  // Legacy (HH:MM / HH:MM:SS from server); keep as fallback only.
  String workedHours = '00:00:00';

  // New (preferred from API)
  int workedSeconds = 0; // worked_seconds from API
  bool isWorking = false; // is_working from API (running timer)
  bool _hasWorkedSecondsFromApi = false; // true if API sends worked_seconds
  DateTime? _serverNowAtLastFetch; // server-aligned time when status was fetched

  // Optional status helpers from backend (safe defaults if missing)
  String? minimumWorkingHour; // "HH:MM"
  bool workHoursBelowMinimum = false;
  String? workHoursShortfall; // "HH:MM"
  bool checkedOutEarly = false;

  // Late check-in info (from backend)
  bool lateCheckIn = false;
  String? lateBy; // "HH:MM"
  String? shiftStart; // "HH:MM" (from API: shift_start)

  // Shift / schedule display (from backend if available)
  String? shiftEnd; // "HH:MM"
  String? graceTime; // "HH:MM"
  String? checkInCutoffTime; // "HH:MM"
  String? checkOutCutoffTime; // "HH:MM"

  // Work mode (IN/OUT)
  String inMode = 'WFO';
  String outMode = 'WFO';


  // Work-mode request status for IN/OUT (optional, provided by backend)
  // Examples: \"pending\", \"approved\"
  String? inRequestStatus;
  String? outRequestStatus;

  // Proof (images + lat,lng) — only for mobile punches (e.g., WFA)
  String? checkInImage;
  String? checkOutImage;
  String? checkInLocation; // "lat, lng"
  String? checkOutLocation; // "lat, lng"

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

  // ===== Mode helpers =====

  String _normMode(String? m) {
    final s = (m ?? '').trim().toUpperCase();
    if (s.isEmpty) return 'WFO';
    if (s == 'WFH') return 'WFA'; // treat WFH as a type of remote for UI
    if (s == 'REMOTE') return 'WFA';
    if (s == 'WFA' || s == 'WFO') return s;
    if (s.contains('DUTY')) return 'ON_DUTY';
    return s;
  }

  bool _isWfoMode(String? m) => _normMode(m) == 'WFO';



  String _modeDisplay(String? m) {
    final nm = _normMode(m);
    if (nm == 'ON_DUTY') return 'ON Duty';
    return nm;
  }

  String? _normReqStatus(String? s) {
    if (s == null) return null;
    final v = s.toString().trim();
    if (v.isEmpty) return null;
    final lower = v.toLowerCase();
    if (lower == 'null' || lower == 'none') return null;

    final up = v.toUpperCase();
    if (up.contains('APPROV')) return 'APPROVED';
    if (up.contains('PEND')) return 'PENDING';
    if (up.contains('REJECT')) return 'REJECTED';
    if (up.contains('CANCEL')) return 'CANCELED';
    return up;
  }

  String _displayReqStatus(String status) {
    final s = status.trim().toUpperCase();
    if (s == 'APPROVED') return 'Approved';
    if (s == 'PENDING') return 'Pending';
    if (s == 'REJECTED') return 'Rejected';
    if (s == 'CANCELED') return 'Canceled';
    return s.substring(0, 1) + s.substring(1).toLowerCase();
  }

  bool get _isBothWfo => _normMode(inMode) == 'WFO' && _normMode(outMode) == 'WFO';

  bool get _shouldShowServerTime {
    // Hide server time when both punches are WFO (device-only day).
    if (_isBothWfo) return false;
    if (!_hasServerTime) return false;

    // Show server time only when the user actually needs to take a swipe action.
    return serverCanClockIn || serverCanClockOut;
  }

  // ===== Action label =====

  String get swipeDirection {
    if (canCheckIn) return 'Swipe ➜ CHECK IN';
    if (canCheckOut) {
      final hasOut = lastCheckOut != null;
      if (hasOut && serverCanUpdateClockOut) return 'Swipe ⇦ UPDATE CHECK OUT';
      return 'Swipe ⇦ CHECK OUT';
    }
    return 'Attendance action not available';
  }

  /// Can the user clock-in now?
  /// Prefer server flags, fallback to legacy behavior.
  bool get canCheckIn => serverCanClockIn;

  /// Can the user clock-out now?
  /// Server is the source of truth.
  bool get canCheckOut => serverCanClockOut;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      await fetchToken();
      await _ensureFaceDetectionAlwaysOn();

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

Future<void> _ensureFaceDetectionAlwaysOn() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  final typedServerUrl = prefs.getString('typed_url');

  await prefs.setBool('face_detection', true);

  if (token == null || typedServerUrl == null) return;

  final uri = Uri.parse('$typedServerUrl/api/facedetection/config/');
  try {
    await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'start': true}),
    );
  } catch (_) {
    // Ignore network errors; face flow will still proceed and server will validate.
  }
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

  Future<Position?> _ensureCurrentLocation({bool showSnackbars = true}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (showSnackbars && !_locationSnackBarShown && mounted) {
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
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (showSnackbars && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied.')),
            );
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (showSnackbars && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permissions are permanently denied.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => appSettings.openAppSettings(),
              ),
            ),
          );
        }
        return null;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return position;

      setState(() => userLocation = position);
      return position;
    } catch (e) {
      debugPrint('Error fetching location: $e');
      if (showSnackbars && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
      return null;
    }
  }

  // Backward-compatible alias (older code may still call this).
  Future<void> _initializeLocation() async {
    await _ensureCurrentLocation(showSnackbars: true);
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

  // ===== parsing helpers =====

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

  String? _toHHMMFromAny(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;

    // ISO datetime => HH:mm
    if (s.contains('T')) {
      try {
        final dt = DateTime.parse(s).toLocal();
        return DateFormat('HH:mm').format(dt);
      } catch (_) {}
    }

    // HH:mm(:ss)
    final v = _toHHMM(s);
    if (_hasValue(v)) return v;
    return null;
  }

  // Flex In duration can come as seconds/int or HH:mm(:ss)
  String? _graceToHHMM(dynamic raw) {
    if (raw == null) return null;

    int? secs;
    if (raw is num) {
      secs = raw.round();
    } else {
      final s0 = raw.toString().trim();
      if (s0.isEmpty || s0.toLowerCase() == 'null') return null;
      final asInt = int.tryParse(s0);
      if (asInt != null) secs = asInt;
    }

    // If provided as seconds (int/num), convert to HH:mm or HH:mm:ss (keep seconds if any)
    if (secs != null) {
      if (secs < 0) secs = 0;
      final h = (secs ~/ 3600).toString().padLeft(2, '0');
      final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
      final s = (secs % 60);
      if (s == 0) return '$h:$m';
      final ss = s.toString().padLeft(2, '0');
      return '$h:$m:$ss';
    }

    // Otherwise assume string HH:mm(:ss) and preserve seconds if any
    final s = raw.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;

    final parts = s.split(':');
    if (parts.length >= 2) {
      final hh = parts[0].padLeft(2, '0');
      final mm = parts[1].padLeft(2, '0');

      if (parts.length >= 3) {
        final secVal = int.tryParse(parts[2]) ?? 0;
        if (secVal == 0) return '$hh:$mm';
        final ss = secVal.toString().padLeft(2, '0');
        return '$hh:$mm:$ss';
      }
      return '$hh:$mm';
    }

    return null;
  }
  String _toHHMMOrDash(String? hhmmss) {
    final v = _toHHMM(hhmmss);
    return _hasValue(v) ? v! : '--:--';
  }

  String _formatDurationHHMM(Duration d) {
    final totalMinutes = d.inMinutes;
    final h = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatSecondsHHMM(int seconds) {
    final sec = seconds < 0 ? 0 : seconds;
    final totalMinutes = sec ~/ 60;
    final h = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  int? _hhmmToMinutes(String? hhmm) {
    if (!_hasValue(hhmm)) return null;
    final s = hhmm!.trim();
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    if (h < 0 || m < 0) return null;
    return (h * 60) + m;
  }

  String _minutesToHHMM(int totalMinutes) {
    final mins = totalMinutes % (24 * 60);
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

// plannedOut = shiftStart + minimumWorkingHour (informational only)
  String? _plannedCheckoutFromShiftStart() {
    if (!_hasValue(shiftStart) || !_hasValue(minimumWorkingHour)) return null;

    final startMin = _hhmmToMinutes(shiftStart);
    final reqMin = _hhmmToMinutes(minimumWorkingHour);

    if (startMin == null || reqMin == null) return null;

    final total = startMin + reqMin;
    final dayOffset = total ~/ (24 * 60);
    final hhmm = _minutesToHHMM(total);

    if (dayOffset > 0) return '$hhmm tomorrow';
    return hhmm;
  }

// Parse time or ISO datetime to DateTime, using attendanceDate as base if only HH:mm
  DateTime? _parseApiDateTime(String? raw, DateTime baseDate) {
    if (!_hasValue(raw)) return null;
    final s = raw!.trim();

    if (s.contains('T')) {
      try {
        return DateTime.parse(s).toLocal();
      } catch (_) {}
    }

    final parts = s.split(':');
    if (parts.length < 2) return null;

    final hh = int.tryParse(parts[0]) ?? 0;
    final mm = int.tryParse(parts[1]) ?? 0;

    int ss = 0;
    if (parts.length >= 3) {
      ss = int.tryParse(parts[2].split('.').first) ?? 0;
    }

    return DateTime(baseDate.year, baseDate.month, baseDate.day, hh, mm, ss);
  }

  DateTime _attendanceBaseDate(DateTime now) {
    final ad = attendanceDate.trim();
    final parsed = DateTime.tryParse(ad);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return DateTime(now.year, now.month, now.day);
  }

// ===== lat,lng proof helpers =====

  String? _formatLatLng(dynamic latRaw, dynamic lngRaw) {
    final lat = (latRaw is num) ? latRaw.toDouble() : double.tryParse(latRaw?.toString() ?? '');
    final lng = (lngRaw is num) ? lngRaw.toDouble() : double.tryParse(lngRaw?.toString() ?? '');
    if (lat == null || lng == null) return null;

    // round (cleaner UI + a bit more privacy)
    final latStr = lat.toStringAsFixed(5);
    final lngStr = lng.toStringAsFixed(5);
    return '$latStr, $lngStr';
  }

  String? _pickFirstLatLng(Map<String, dynamic> data, List<String> latKeys, List<String> lngKeys) {
    for (final latK in latKeys) {
      for (final lngK in lngKeys) {
        final v = _formatLatLng(data[latK], data[lngK]);
        if (_hasValue(v)) return v;
      }
    }
    return null;
  }

  String? _readLatLngFromApi(Map<String, dynamic> data, String prefix) {
    final p = prefix.toLowerCase();

    // nested: "<prefix>_location": {lat,lng} or {latitude,longitude}
    final nested = data['${p}_location'];
    if (nested is Map) {
      final v1 = _formatLatLng(nested['lat'], nested['lng']);
      if (_hasValue(v1)) return v1;

      final v2 = _formatLatLng(nested['latitude'], nested['longitude']);
      if (_hasValue(v2)) return v2;
    }

    // flat common combos
    final latKeys = <String>[
      '${p}_lat',
      '${p}_latitude',
      '${p}Lat',
      '${p}Latitude',
      // some backends use "clock_in_latitude" etc:
      p.contains('check') ? p.replaceAll('check_', 'clock_') + '_lat' : p,
      p.contains('check') ? p.replaceAll('check_', 'clock_') + '_latitude' : p,
    ];

    final lngKeys = <String>[
      '${p}_lng',
      '${p}_longitude',
      '${p}Lng',
      '${p}Longitude',
      p.contains('check') ? p.replaceAll('check_', 'clock_') + '_lng' : p,
      p.contains('check') ? p.replaceAll('check_', 'clock_') + '_longitude' : p,
    ];

    // also try hardcoded known fields
    final hard = _pickFirstLatLng(
      data,
      [
        '${p}_lat',
        '${p}_latitude',
        '${p}_latitide',
        'latitude',
      ],
      [
        '${p}_lng',
        '${p}_longitude',
        '${p}_longitide',
        'longitude',
      ],
    );
    if (_hasValue(hard)) return hard;

    final v = _pickFirstLatLng(data, latKeys, lngKeys);
    if (_hasValue(v)) return v;

    return null;
  }

  String _googleMapsUrlFromLatLng(String latLng) {
    final q = Uri.encodeComponent(latLng);
    return 'https://www.google.com/maps/search/?api=1&query=$q';
  }

  void _showMapLinkDialog(String title, String latLng) {
    final url = _googleMapsUrlFromLatLng(latLng);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

// ===== refresh status =====

  Future<void> refreshAttendanceStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    if (token == null || typedServerUrl == null) return;

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

    // server time offset
    bool hasServerTime = false;
    Duration computedOffset = _serverOffset;

    DateTime? serverAtReceiveTs;
    final serverNowRaw = data['server_now']?.toString();
    if (serverNowRaw != null && serverNowRaw.trim().isNotEmpty) {
      try {
        final serverNow = DateTime.parse(serverNowRaw).toLocal();
        serverAtReceiveTs = serverNow.add(Duration(milliseconds: (rttMs / 2).round()));
        computedOffset = serverAtReceiveTs.difference(t1);
        hasServerTime = true;
      } catch (_) {
        hasServerTime = false;
      }
    }
    serverAtReceiveTs ??= t1;

    final bool statusFlag = (data['status'] ?? false) == true;
    final bool hasAttendanceFlag = (data['has_attendance'] ?? false) == true;

    final bool cutoffPassed = (data['check_in_cutoff_passed'] ??
        data['check_in_cutoff_has_passed'] ??
        false) ==
        true;

    final String suggestedAction =
    (data['suggested_action'] ?? data['action'] ?? '').toString().toLowerCase();

    final bool canInFromApi = (data['can_clock_in'] ?? data['can_check_in'] ?? false) == true;
    final bool canOutFromApi = (data['can_clock_out'] ?? data['can_check_out'] ?? false) == true;
    final bool canUpdateOutFromApi =
        (data['can_update_clock_out'] ?? data['can_update_check_out'] ?? data['can_update_checkout'] ?? false) ==
            true;

    // Backend-driven proof requirements
    final bool reqPhotoInFromApi =
        (data['requires_photo_in'] ?? data['require_photo_in'] ?? data['photo_required_in'] ?? false) == true;
    final bool reqPhotoOutFromApi =
        (data['requires_photo_out'] ?? data['require_photo_out'] ?? data['photo_required_out'] ?? false) == true;
    final bool reqLocInFromApi =
        (data['requires_location_in'] ?? data['require_location_in'] ?? data['location_required_in'] ?? false) ==
            true;
    final bool reqLocOutFromApi =
        (data['requires_location_out'] ?? data['require_location_out'] ?? data['location_required_out'] ?? false) ==
            true;

    final String? first =
    (data['first_check_in'] ?? data['clock_in_time'] ?? data['clock_in'])?.toString();
    final String? last =
    (data['last_check_out'] ?? data['clock_out_time'] ?? data['clock_out'])?.toString();

    final String hours = (data['worked_hours'] ?? data['duration'] ?? '00:00:00').toString();

    // New fields
    final bool hasWorkedSec = data.containsKey('worked_seconds');
    final int workedSec = int.tryParse((data['worked_seconds'] ?? 0).toString()) ?? 0;

    final bool isWorkingFromApi =
        (data['is_working'] ?? data['is_currently_working'] ?? false) == true;

    // Optional hints
    final String? minWorkRaw =
    (data['minimum_working_hour'] ?? data['minimum_work_hours'] ?? data['min_working_hour'])
        ?.toString();

    final String? shortfallRaw =
    (data['work_hours_shortfall'] ?? data['work_hours_remaining'] ?? data['shortfall'])
        ?.toString();
    final bool hasBelowMinKey = data.containsKey('work_hours_below_minimum') ||
        data.containsKey('below_minimum_work_hours') ||
        data.containsKey('below_minimum') ||
        data.containsKey('below_min');

    final bool hasShortfallKey = data.containsKey('work_hours_shortfall') ||
        data.containsKey('work_hours_remaining') ||
        data.containsKey('shortfall');

    final bool belowMin =
        (data['work_hours_below_minimum'] ?? data['below_minimum_work_hours'] ?? data['below_minimum'] ?? data['below_min'] ?? false) == true;

    final bool earlyOut = (data['checked_out_early'] ?? data['early_check_out'] ?? false) == true;

    // Late info
    final bool late = (data['late_check_in'] ?? false) == true;
    final String? lateByRaw = (data['late_by'] ?? data['late_minutes'] ?? data['late'])?.toString();

    // Shift/schedule display
    final String? shiftStartRaw =
    (data['shift_start'] ?? data['shift_start_time'] ?? data['shift_start_hhmm'])?.toString();
    final String? shiftEndRaw =
    (data['shift_end'] ?? data['shift_end_time'] ?? data['shift_end_hhmm'])?.toString();

    final dynamic graceRaw =
        data['grace_time'] ?? data['grace'] ?? data['grace_allowed'] ?? data['allowed_grace'];

    final String? cutoffInRaw =
    (data['check_in_cutoff_time'] ?? data['cutoff_in'] ?? data['check_in_cutoff'])?.toString();
    final String? cutoffOutRaw =
    (data['check_out_cutoff_time'] ?? data['cutoff_out'] ?? data['check_out_cutoff'])?.toString();

    // Work modes
    final String inModeRaw =
    (data['in_mode'] ?? data['check_in_mode'] ?? data['clock_in_mode'] ?? 'WFO').toString();
    final String outModeRaw =
    (data['out_mode'] ?? data['check_out_mode'] ?? data['clock_out_mode'] ?? 'WFO').toString();

    // Presence-only hint (On Duty)
    final bool hasPresenceKey = data.containsKey('is_presensi_only') ||
        data.containsKey('is_presence_only') ||
        data.containsKey('presence_only');
    final bool presenceOnly = hasPresenceKey
        ? ((data['is_presensi_only'] ?? data['is_presence_only'] ?? data['presence_only'] ?? false) == true)
        : (_normMode(inModeRaw) == 'ON_DUTY' || _normMode(outModeRaw) == 'ON_DUTY');


// Work-mode request status (optional)
    String? _statusFrom(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      if (v is Map) return v['status']?.toString();
      return null;
    }

    final String? inReqStatusRaw = (data['in_request_status'] ??
        data['check_in_request_status'] ??
        _statusFrom(data['in_request']) ??
        _statusFrom(data['work_mode_request_in']) ??
        _statusFrom(data['work_mode_request']) ??
        '')
        .toString();

    final String? outReqStatusRaw = (data['out_request_status'] ??
        data['check_out_request_status'] ??
        _statusFrom(data['out_request']) ??
        _statusFrom(data['work_mode_request_out']) ??
        _statusFrom(data['work_mode_request']) ??
        '')
        .toString();

    // Images
    final String? inImgRaw =
    (data['check_in_image'] ?? data['clock_in_image'] ?? data['attendance_clock_in_image'])
        ?.toString();
    final String? outImgRaw =
    (data['check_out_image'] ?? data['clock_out_image'] ?? data['attendance_clock_out_image'])
        ?.toString();

    // Locations (lat,lng only)
    final String? inLoc =
        _readLatLngFromApi(data, 'clock_in') ?? _readLatLngFromApi(data, 'check_in');
    final String? outLoc =
        _readLatLngFromApi(data, 'clock_out') ?? _readLatLngFromApi(data, 'check_out');

    final String attDate = (data['attendance_date'] ?? '').toString();

    final bool hasIn = (data['has_checked_in'] ?? ((first ?? '').trim().isNotEmpty)) == true;

    final bool missingIn =
        (data['missing_check_in'] ?? false) == true || (cutoffPassed && !hasIn);

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

    final bool canUpdateOut =
    (data.containsKey('can_update_clock_out') ||
        data.containsKey('can_update_check_out') ||
        data.containsKey('can_update_checkout'))
        ? canUpdateOutFromApi
        : ((last ?? '').trim().isNotEmpty);

    final bool finalIsWorking =
    (data.containsKey('is_working') || data.containsKey('is_currently_working'))
        ? isWorkingFromApi
        : statusFlag;

    setState(() {
      isCurrentlyCheckedIn = finalIsWorking;

      checkInCutoffPassed = cutoffPassed;
      serverCanClockIn = canClockIn;
      serverCanClockOut = canClockOut;
      serverCanUpdateClockOut = canUpdateOut;

      requiresPhotoIn = reqPhotoInFromApi;
      requiresPhotoOut = reqPhotoOutFromApi;
      requiresLocationIn = reqLocInFromApi;
      requiresLocationOut = reqLocOutFromApi;

      hasAttendance = hasAttendanceFlag ||
          ((first ?? '').trim().isNotEmpty) ||
          ((last ?? '').trim().isNotEmpty);

      hasCheckedIn = hasIn;
      missingCheckIn = missingIn;

      isPresenceOnly = presenceOnly;

      attendanceDate = attDate;

      firstCheckIn =
      (first != null && first.trim().isNotEmpty && first.trim().toLowerCase() != 'null') ? first : null;

      lastCheckOut =
      (last != null && last.trim().isNotEmpty && last.trim().toLowerCase() != 'null') ? last : null;

      workedHours = hours;

      _hasWorkedSecondsFromApi = hasWorkedSec;
      workedSeconds = workedSec;
      isWorking = finalIsWorking;
      _serverNowAtLastFetch = serverAtReceiveTs;

      minimumWorkingHour = _toHHMMFromAny(minWorkRaw);

// Prefer server flags when provided; otherwise compute from worked_seconds vs required minutes.
      workHoursBelowMinimum = hasBelowMinKey ? belowMin : false;
      checkedOutEarly = earlyOut;

      lateCheckIn = late;
      lateBy = _toHHMMFromAny(lateByRaw);

      shiftStart = _toHHMMFromAny(shiftStartRaw);
      shiftEnd = _toHHMMFromAny(shiftEndRaw);
      graceTime = _graceToHHMM(graceRaw);
      checkInCutoffTime = _toHHMMFromAny(cutoffInRaw);
      checkOutCutoffTime = _toHHMMFromAny(cutoffOutRaw);

      inRequestStatus = _normReqStatus(inReqStatusRaw);
      outRequestStatus = _normReqStatus(outReqStatusRaw);

      inMode = _normMode(inModeRaw);
      outMode = _normMode(outModeRaw);

      workHoursShortfall = _toHHMMFromAny(shortfallRaw);

// Fallback compute shortfall/below-min when API doesn't provide it.
      if (!isPresenceOnly && _hasWorkedSecondsFromApi) {
        final reqMin = _requiredWorkMinutes();
        if (reqMin != null && reqMin > 0) {
          final shortSec = (reqMin * 60) - workedSeconds;
          final short = shortSec > 0 ? shortSec : 0;
          if (!hasShortfallKey) {
            workHoursShortfall = short > 0 ? _formatSecondsHHMM(short) : null;
          }
          if (!hasBelowMinKey) {
            workHoursBelowMinimum = short > 0 && _hasValue(lastCheckOut);
          }
        }
      }

      checkInImage = _cleanNullablePath(inImgRaw);
      checkOutImage = _cleanNullablePath(outImgRaw);
      checkInLocation = inLoc;
      checkOutLocation = outLoc;

      _lastRttMs = rttMs;
      _hasServerTime = hasServerTime;
      if (hasServerTime) {
        _serverOffset = computedOffset;
      }
    });
  }

// ===== Work hours rendering =====

  String _computeWorkHoursStatic(DateTime now) {
    if (_hasWorkedSecondsFromApi) {
      return _formatSecondsHHMM(workedSeconds);
    }

    final base = _attendanceBaseDate(now);
    final inDt = _parseApiDateTime(firstCheckIn, base);
    var outDt = _parseApiDateTime(lastCheckOut, base);

    if (missingCheckIn) {
      if (inDt == null || outDt == null) return '00:00';
      if (outDt.isBefore(inDt)) outDt = outDt.add(const Duration(days: 1));
      final diff = outDt.difference(inDt);
      return _formatDurationHHMM(diff.isNegative ? Duration.zero : diff);
    }

    if (inDt != null && outDt != null) {
      if (outDt.isBefore(inDt)) outDt = outDt.add(const Duration(days: 1));
      final diff = outDt.difference(inDt);
      return _formatDurationHHMM(diff.isNegative ? Duration.zero : diff);
    }

    return _toHHMMOrDash(workedHours);
  }

  Widget _buildWorkHoursValue(TextStyle style) {
    // Show work hours ONLY as the final value after check-out.
    // This avoids confusion between server time and biometric/device time.
    if (isPresenceOnly) {
      return Text('-', style: style);
    }

    if (!_hasValue(lastCheckOut)) {
      return Text('-', style: style);
    }

    final now = _hasServerTime ? DateTime.now().add(_serverOffset) : DateTime.now();
    return Text(_computeWorkHoursStatic(now), style: style);
  }

  String _statusNote() {
    final hasIn = _hasValue(firstCheckIn);
    final hasOut = _hasValue(lastCheckOut);

    if (!hasAttendance && !missingCheckIn) {
      if (checkInCutoffPassed && serverCanClockOut) return 'Check In cutoff passed • Check Out available';
      return 'No record yet • Please Check In';
    }

    if (missingCheckIn) {
      if (hasOut) return 'Missing Check In • Check Out saved';
      return 'Missing Check In • Check Out available';
    }

    if (hasIn && !hasOut) {
      if (lateCheckIn && _hasValue(lateBy)) {
        final planned = _plannedCheckoutFromShiftStart();
        if (planned != null) return 'Late ${lateBy!} • Check Out at $planned';
        return 'Late ${lateBy!}';
      }
      return 'Checked In • Don’t forget to Check Out';
    }

    if (hasIn && hasOut) {
      if (workHoursBelowMinimum) {
        if (lateCheckIn && _hasValue(lateBy)) {
          if (_hasValue(workHoursShortfall)) return 'Late ${lateBy!} • Short by ${workHoursShortfall!}';
          return 'Late ${lateBy!} • Below minimum hours';
        }
        if (_hasValue(workHoursShortfall)) return 'Short by ${workHoursShortfall!}';
        if (_hasValue(minimumWorkingHour)) return 'Below minimum (${minimumWorkingHour!})';
        return 'Below minimum hours';
      }

      if (checkedOutEarly) return 'Checked Out early';
      return 'Attendance recorded';
    }

    if (!hasIn && hasOut) return 'Check Out saved • Missing Check In';

    return '';
  }

// ===== Media helpers =====

  String? _cleanNullablePath(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'null' || lower == 'none') return null;

    if (s.startsWith('http://') || s.startsWith('https://')) return s;

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

// ===== Proof rules =====

  bool get _hasCheckedOut => _hasValue(lastCheckOut);

  bool get _inPunchIsMobile => !_isWfoMode(inMode);
  bool get _outPunchIsMobile => !_isWfoMode(outMode);

  bool get _shouldShowInProof => _inPunchIsMobile && (hasCheckedIn);
  bool get _shouldShowOutProof => _outPunchIsMobile && (_hasCheckedOut);

  bool get _shouldShowProofSection {
    if (_isBothWfo) return false;
    return _shouldShowInProof || _shouldShowOutProof;
  }

  Widget _buildProofTile({required String label, required String? url, required String? location}) {
    final fullUrl = _buildMediaUrl(url);
    final headers =
    getToken.isNotEmpty ? <String, String>{'Authorization': 'Bearer $getToken'} : <String, String>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                : Padding(
              padding: const EdgeInsets.all(6.0),
              child: Image.network(
                fullUrl,
                headers: headers,
                fit: BoxFit.contain, // portrait-safe (no crop)
                errorBuilder: (context, error, stackTrace) => const Center(child: Text('-')),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (_hasValue(location))
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  location!,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _showMapLinkDialog(label, location),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('Map', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
      ],
    );
  }


  Widget _statusBadge(String status) {
    final s = status.trim().toUpperCase();
    Color bg = Colors.grey.shade200;
    Color fg = Colors.grey.shade800;

    if (s == 'APPROVED') {
      bg = Colors.green.shade100;
      fg = Colors.green.shade800;
    } else if (s == 'PENDING') {
      bg = Colors.amber.shade100;
      fg = Colors.brown.shade800;
    } else if (s == 'REJECTED') {
      bg = Colors.red.shade100;
      fg = Colors.red.shade800;
    } else if (s == 'CANCELED') {
      bg = Colors.grey.shade300;
      fg = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _displayReqStatus(s),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _modeChip(String text, {String? status}) {
    final st = _normReqStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (st != null) ...[
            const SizedBox(width: 8),
            _statusBadge(st),
          ],
        ],
      ),
    );
  }

  Widget _buildModeRow() {
    final inText = 'IN: ${_modeDisplay(inMode)}';
    final outText = 'OUT: ${_modeDisplay(outMode)}';

    // Only show request status badges for request-based modes (WFA / ON Duty).
    final inStatus = (_normMode(inMode) == 'WFO') ? null : inRequestStatus;
    final outStatus = (_normMode(outMode) == 'WFO') ? null : outRequestStatus;

    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: [
        _modeChip(inText, status: inStatus),
        _modeChip(outText, status: outStatus),
      ],
    );
  }


  Widget _buildShiftLine() {
    final name = requestsEmpMyShiftName.trim().isEmpty ? 'Shift' : requestsEmpMyShiftName.trim();

    String timePart = '';
    if (_hasValue(shiftStart) && _hasValue(shiftEnd)) {
      timePart = '${shiftStart!}–${shiftEnd!}';
    } else if (_hasValue(shiftStart)) {
      timePart = shiftStart!;
    }

    final flexPart = _hasValue(graceTime) ? ' • Flex In ${_graceShortDisplay()}' : '';
    final text = timePart.isNotEmpty ? '$name • $timePart$flexPart' : '$name$flexPart';

    return Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis);
  }

  Widget _buildCutoffLine() {
    if (!_hasValue(checkInCutoffTime) && !_hasValue(checkOutCutoffTime)) return const SizedBox.shrink();
    final inTxt = _hasValue(checkInCutoffTime) ? checkInCutoffTime! : '--:--';
    final outTxt = _hasValue(checkOutCutoffTime) ? checkOutCutoffTime! : '--:--';
    return Text('Cutoff • In $inTxt • Out $outTxt', style: TextStyle(fontSize: 12, color: Colors.grey.shade700));
  }




  String _fmtHHMM(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  int? _requiredWorkMinutes() {
    final req = _hhmmToMinutes(minimumWorkingHour);
    if (req != null && req > 0) return req;

    final s = _hhmmToMinutes(shiftStart);
    final e = _hhmmToMinutes(shiftEnd);
    if (s == null || e == null) return null;
    var d = e - s;
    if (d < 0) d += 24 * 60;
    return d > 0 ? d : null;
  }

  bool get _isOnDutyDay {
    return isPresenceOnly || _normMode(inMode) == 'ON_DUTY' || _normMode(outMode) == 'ON_DUTY';
  }

  bool get _shouldShowExpectedOutLine {
    // Don't confuse users on "missing check-in" days (first punch is OUT)
    if (missingCheckIn) return false;

    // Only meaningful after we have a check-in time.
    if (!_hasValue(firstCheckIn)) return false;

    // Show only when it's actionable/needed:
    // - still working, OR
    // - already checked-out but work hours are still below minimum (so user knows what OUT time is expected).
    if (isWorking) return true;

    if (workHoursBelowMinimum && (serverCanUpdateClockOut || serverCanClockOut)) return true;

    return false;
  }

  String? _expectedOutDisplay() {
    if (!_shouldShowExpectedOutLine) return null;

    // On Duty: always show normal shift end (no flex expected out).
    if (_isOnDutyDay) {
      if (_hasValue(shiftEnd)) return shiftEnd!;
      return null;
    }

    final now = _hasServerTime ? DateTime.now().add(_serverOffset) : DateTime.now();
    final base = _attendanceBaseDate(now);

    final inDt = _parseApiDateTime(firstCheckIn, base);
    if (inDt == null) return null;

    // Flex rule:
    // - When check-in happens *within* the Flex In window, expected out is based on actual check-in.
    // - When check-in happens *after* Flex In ends, expected out is capped at the latest flex start
    //   (shiftStart + flexDuration). This avoids extending expected out later just because the
    //   employee arrived late.
    DateTime baseStart = inDt;
    final flexLatest = _latestFlexStartDateTime(base);
    if (flexLatest != null && inDt.isAfter(flexLatest)) {
      baseStart = flexLatest;
    }

    final reqMin = _requiredWorkMinutes();
    if (reqMin == null || reqMin <= 0) return null;

    final outDt = baseStart.add(Duration(minutes: reqMin));
    return _fmtHHMM(outDt);
  }

  DateTime? _latestFlexStartDateTime(DateTime baseDate) {
    // Flex In uses the same value as `graceTime` in API/UI (duration like HH:mm(:ss)).
    // Latest flex start = shiftStart + flexDuration.
    if (!_hasValue(shiftStart) || !_hasValue(graceTime)) return null;

    final start = _parseHHMMToTimeOfDay(shiftStart!);
    if (start == null) return null;

    final flexDur = _parseGraceToDuration(graceTime!);
    if (flexDur.inSeconds <= 0) return null;

    final startDt = DateTime(baseDate.year, baseDate.month, baseDate.day, start.hour, start.minute);
    return startDt.add(flexDur);
  }

  Widget _buildShiftInfoSection() {
    final shiftText = (_hasValue(shiftStart) && _hasValue(shiftEnd))
        ? '${shiftStart!}–${shiftEnd!}'
        : (_hasValue(shiftStart) ? shiftStart! : '--:--');

    final graceShort = _graceShortDisplay();
    final cutoffIn = _hasValue(checkInCutoffTime) ? checkInCutoffTime! : '--:--';
    final cutoffOut = _hasValue(checkOutCutoffTime) ? checkOutCutoffTime! : '--:--';

    final expectedOut = _expectedOutDisplay();

    // No extra "card" wrapper here (to avoid nested boxes). Just chips.
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModeRow(),
          const SizedBox(height: 12),

          // Row 1: [08:00–17:00] [Flex In 10m]
          Row(
            children: [
              Expanded(child: _infoChip(shiftText)),
              const SizedBox(width: 8),
              Expanded(child: _infoChip('Flex In $graceShort')),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: [IN ≤ 12:00] [OUT ≤ 23:59]
          Row(
            children: [
              Expanded(child: _infoChip('IN ≤ $cutoffIn')),
              const SizedBox(width: 8),
              Expanded(child: _infoChip('OUT ≤ $cutoffOut')),
            ],
          ),

          if (expectedOut != null) ...[
            const SizedBox(height: 10),
            Text(
              'Expected Check Out : $expectedOut',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _graceShortDisplay() {
    if (!_hasValue(graceTime)) return '--';
    final dur = _parseGraceToDuration(graceTime!);
    final totalSecs = dur.inSeconds;
    if (totalSecs <= 0) return '0m';

    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;

    if (mins == 0) return '${secs}s';
    if (secs == 0) return '${mins}m';
    return '${mins}m ${secs}s';
  }


  Widget _shiftInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  String _todayModeText() {
    final inText = _prettyMode(inMode);
    final outText = _prettyMode(outMode);
    if (inText == outText) return inText;
    return 'IN $inText / OUT $outText';
  }

  String _prettyMode(String? raw) {
    final m = _normMode(raw ?? 'WFO');
    switch (m) {
      case 'WFA':
        return 'WFA';
      case 'ON_DUTY':
        return 'ON DUTY';
      case 'WFO':
      default:
        return 'WFO';
    }
  }

  String _graceDisplay() {
    if (!_hasValue(graceTime)) return '-';
    final dur = _parseGraceToDuration(graceTime!);
    final totalSecs = dur.inSeconds;

    if (totalSecs <= 0) return '0m';

    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;

    final base = (mins == 0)
        ? '${secs}s'
        : (secs == 0 ? '${mins}m' : '${mins}m ${secs}s');

    final until = _graceUntil();
    if (until == null) return base;
    return '$base (hingga $until)';
  }

  String? _graceUntil() {
    if (!_hasValue(shiftStart) || !_hasValue(graceTime)) return null;
    final start = _parseHHMMToTimeOfDay(shiftStart!);
    if (start == null) return null;

    final dt = DateTime(2000, 1, 1, start.hour, start.minute)
        .add(_parseGraceToDuration(graceTime!));

    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');

    return dt.second == 0 ? '$hh:$mm' : '$hh:$mm:$ss';
  }

  Duration _parseGraceToDuration(String raw) {
    final parts = raw.split(':');
    int h = 0, m = 0, s = 0;
    if (parts.isNotEmpty) h = int.tryParse(parts[0]) ?? 0;
    if (parts.length >= 2) m = int.tryParse(parts[1]) ?? 0;
    if (parts.length >= 3) s = int.tryParse(parts[2]) ?? 0;
    return Duration(hours: h, minutes: m, seconds: s);
  }

  TimeOfDay? _parseHHMMToTimeOfDay(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

// ===== Errors / dialogs =====

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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }


// ===== Capture helpers =====

  Future<File?> _captureSelfie({bool showSnackbars = true}) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );
      if (xfile == null) return null;
      return File(xfile.path);
    } catch (e) {
      debugPrint('Error capturing selfie: $e');
      if (showSnackbars && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open camera: $e')),
        );
      }
      return null;
    }
  }

// ===== Clock post =====

  Future<Map<String, dynamic>?> _postClock({required bool isClockIn}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    if (token == null || typedServerUrl == null) return null;

    final requirePhoto = isClockIn ? requiresPhotoIn : requiresPhotoOut;
    final requireLocation = isClockIn ? requiresLocationIn : requiresLocationOut;

    Position? pos;
    if (requireLocation) {
      pos = userLocation ?? await _ensureCurrentLocation(showSnackbars: true);
      if (pos == null) {
        if (!_locationUnavailableSnackBarShown && mounted) {
          _locationUnavailableSnackBarShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location unavailable. Cannot proceed.')),
          );
        }
        return null;
      }
    }

    File? selfie;
    if (requirePhoto) {
      selfie = await _captureSelfie(showSnackbars: true);
      if (selfie == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo is required to proceed.')),
          );
        }
        return null;
      }
    }

    final endpoint = isClockIn ? '/api/attendance/clock-in/' : '/api/attendance/clock-out/';
    final base = typedServerUrl.endsWith('/')
        ? typedServerUrl.substring(0, typedServerUrl.length - 1)
        : typedServerUrl;
    final uri = Uri.parse('$base$endpoint');

    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      if (requireLocation && pos != null) {
        request.fields['latitude'] = pos.latitude.toString();
        request.fields['longitude'] = pos.longitude.toString();
        request.fields['accuracy'] = pos.accuracy.toString();
        request.fields['captured_at'] = DateTime.now().toIso8601String();
      }

      if (selfie != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            selfie.path,
            filename: p.basename(selfie.path),
          ),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) return decoded;
          return {};
        } catch (_) {
          return {};
        }
      }

      if (!mounted) return null;
      showActionFailedDialog(
        context,
        isClockIn ? 'Check-in Failed' : 'Check-out Failed',
        _extractErrorMessage(response.body),
      );
      return null;
    } catch (e) {
      debugPrint('Clock request failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _doClockIn() async {
    if (!canCheckIn) return;

    final prefs = await SharedPreferences.getInstance();
    final faceDetection = true;

    // Backend-driven location requirement (WFA / ON_DUTY)
    if (requiresLocationIn) {
      final pos = userLocation ?? await _ensureCurrentLocation(showSnackbars: true);
      if (pos == null) return;
    }

    if (faceDetection) {
      // FaceScanner sends location only when `geo_fencing` is true.
      // We DO NOT do geofencing validation; we only reuse the flag to include lat/lng in the request.
      final oldGeo = prefs.getBool('geo_fencing') ?? false;
      if (requiresLocationIn && !oldGeo) {
        await prefs.setBool('geo_fencing', true);
      }

      try {
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Check Out recorded, but no Check In was found. Please submit an attendance request.'),
              ),
            );
          }
        }
      } finally {
        if (requiresLocationIn && !oldGeo) {
          await prefs.setBool('geo_fencing', oldGeo);
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
    final faceDetection = true;

    // Backend-driven location requirement (WFA / ON_DUTY)
    if (requiresLocationOut) {
      final pos = userLocation ?? await _ensureCurrentLocation(showSnackbars: true);
      if (pos == null) return;
    }

    if (faceDetection) {
      // FaceScanner sends location only when `geo_fencing` is true.
      final oldGeo = prefs.getBool('geo_fencing') ?? false;
      if (requiresLocationOut && !oldGeo) {
        await prefs.setBool('geo_fencing', true);
      }

      try {
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
              const SnackBar(
                content: Text('Check Out recorded, but no Check In was found. Please submit an attendance request.'),
              ),
            );
          }
        }
      } finally {
        if (requiresLocationOut && !oldGeo) {
          await prefs.setBool('geo_fencing', oldGeo);
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
          const SnackBar(
            content: Text('Check Out recorded, but no Check In was found. Please submit an attendance request.'),
          ),
        );
      }
    }
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

// ===== UI =====

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
                Text('Attendance',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                Text('00:00:00', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Shimmer.fromColors(
            baseColor: Colors.grey,
            highlightColor: Colors.white70,
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Center(child: value),
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Attendance',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                Text(dateLabel, style: const TextStyle(color: Colors.white70)),
              ],
            ),

            if (_shouldShowServerTime) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: StreamBuilder<int>(
                  stream: Stream.periodic(const Duration(seconds: 5), (i) => i),
                  builder: (context, _) {
                    final serverNow = DateTime.now().add(_serverOffset);
                    return Text(
                      'Server Time • ${DateFormat('HH:mm').format(serverNow)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 16),

            Row(
              children: [
                _headerStat(
                  label: 'First Check-In',
                  value: Text(checkInText,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                _headerStat(
                  label: 'Last Check-Out',
                  value: Text(checkOutText,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                _headerStat(
                  label: 'Work Hours',
                  value: _buildWorkHoursValue(
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),

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
    final showProof = _shouldShowProofSection;

    final List<Widget> tiles = [];

    if (_shouldShowInProof) {
      tiles.add(
        Expanded(
          child: _buildProofTile(
            label: 'Check-In Proof',
            url: checkInImage,
            location: checkInLocation,
          ),
        ),
      );
    }

    if (_shouldShowOutProof) {
      tiles.add(
        Expanded(
          child: _buildProofTile(
            label: 'Check-Out Proof',
            url: checkOutImage,
            location: checkOutLocation,
          ),
        ),
      );
    }

    Widget proofWidget = const SizedBox.shrink();
    if (showProof && tiles.isNotEmpty) {
      if (tiles.length == 1) {
        proofWidget = Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Row(children: [tiles.first]),
        );
      } else {
        proofWidget = Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Row(
            children: [
              tiles[0],
              const SizedBox(width: 12),
              tiles[1],
            ],
          ),
        );
      }
    }

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[400]),
                                child: const Icon(Icons.person),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$requestsEmpMyFirstName $requestsEmpMyLastName',
                        style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                _buildShiftInfoSection(),

                // Proof section (mobile-only), hidden when both WFO
                proofWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeAction() {
    if (!canCheckIn && !canCheckOut) return const SizedBox.shrink();

    return GestureDetector(
      onPanUpdate: (details) async {
        if (_isProcessingDrag) return;
        if (details.delta.dx.abs() <= details.delta.dy.abs() || details.delta.dx.abs() <= 10) return;

        _isProcessingDrag = true;

        if (details.delta.dx > 0) {
          if (canCheckIn) {
            await _doClockIn();
          }
        } else {
          if (canCheckOut) {
            await _doClockOut();
          }
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
