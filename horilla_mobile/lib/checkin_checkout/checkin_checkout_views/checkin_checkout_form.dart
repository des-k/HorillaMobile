// checkin_checkout_form.dart (REVISED)
// - Server-driven actions (can_clock_in/out/update) + proof requirements from backend
// - Server Time shows for non-WFO days (WFA / WFH / ON_DUTY), even if no swipe action is available yet
// - Work Hours shows ONLY as final value after check-out (no running timer)
// - Hide Server Time + Proof (photos/locations) when IN/OUT modes are both WFO (device-only day)
// - Show proof (photo + location) only for mobile modes (WFA / WFH / ON_DUTY) after the relevant punch exists
// - Keeps photo portrait safe (BoxFit.contain, no crop)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' as appSettings;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:horilla/res/utilities/device_info.dart';
import 'package:horilla/res/utilities/mobile_attendance_settings.dart';
import 'face_detection.dart';
import 'mobile_header_state.dart';

class CheckInCheckOutFormTestOverrides {
  const CheckInCheckOutFormTestOverrides({
    this.loadToken,
    this.loadBaseUrl,
    this.fetchProofSettings,
    this.fetchEmployeeRecord,
    this.fetchEmployeeWorkInfoRecord,
    this.fetchAttendanceStatusPayload,
    this.launchFaceScanner,
  });

  final Future<String?> Function()? loadToken;
  final Future<String?> Function()? loadBaseUrl;
  final Future<MobileAttendanceSettingsResult> Function()? fetchProofSettings;
  final Future<Map<String, dynamic>?> Function()? fetchEmployeeRecord;
  final Future<Map<String, dynamic>?> Function(String workInfoId)? fetchEmployeeWorkInfoRecord;
  final Future<Map<String, dynamic>> Function()? fetchAttendanceStatusPayload;
  final Future<Object?> Function(
      BuildContext context, {
      required bool isClockIn,
      required Position? userLocation,
      required Map<String, dynamic> userDetails,
      })? launchFaceScanner;
}

class CheckInCheckOutFormPage extends StatefulWidget {
  const CheckInCheckOutFormPage({super.key, this.testOverrides});

  final CheckInCheckOutFormTestOverrides? testOverrides;

  @override
  _CheckInCheckOutFormPageState createState() => _CheckInCheckOutFormPageState();
}

class _CheckInCheckOutFormPageState extends State<CheckInCheckOutFormPage> with WidgetsBindingObserver {
  // UI state
  bool isLoading = true;
  String? _statusLoadErrorMessage;
  bool _isProcessingDrag = false;
  bool _locationSnackBarShown = false;
  bool _locationUnavailableSnackBarShown = false;

  // Attendance availability is driven by backend policy.
  bool attendanceEnabled = true;
  String? attendanceDisabledMessage;
  String? attendanceDisabledReasonCode;
  List<String> attendanceBlockedRoles = const [];

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

  bool isPresenceOnly = false; // Backend-driven attendance effect flag

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

  bool faceDetectionEnabled = true;
  bool locationEnabled = true;
  bool wfhGeofencingEnabled = true;
  int wfhRadiusInMeters = 250;
  bool requiresHomeReconfiguration = false;
  bool requiresFaceReenrollment = false;
  bool hasHomeLocationConfigured = false;
  Map<String, dynamic>? wfhProfile;

  String attendanceDate = ''; // yyyy-mm-dd (resolved)
  String? firstCheckIn;
  String? lastCheckOut;

  // Legacy (HH:MM / HH:MM:SS from server); keep as fallback only.
  String workedHours = '00:00';

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
  String? checkedOutEarlyBy; // "HH:MM"
  String? earliestCheckOut; // "HH:MM"

  // Late check-in info (from backend)
  bool lateCheckIn = false;
  String? lateBy; // "HH:MM"
  String? shiftStart; // "HH:MM" (from API: shift_start)

  // Shift / schedule display (from backend if available)
  String? shiftEnd; // "HH:MM"
  String? graceTime; // "HH:MM"
  String? graceClockInType; // after / before_after
  String? checkInCutoffTime; // "HH:MM"
  String? checkOutCutoffTime; // "HH:MM"

  // Server-driven window info (from CheckingStatus)
  String? checkInWindowStart; // \"HH:MM\"
  String? checkInWindowEnd;   // \"HH:MM\"
  String? checkOutWindowStart; // \"HH:MM\"
  String? checkOutWindowEnd;   // \"HH:MM\"
  String? checkInBlockReason;
  String? checkOutBlockReason;

  // Work mode (IN/OUT)
  String inMode = 'WFO';
  String outMode = 'WFO';
  String? inModeSource;
  String? outModeSource;
  String? inRequestedMode;
  String? outRequestedMode;

  // Attendance validity per punch (Option B; nullable when not provided by backend)
  String? inAttendanceStatus; // VALID / REJECTED
  String? outAttendanceStatus; // VALID / REJECTED
  String? inAttendanceRejectReasonCode;
  String? outAttendanceRejectReasonCode;


  // Work-mode request status for IN/OUT (optional, provided by backend)
  // Examples: \"pending\", \"approved\"
  String? inRequestStatus;
  String? outRequestStatus;

  // Proof (images + lat,lng) — only for mobile punches (e.g., WFA)
  String? checkInImage;
  String? checkOutImage;
  String? checkInLocation; // "lat, lng"
  String? checkOutLocation; // "lat, lng"

  // Canonical mobile header note (backend-driven)
  String? backendHeaderStateCode;
  String? backendHeaderStateMessage;
  String? backendHeaderDetailMessage;

  // Location
  Position? userLocation;

  // Server time (display only)
  // The app doesn't poll the server every second; instead it keeps an offset computed from
  // `server_now` + RTT/2 so the displayed server time keeps running smoothly.
  Duration _serverOffset = Duration.zero;
  bool _hasServerTime = false;
  int _lastRttMs = 0;

  // Auto-refresh status at the next server-time boundary (e.g., when a window starts/ends)
  // so swipe actions appear/disappear without manual refresh.
  Timer? _statusAutoRefreshTimer;
  DateTime? _statusAutoRefreshAtServer;

  // Bottom nav
  final _controller = NotchBottomBarController(index: 1);

  // ===== Mode helpers =====

  String _normMode(String? m) {
    final s = (m ?? '').trim().toUpperCase();
    if (s.isEmpty) return 'WFO';
    if (s == 'WFH') return 'WFH';
    if (s == 'REMOTE') return 'WFA';
    if (s == 'WFA' || s == 'WFO') return s;
    if (s.contains('DUTY')) return 'ON_DUTY';
    return s;
  }

  bool _isWfoMode(String? m) => _normMode(m) == 'WFO';
  bool _isWfhMode(String? m) => _normMode(m) == 'WFH';



  String _modeDisplay(String? m) {
    final nm = _normMode(m);
    if (nm == 'ON_DUTY') return 'ON Duty';
    return nm;
  }

  bool _shouldShowRequestBadge({
    required String displayMode,
    String? requestStatus,
    String? modeSource,
    String? requestedMode,
  }) {
    final rs = _normReqStatus(requestStatus);
    if (rs != 'APPROVED') return false;

    final source = (modeSource ?? '').trim().toLowerCase();
    if (source == 'approved_request' || source == 'request') {
      return true;
    }

    final display = _normMode(displayMode);
    final requested = _normMode(requestedMode);
    if (requested.isEmpty) return false;
    return requested == display;
  }

  String? _normReqStatus(String? s) {
    if (s == null) return null;
    final v = s.toString().trim();
    if (v.isEmpty) return null;
    final lower = v.toLowerCase();
    if (lower == 'null' || lower == 'none') return null;

    final up = v.toUpperCase();
    if (up.contains('APPROV')) return 'APPROVED';
    if (up.contains('WAIT')) return 'WAITING';
    if (up.contains('PEND')) return 'PENDING';
    if (up.contains('REJECT')) return 'REJECTED';
    if (up.contains('CANCEL')) return 'CANCELED';
    return up;
  }

  String _displayReqStatus(String status) {
    final s = status.trim().toUpperCase();
    if (s == 'APPROVED') return 'Approved';
    if (s == 'WAITING') return 'Waiting';
    if (s == 'PENDING') return 'Pending';
    if (s == 'REJECTED') return 'Rejected';
    if (s == 'CANCELED') return 'Canceled';
    if (s == 'VALID') return 'Valid';
    return s.substring(0, 1) + s.substring(1).toLowerCase();
  }

  String? _normPunchStatus(String? s) {
    if (s == null) return null;
    final v = s.toString().trim();
    if (v.isEmpty) return null;
    final up = v.toUpperCase();
    if (up.contains('VALID')) return 'VALID';
    if (up.contains('REJECT')) return 'REJECTED';
    return up;
  }

  bool get _isBothWfo => _normMode(inMode) == 'WFO' && _normMode(outMode) == 'WFO';

  bool get _shouldShowServerTime {
    // Server Time visibility rules:
    // 1) Hide when server_now is unavailable.
    // 2) Hide when both IN and OUT are WFO (device-only day).
    // 3) If both IN and OUT are non-WFO (WFA/WFH/ON_DUTY): always show.
    // 4) If IN=WFO and OUT is non-WFO: show only after check-in cutoff has passed
    //    (because the relevant constrained action is CHECK OUT).
    // 5) If IN is non-WFO and OUT=WFO: show only before check-in cutoff has passed
    //    (because the relevant constrained action is CHECK IN).

    if (!_hasServerTime) return false;
    if (_isBothWfo) return false;

    final bool inWfo = _isWfoMode(inMode);
    final bool outWfo = _isWfoMode(outMode);

    if (!inWfo && !outWfo) return true;
    if (inWfo && !outWfo) return checkInCutoffPassed;
    if (!inWfo && outWfo) return !checkInCutoffPassed;
    return true;
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
    WidgetsBinding.instance.addObserver(this);
    _initializeData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusAutoRefreshTimer?.cancel();
    _statusAutoRefreshTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !isLoading && !_isProcessingDrag) {
      unawaited(refreshAttendanceStatus());
    }
  }

  Future<void> _initializeData() async {
    try {
      await fetchToken();
      await _loadAttendanceProofSettings();

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
    final override = widget.testOverrides?.loadToken;
    final token = override != null
        ? await override()
        : (await SharedPreferences.getInstance()).getString('token');
    if (!mounted) {
      getToken = token ?? '';
      return;
    }
    setState(() => getToken = token ?? '');
  }

  Future<void> _openMaps(String? location) async {
    if (location == null) return;
    final s = location.trim();
    if (s.isEmpty) return;

    Uri uri;

    if (s.startsWith('http://') || s.startsWith('https://')) {
      uri = Uri.parse(s);
    } else {
      // Coba parse "lat,lng"
      final m = RegExp(r'^\s*(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)\s*$')
          .firstMatch(s);
      final query = m != null
          ? '${m.group(1)},${m.group(3)}'
          : Uri.encodeComponent(s);

      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _loadAttendanceProofSettings() async {
    final override = widget.testOverrides?.fetchProofSettings;
    final settings = override != null
        ? await override()
        : await MobileAttendanceSettingsService.fetchAndCache();
    if (!mounted) return;
    setState(() {
      faceDetectionEnabled = settings.faceDetectionEnabled;
      locationEnabled = settings.locationEnabled;
      wfhGeofencingEnabled = settings.wfhGeofencingEnabled;
      wfhRadiusInMeters = settings.wfhRadiusInMeters;
      requiresHomeReconfiguration = settings.requiresHomeReconfiguration;
      requiresFaceReenrollment = settings.requiresFaceReenrollment;
      hasHomeLocationConfigured = settings.hasHomeLocationConfigured;
    });
  }

  Future<MobileAttendanceSettingsResult> _refreshProofSettingsBeforePunch() async {
    final override = widget.testOverrides?.fetchProofSettings;
    final settings = override != null
        ? await override()
        : await MobileAttendanceSettingsService.fetchAndCache();
    if (mounted) {
      setState(() {
        faceDetectionEnabled = settings.faceDetectionEnabled;
        locationEnabled = settings.locationEnabled;
        wfhGeofencingEnabled = settings.wfhGeofencingEnabled;
        wfhRadiusInMeters = settings.wfhRadiusInMeters;
        requiresHomeReconfiguration = settings.requiresHomeReconfiguration;
        requiresFaceReenrollment = settings.requiresFaceReenrollment;
        hasHomeLocationConfigured = settings.hasHomeLocationConfigured;
      });
    } else {
      faceDetectionEnabled = settings.faceDetectionEnabled;
      locationEnabled = settings.locationEnabled;
      wfhGeofencingEnabled = settings.wfhGeofencingEnabled;
      wfhRadiusInMeters = settings.wfhRadiusInMeters;
      requiresHomeReconfiguration = settings.requiresHomeReconfiguration;
      requiresFaceReenrollment = settings.requiresFaceReenrollment;
      hasHomeLocationConfigured = settings.hasHomeLocationConfigured;
    }
    return settings;
  }

  Future<void> _refreshCanonicalStatusAfterRemoteAttempt() async {
    if (!mounted) return;
    try {
      await refreshAttendanceStatus();
    } catch (_) {}
  }

  String _extractApiMessage(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        final message = (decoded['message'] ?? decoded['detail'] ?? decoded['error'] ?? '').toString().trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    return responseBody.trim().isNotEmpty ? responseBody.trim() : 'Unable to process attendance request.';
  }


  Future<void> getBaseUrl() async {
    final override = widget.testOverrides?.loadBaseUrl;
    final typedServerUrl = override != null
        ? await override()
        : (await SharedPreferences.getInstance()).getString('typed_url');
    if (!mounted) {
      baseUrl = (typedServerUrl ?? '').trim();
      return;
    }
    setState(() => baseUrl = (typedServerUrl ?? '').trim());
  }

  Future<void> prefetchData() async {
    final override = widget.testOverrides?.fetchEmployeeRecord;
    Map<String, dynamic>? responseData;

    if (override != null) {
      responseData = await override();
    } else {
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
        responseData = Map<String, dynamic>.from(jsonDecode(response.body));
      }
    }

    if (responseData == null) return;

    arguments = {
      'employee_id': responseData['id'],
      'employee_name': '${responseData['employee_first_name'] ?? ''} ${responseData['employee_last_name'] ?? ''}'.trim(),
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
      'wfh_profile': responseData['wfh_profile'],
    };
  }

  Future<void> getLoginEmployeeRecord() async {
    final override = widget.testOverrides?.fetchEmployeeRecord;
    Map<String, dynamic>? responseBody;

    if (override != null) {
      responseBody = await override();
    } else {
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
        responseBody = Map<String, dynamic>.from(jsonDecode(response.body));
      }
    }

    if (responseBody == null) return;

    final body = responseBody;
    final employeeFirstName = body['employee_first_name'] ?? '';
    final employeeLastName = body['employee_last_name'] ?? '';
    final badgeId = body['badge_id'] ?? '';
    final departmentName = body['department_name'] ?? '';
    final employeeProfile = body['employee_profile'] ?? '';
    final employeeWorkInfoId = (body['employee_work_info_id'] ?? '').toString();

    if (!mounted) {
      requestsEmpMyFirstName = employeeFirstName;
      requestsEmpMyLastName = employeeLastName;
      requestsEmpMyBadgeId = badgeId;
      requestsEmpMyDepartment = departmentName;
      requestsEmpProfile = employeeProfile;
      requestsEmpMyWorkInfoId = employeeWorkInfoId;
    } else {
      setState(() {
        requestsEmpMyFirstName = employeeFirstName;
        requestsEmpMyLastName = employeeLastName;
        requestsEmpMyBadgeId = badgeId;
        requestsEmpMyDepartment = departmentName;
        requestsEmpProfile = employeeProfile;
        requestsEmpMyWorkInfoId = employeeWorkInfoId;
      });
    }

    if (requestsEmpMyWorkInfoId.isNotEmpty) {
      await getLoginEmployeeWorkInfoRecord(requestsEmpMyWorkInfoId);
    }
  }

  Future<void> getLoginEmployeeWorkInfoRecord(String workInfoId) async {
    final override = widget.testOverrides?.fetchEmployeeWorkInfoRecord;
    Map<String, dynamic>? responseBody;

    if (override != null) {
      responseBody = await override(workInfoId);
    } else {
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
        responseBody = Map<String, dynamic>.from(jsonDecode(response.body));
      }
    }

    if (responseBody == null) return;

    final body = responseBody;
    final shiftName = (body['shift_name'] ?? 'None').toString();

    if (!mounted) {
      requestsEmpMyShiftName = shiftName;
      return;
    }

    setState(() {
      requestsEmpMyShiftName = shiftName;
    });
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
    var s = raw.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;

    // Minute-based decimal payloads such as "225.5" must be displayed as-is.
    if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(s)) {
      return s;
    }

    // normalize legacy dot format "02.08" => "02:08" (only when it's a simple time)
    if (!s.contains('T') && s.contains('.') && !s.contains(':') && RegExp(r'^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$').hasMatch(s)) {
      s = s.replaceAll('.', ':');
    }

    // ISO datetime => HH:mm
    if (s.contains('T')) {
      try {
        final dt = DateTime.parse(s).toLocal();
        return DateFormat('HH:mm').format(dt);
      } catch (_) {}
    }

    // 12-hour (AM/PM) => HH:mm
    if (RegExp(r'\b(am|pm)\b', caseSensitive: false).hasMatch(s)) {
      try {
        final t = DateFormat('hh:mm a').parseLoose(s);
        return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
      try {
        final t = DateFormat('hh:mm:ss a').parseLoose(s);
        return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    // HH:mm(:ss) -> HH:mm
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

    // If provided as seconds (int/num), convert to HH:mm (minutes only; ignore seconds)
    if (secs != null) {
      if (secs < 0) secs = 0;
      final h = (secs ~/ 3600).toString().padLeft(2, '0');
      final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
      return '$h:$m';
    }

    // Otherwise assume string HH:mm(:ss) or legacy HH.mm and return HH:mm (minutes only)
    var s = raw.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;

    if (s.contains('.') && !s.contains(':') && RegExp(r'^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$').hasMatch(s)) {
      s = s.replaceAll('.', ':');
    }

    final parts = s.split(':');
    if (parts.length >= 2) {
      final hh = parts[0].padLeft(2, '0');
      final mm = parts[1].padLeft(2, '0');
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


// Parse time or ISO datetime to DateTime, using attendanceDate as base if only HH:mm
  DateTime? _parseApiDateTime(String? raw, DateTime baseDate) {
    if (!_hasValue(raw)) return null;

    var s = raw!.trim();
    if (s.isEmpty) return null;

    // normalize legacy dot format "02.08" => "02:08"
    if (!s.contains('T') && s.contains('.') && !s.contains(':') && RegExp(r'^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$').hasMatch(s)) {
      s = s.replaceAll('.', ':');
    }

    // ISO datetime
    if (s.contains('T')) {
      try {
        final dt = DateTime.parse(s).toLocal();
        // keep only minutes (seconds ignored for UI logic)
        return DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
      } catch (_) {}
    }

    // 12-hour (AM/PM)
    if (RegExp(r'\b(am|pm)\b', caseSensitive: false).hasMatch(s)) {
      try {
        final t = DateFormat('hh:mm a').parseLoose(s);
        return DateTime(baseDate.year, baseDate.month, baseDate.day, t.hour, t.minute);
      } catch (_) {}
      try {
        final t = DateFormat('hh:mm:ss a').parseLoose(s);
        return DateTime(baseDate.year, baseDate.month, baseDate.day, t.hour, t.minute);
      } catch (_) {}
    }

    // HH:mm(:ss)
    final parts = s.split(':');
    if (parts.length < 2) return null;

    final hh = int.tryParse(parts[0]) ?? 0;
    final mm = int.tryParse(parts[1]) ?? 0;

    return DateTime(baseDate.year, baseDate.month, baseDate.day, hh, mm);
  }


  DateTime _attendanceBaseDate(DateTime now) {
    // Prefer the resolved attendance date from API (yyyy-mm-dd).
    if (attendanceDate.trim().isNotEmpty) {
      try {
        final d = DateTime.parse(attendanceDate).toLocal();
        return DateTime(d.year, d.month, d.day);
      } catch (_) {}
    }
    return DateTime(now.year, now.month, now.day);
  }



  String _statusNote() {
    if (_hasValue(backendHeaderStateMessage)) {
      return backendHeaderStateMessage!.trim();
    }

    final hasIn = _hasValue(firstCheckIn);
    final hasOut = _hasValue(lastCheckOut);
    final now = _hasServerTime ? DateTime.now().add(_serverOffset) : DateTime.now();
    bool outCutoffPassed = false;

    if (_hasValue(checkOutCutoffTime)) {
      final base = _attendanceBaseDate(now);
      var cutoff = _parseApiDateTime(checkOutCutoffTime, base);
      if (cutoff != null) {
        final start = _hasValue(shiftStart) ? _parseApiDateTime(shiftStart, base) : null;
        final end = _hasValue(shiftEnd) ? _parseApiDateTime(shiftEnd, base) : null;
        final isNightShift = (start != null && end != null && end.isBefore(start));
        if (isNightShift && start != null && cutoff.isBefore(start)) {
          cutoff = cutoff.add(const Duration(days: 1));
        }
        outCutoffPassed = !now.isBefore(cutoff);
      }
    }

    if (!hasAttendance && !missingCheckIn) {
      if (outCutoffPassed && !serverCanClockOut) {
        return 'Check Out cutoff passed';
      }
      return 'No record yet';
    }

    if (missingCheckIn) {
      if (hasOut && checkedOutEarly) return 'Missing Check In, Check Out Early';
      return 'Missing Check In';
    }

    if (hasIn && !hasOut) {
      if (outCutoffPassed && !serverCanClockOut) {
        return 'Check Out cutoff passed';
      }
      return 'Checked In';
    }

    if (hasIn && hasOut) {
      if (checkedOutEarly) return 'Checked Out early';
      return 'Attendance recorded';
    }

    if (!hasIn && hasOut) {
      if (checkedOutEarly) return 'Missing Check In, Check Out Early';
      return 'Missing Check In';
    }

    return '';
  }

  String? _statusDetailNote() {
    if (_hasValue(backendHeaderDetailMessage)) {
      return backendHeaderDetailMessage!.trim();
    }

    final hasIn = _hasValue(firstCheckIn);
    final hasOut = _hasValue(lastCheckOut);
    final parts = <String>[];
    final now = _hasServerTime ? DateTime.now().add(_serverOffset) : DateTime.now();
    bool outCutoffPassed = false;

    if (_hasValue(checkOutCutoffTime)) {
      final base = _attendanceBaseDate(now);
      var cutoff = _parseApiDateTime(checkOutCutoffTime, base);
      if (cutoff != null) {
        final start = _hasValue(shiftStart) ? _parseApiDateTime(shiftStart, base) : null;
        final end = _hasValue(shiftEnd) ? _parseApiDateTime(shiftEnd, base) : null;
        final isNightShift = (start != null && end != null && end.isBefore(start));
        if (isNightShift && start != null && cutoff.isBefore(start)) {
          cutoff = cutoff.add(const Duration(days: 1));
        }
        outCutoffPassed = !now.isBefore(cutoff);
      }
    }

    if (!hasAttendance && !missingCheckIn) {
      if (outCutoffPassed && !serverCanClockOut) {
        return 'Please submit an attendance request';
      }
      return 'Please Check In';
    }

    if (missingCheckIn) {
      if (hasOut && checkedOutEarly) {
        if (_hasValue(checkedOutEarlyBy)) {
          return 'Short by ${checkedOutEarlyBy!} - Check Out saved';
        }
        return 'Check Out saved';
      }
      if (hasOut) return 'Check Out saved';
      if (serverCanClockOut) return 'Check Out available';
      return null;
    }

    if (hasIn && !hasOut) {
      if (outCutoffPassed && !serverCanClockOut) {
        return 'Please submit an attendance request';
      }
      if (lateCheckIn && _hasValue(lateBy)) {
        parts.add('Late by ${lateBy!}');
      }
      final eco = _hasValue(earliestCheckOut) ? earliestCheckOut : checkOutWindowStart;
      if (_hasValue(eco)) {
        parts.add('Earliest Check Out: ${eco!}');
      }
      return parts.isEmpty ? null : parts.join(' - ');
    }

    if (hasIn && hasOut) {
      if (checkedOutEarly) {
        if (_hasValue(checkedOutEarlyBy)) {
          parts.add('Short by ${checkedOutEarlyBy!}');
        }
        if (lateCheckIn && _hasValue(lateBy)) {
          parts.add('Late by ${lateBy!}');
        }
        return parts.isEmpty ? null : parts.join(' - ');
      }
      if (lateCheckIn && _hasValue(lateBy)) {
        return 'Late by ${lateBy!}';
      }
      return null;
    }

    if (!hasIn && hasOut) {
      if (checkedOutEarly) {
        if (_hasValue(checkedOutEarlyBy)) {
          return 'Short by ${checkedOutEarlyBy!} - Check Out saved';
        }
        return 'Check Out saved';
      }
      return 'Check Out saved';
    }

    return null;
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

  Future<void> _openMapLink(String title, String latLng) async {
    final urlStr = _googleMapsUrlFromLatLng(latLng);
    final uri = Uri.parse(urlStr);

    // Try opening Google Maps / browser directly (no dialog).
    final okExternal = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (okExternal) return;

    final okDefault = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (okDefault) return;

    // Final fallback: show a SnackBar with copy action (no modal dialog).
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Unable to open Maps. Link copied to clipboard.'),
        action: SnackBarAction(
          label: 'COPY',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: urlStr));
          },
        ),
      ),
    );

    await Clipboard.setData(ClipboardData(text: urlStr));
  }

// ===== refresh status =====

  Future<void> refreshAttendanceStatus() async {
    final t0 = DateTime.now();
    int rttMs = 0;
    Map<String, dynamic> data;

    try {
      final override = widget.testOverrides?.fetchAttendanceStatusPayload;
      if (override != null) {
        data = Map<String, dynamic>.from(await override());
        rttMs = DateTime.now().difference(t0).inMilliseconds;
      } else {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        final typedServerUrl = prefs.getString('typed_url');

        if (token == null || typedServerUrl == null) {
          if (mounted) {
            setState(() {
              _statusLoadErrorMessage = 'Missing login/session data.';
            });
          } else {
            _statusLoadErrorMessage = 'Missing login/session data.';
          }
          return;
        }

        final uri = Uri.parse('$typedServerUrl/api/attendance/checking-in');
        final response = await http.get(uri, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });
        final t1 = DateTime.now();
        rttMs = t1.difference(t0).inMilliseconds;

        if (response.statusCode != 200) {
          final msg = 'Failed to fetch attendance status. Please retry.';
          debugPrint('Failed to fetch attendance status: ${response.statusCode} ${response.body}');
          if (mounted) {
            setState(() {
              _statusLoadErrorMessage = msg;
            });
          } else {
            _statusLoadErrorMessage = msg;
          }
          return;
        }

        data = Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      final msg = 'Failed to fetch attendance status. Please retry.';
      debugPrint('Failed to fetch attendance status: $e');
      if (mounted) {
        setState(() {
          _statusLoadErrorMessage = msg;
        });
      } else {
        _statusLoadErrorMessage = msg;
      }
      return;
    }

    final t1 = DateTime.now();

    final headerState = MobileAttendanceHeaderState.fromApi(data);

    final bool enabledFromApi =
        (data['attendance_enabled'] ?? data['attendanceEnabled'] ?? data['is_attendance_enabled'] ?? true) == true;

    final dynamic blockedRolesRaw = data['blocked_roles'];
    final List<String> blockedRolesFromApi = blockedRolesRaw is List
        ? blockedRolesRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const [];

    final String? disabledReasonCodeFromApi = !enabledFromApi
        ? (data['attendance_disabled_reason'] ?? data['disabled_reason'])?.toString()
        : null;

    final String? disabledMsgFromApi = !enabledFromApi
        ? (data['attendance_disabled_message'] ??
        data['detail'] ??
        data['message'])
        ?.toString()
        : null;

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

    final String hours = (data['worked_hours'] ?? data['duration'] ?? '00:00').toString();

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

    // Window info (new API contract)
    final String? winInStartRaw = (data['check_in_window_start'] ?? data['checkin_window_start'] ?? data['check_in_start'])?.toString();
    final String? winInEndRaw = (data['check_in_window_end'] ?? data['checkin_window_end'] ?? data['check_in_end'])?.toString();
    final String? winOutStartRaw = (data['check_out_window_start'] ?? data['checkout_window_start'] ?? data['check_out_start'])?.toString();
    final String? winOutEndRaw = (data['check_out_window_end'] ?? data['checkout_window_end'] ?? data['check_out_end'])?.toString();

    final String? inBlockReasonRaw = (data['check_in_block_reason'] ?? data['check_in_block_reason_code'] ?? data['check_in_reason'])?.toString();
    final String? outBlockReasonRaw = (data['check_out_block_reason'] ?? data['check_out_block_reason_code'] ?? data['check_out_reason'])?.toString();


    // Work modes
    final String inModeRaw =
    (data['in_work_type'] ?? data['in_mode'] ?? data['check_in_mode'] ?? data['clock_in_mode'] ?? 'WFO').toString();
    final String outModeRaw =
    (data['out_work_type'] ?? data['out_mode'] ?? data['check_out_mode'] ?? data['clock_out_mode'] ?? 'WFO').toString();
    final String? inModeSourceRaw = (data['in_work_type_source'] ?? data['in_mode_source'] ?? data['check_in_mode_source'])?.toString();
    final String? outModeSourceRaw = (data['out_work_type_source'] ?? data['out_mode_source'] ?? data['check_out_mode_source'])?.toString();
    final String? inRequestedModeRaw = (data['in_requested_work_type'] ?? data['in_requested_mode'] ?? data['check_in_requested_mode'])?.toString();
    final String? outRequestedModeRaw = (data['out_requested_work_type'] ?? data['out_requested_mode'] ?? data['check_out_requested_mode'])?.toString();

    // Option B: punch validity (may be null)
    final String? inAttStatusRaw = data['in_attendance_status']?.toString();
    final String? outAttStatusRaw = data['out_attendance_status']?.toString();
    final String? inRejectRaw = data['in_attendance_reject_reason_code']?.toString();
    final String? outRejectRaw = data['out_attendance_reject_reason_code']?.toString();

    // Backend-driven attendance effect hint. Do not infer this from ON DUTY alone.
    final bool hasPresenceKey = data.containsKey('is_presensi_only') ||
        data.containsKey('is_presence_only') ||
        data.containsKey('presence_only');
    final bool presenceOnly = hasPresenceKey
        ? ((data['is_presensi_only'] ?? data['is_presence_only'] ?? data['presence_only'] ?? false) == true)
        : false;


// Work-mode request status (optional)
    String? _statusFrom(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      if (v is Map) return v['status']?.toString();
      return null;
    }

    final String? inReqStatusRaw = (data['in_work_type_request_status'] ??
        data['in_request_status'] ??
        data['check_in_request_status'] ??
        _statusFrom(data['in_work_type_request']) ??
        _statusFrom(data['in_request']) ??
        _statusFrom(data['work_mode_request_in']) ??
        _statusFrom(data['work_mode_request']) ??
        '')
        .toString();

    final String? outReqStatusRaw = (data['out_work_type_request_status'] ??
        data['out_request_status'] ??
        data['check_out_request_status'] ??
        _statusFrom(data['out_work_type_request']) ??
        _statusFrom(data['out_request']) ??
        _statusFrom(data['work_mode_request_out']) ??
        _statusFrom(data['work_mode_request']) ??
        '')
        .toString();

    final String? earliestCheckOutRaw = (data['earliest_check_out'] ?? data['planned_check_out'] ?? data['check_out_window_start'])?.toString();
    final String? checkedOutEarlyByRaw = (data['checked_out_early_by'])?.toString();

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
      _statusLoadErrorMessage = null;
      attendanceEnabled = enabledFromApi;
      attendanceDisabledReasonCode = disabledReasonCodeFromApi;
      attendanceBlockedRoles = blockedRolesFromApi;
      attendanceDisabledMessage = _resolveAttendanceDisabledMessage(
        explicitMessage: disabledMsgFromApi,
        reasonCode: disabledReasonCodeFromApi,
        blockedRoles: blockedRolesFromApi,
      );

      isCurrentlyCheckedIn = finalIsWorking;

      checkInCutoffPassed = cutoffPassed;
      // If attendance is disabled for this user, hide punch actions.
      serverCanClockIn = enabledFromApi ? canClockIn : false;
      serverCanClockOut = enabledFromApi ? canClockOut : false;
      serverCanUpdateClockOut = enabledFromApi ? canUpdateOut : false;

      requiresPhotoIn = enabledFromApi ? reqPhotoInFromApi : false;
      requiresPhotoOut = enabledFromApi ? reqPhotoOutFromApi : false;
      requiresLocationIn = enabledFromApi ? reqLocInFromApi : false;
      requiresLocationOut = enabledFromApi ? reqLocOutFromApi : false;

      hasAttendance = hasAttendanceFlag ||
          ((first ?? '').trim().isNotEmpty) ||
          ((last ?? '').trim().isNotEmpty);

      hasCheckedIn = hasIn;
      missingCheckIn = missingIn;

      isPresenceOnly = presenceOnly;

      attendanceDate = attDate;
      backendHeaderStateCode = headerState.code;
      backendHeaderStateMessage = headerState.message;
      backendHeaderDetailMessage = headerState.detailMessage;

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
      checkedOutEarlyBy = _toHHMMFromAny(checkedOutEarlyByRaw);
      earliestCheckOut = _toHHMMFromAny(earliestCheckOutRaw);

      lateCheckIn = late;
      lateBy = _toHHMMFromAny(lateByRaw);

      shiftStart = _toHHMMFromAny(shiftStartRaw);
      shiftEnd = _toHHMMFromAny(shiftEndRaw);
      graceTime = _graceToHHMM(graceRaw);
      graceClockInType = _normalizeClockInType((data['clock_in_type'] ?? data['grace_clock_in_type'] ?? data['grace_type'])?.toString());
      checkInCutoffTime = _toHHMMFromAny(cutoffInRaw);
      checkOutCutoffTime = _toHHMMFromAny(cutoffOutRaw);

      checkInWindowStart = _toHHMMFromAny(winInStartRaw);
      checkInWindowEnd = _toHHMMFromAny(winInEndRaw);
      checkOutWindowStart = _toHHMMFromAny(winOutStartRaw);
      checkOutWindowEnd = _toHHMMFromAny(winOutEndRaw);
      checkInBlockReason = _cleanReason(inBlockReasonRaw);
      checkOutBlockReason = _cleanReason(outBlockReasonRaw);

      inRequestStatus = _normReqStatus(inReqStatusRaw);
      outRequestStatus = _normReqStatus(outReqStatusRaw);

      inAttendanceStatus = _normPunchStatus(inAttStatusRaw);
      outAttendanceStatus = _normPunchStatus(outAttStatusRaw);
      inAttendanceRejectReasonCode = (inRejectRaw == null || inRejectRaw.trim().isEmpty) ? null : inRejectRaw.trim();
      outAttendanceRejectReasonCode = (outRejectRaw == null || outRejectRaw.trim().isEmpty) ? null : outRejectRaw.trim();

      inMode = _normMode(inModeRaw);
      outMode = _normMode(outModeRaw);
      inModeSource = (inModeSourceRaw == null || inModeSourceRaw.trim().isEmpty) ? null : inModeSourceRaw.trim();
      outModeSource = (outModeSourceRaw == null || outModeSourceRaw.trim().isEmpty) ? null : outModeSourceRaw.trim();
      inRequestedMode = (inRequestedModeRaw == null || inRequestedModeRaw.trim().isEmpty) ? null : _normMode(inRequestedModeRaw);
      outRequestedMode = (outRequestedModeRaw == null || outRequestedModeRaw.trim().isEmpty) ? null : _normMode(outRequestedModeRaw);

      workHoursShortfall = _toHHMMFromAny(shortfallRaw);


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

    // Auto-refresh at the next window boundary so swipe actions update without manual refresh.
    if (!mounted) return;
    if (hasServerTime) {
      final nowServer = DateTime.now().add(computedOffset);
      _scheduleNextStatusRefresh(nowServer);
    } else {
      _cancelNextStatusRefresh();
    }
  }

  void _cancelNextStatusRefresh() {
    _statusAutoRefreshTimer?.cancel();
    _statusAutoRefreshTimer = null;
    _statusAutoRefreshAtServer = null;
  }

  DateTime? _adjustForNightShiftIfNeeded(DateTime? dt, DateTime base) {
    if (dt == null) return null;
    final start = _hasValue(shiftStart) ? _parseApiDateTime(shiftStart, base) : null;
    final end = _hasValue(shiftEnd) ? _parseApiDateTime(shiftEnd, base) : null;
    final isNightShift = (start != null && end != null && end.isBefore(start));
    if (isNightShift && start != null && dt.isBefore(start)) {
      return dt.add(const Duration(days: 1));
    }
    return dt;
  }

  void _scheduleNextStatusRefresh(DateTime serverNow) {
    // Only schedule when we have server time; otherwise we might schedule using device time.
    if (!_hasServerTime) {
      _cancelNextStatusRefresh();
      return;
    }

    final base = _attendanceBaseDate(serverNow);

    final inStart = _adjustForNightShiftIfNeeded(_parseApiDateTime(checkInWindowStart, base), base);
    final inEnd = _adjustForNightShiftIfNeeded(
      _parseApiDateTime(checkInWindowEnd ?? checkInCutoffTime, base),
      base,
    );
    final outStart = _adjustForNightShiftIfNeeded(_parseApiDateTime(checkOutWindowStart, base), base);
    final outEnd = _adjustForNightShiftIfNeeded(
      _parseApiDateTime(checkOutWindowEnd ?? checkOutCutoffTime, base),
      base,
    );

    final List<DateTime> candidates = [];

    // Check-In becomes available at window start, and becomes unavailable at window end.
    if (!serverCanClockIn) {
      if (inStart != null && serverNow.isBefore(inStart)) candidates.add(inStart);
    } else {
      if (inEnd != null && serverNow.isBefore(inEnd)) candidates.add(inEnd);
    }

    // Check-Out becomes available at window start, and becomes unavailable at window end.
    if (!serverCanClockOut) {
      if (outStart != null && serverNow.isBefore(outStart)) candidates.add(outStart);
    } else {
      if (outEnd != null && serverNow.isBefore(outEnd)) candidates.add(outEnd);
    }

    if (candidates.isEmpty) {
      _cancelNextStatusRefresh();
      return;
    }

    candidates.sort();
    final nextAtServer = candidates.first;

    // Avoid re-scheduling the same boundary repeatedly.
    if (_statusAutoRefreshAtServer != null && _statusAutoRefreshAtServer!.isAtSameMomentAs(nextAtServer)) {
      return;
    }

    _cancelNextStatusRefresh();
    _statusAutoRefreshAtServer = nextAtServer;

    var delay = nextAtServer.difference(serverNow);
    // Add a small buffer so the server is safely past the boundary.
    delay += const Duration(seconds: 2);

    if (delay.isNegative) {
      // Boundary already passed; don't schedule.
      _statusAutoRefreshAtServer = null;
      return;
    }

    // Cap very long timers to reduce risk of stale state; refresh again sooner.
    if (delay.inHours > 12) {
      delay = const Duration(hours: 12);
    }

    _statusAutoRefreshTimer = Timer(delay, () async {
      if (!mounted) return;
      await refreshAttendanceStatus();
    });
  }

  int _computeWorkedMinutesFromPunches(DateTime now) {
    if (!_hasValue(firstCheckIn) || !_hasValue(lastCheckOut)) return 0;

    final base = _attendanceBaseDate(now);

    DateTime? inDt = _parseApiDateTime(firstCheckIn, base);
    DateTime? outDt = _parseApiDateTime(lastCheckOut, base);
    if (inDt == null || outDt == null) return 0;

    final DateTime? shiftStartDt = _hasValue(shiftStart) ? _parseApiDateTime(shiftStart, base) : null;
    final DateTime? shiftEndOnBase = _hasValue(shiftEnd) ? _parseApiDateTime(shiftEnd, base) : null;

    final bool isNightShift = (shiftStartDt != null && shiftEndOnBase != null && shiftEndOnBase.isBefore(shiftStartDt));

    // For night shifts, times after midnight (e.g., 00:10) are earlier than shift_start when parsed
    // against the base date. Move them to the next day (but keep early check-in like 21:00 on the same day).
    if (isNightShift && shiftEndOnBase != null) {
      if (inDt.isBefore(shiftEndOnBase)) inDt = inDt.add(const Duration(days: 1));
      if (outDt.isBefore(shiftEndOnBase)) outDt = outDt.add(const Duration(days: 1));
    }

    if (outDt.isBefore(inDt)) outDt = outDt.add(const Duration(days: 1));

    // Work hours starts from shift_start if the employee checked in earlier than shift start.
    if (shiftStartDt != null && inDt.isBefore(shiftStartDt)) {
      inDt = shiftStartDt;
    }

    final diffMin = outDt.difference(inDt).inMinutes;
    return diffMin < 0 ? 0 : diffMin;
  }

// ===== Work hours rendering =====

  String _computeWorkHoursStatic(DateTime now) {
    // Work Hours shows ONLY as a final value after a completed attendance pair.
    // It is computed from First Check-In and Last Check-Out (minute-based),
    // but if First Check-In is earlier than shift start, we start counting from shift start.

    if (!_hasValue(firstCheckIn) || !_hasValue(lastCheckOut)) return '-';

    final workedMin = _computeWorkedMinutesFromPunches(now);
    return _minutesToHHMM(workedMin);
  }

  Widget _buildWorkHoursValue(TextStyle style) {
    // Show work hours ONLY as the final value after a VALID completed attendance pair.
    if (isPresenceOnly) {
      return Text('-', style: style);
    }

    if (!_hasValue(firstCheckIn) || !_hasValue(lastCheckOut)) {
      return Text('-', style: style);
    }

    // If the OUT punch is rejected (early checkout), do not treat it as a valid completion.
    if (_normPunchStatus(outAttendanceStatus) == 'REJECTED') {
      return Text('-', style: style);
    }

    if (_hasWorkedSecondsFromApi) {
      final apiMinutes = workedSeconds < 0 ? 0 : workedSeconds ~/ 60;
      return Text(_minutesToHHMM(apiMinutes), style: style);
    }

    final now = _hasServerTime ? DateTime.now().add(_serverOffset) : DateTime.now();
    return Text(_computeWorkHoursStatic(now), style: style);
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

  String? _cleanReason(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'null' || lower == 'none') return null;
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
        // Keep a consistent height so IN/OUT tiles stay aligned even if one side has no location.
        // IMPORTANT: keep the whole caption centered (icon + text + link), even when there is only ONE tile.
        SizedBox(
          height: 44,
          child: _hasValue(location)
              ? LayoutBuilder(
            builder: (context, c) {
              final maxTextWidth = (c.maxWidth - 70).clamp(60.0, c.maxWidth);
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxTextWidth),
                          child: Text(
                            location!,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () => _openMapLink(label, location!),
                    child: Text(
                      'Open Maps',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              );
            },
          )
              : const SizedBox.shrink(),
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
    } else if (s == 'VALID') {
      bg = Colors.green.shade100;
      fg = Colors.green.shade800;
    } else if (s == 'WAITING') {
      bg = Colors.amber.shade100;
      fg = Colors.brown.shade800;
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

  Widget _modeChip(String text, {String? requestStatus, String? punchStatus}) {
    final rs = _normReqStatus(requestStatus);
    final ps = _normPunchStatus(punchStatus);
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
          if (rs != null) ...[
            const SizedBox(width: 8),
            _statusBadge(rs),
          ],
          if (ps != null) ...[
            const SizedBox(width: 8),
            _statusBadge(ps),
          ],
        ],
      ),
    );
  }

  Widget _buildModeRow() {
    final inText = 'IN: ${_modeDisplay(inMode)}';
    final outText = 'OUT: ${_modeDisplay(outMode)}';

    // Only show request badges when the visible mode is actually request-driven.
    final inReq = _shouldShowRequestBadge(
      displayMode: inMode,
      requestStatus: inRequestStatus,
      modeSource: inModeSource,
      requestedMode: inRequestedMode,
    ) ? inRequestStatus : null;
    final outReq = _shouldShowRequestBadge(
      displayMode: outMode,
      requestStatus: outRequestStatus,
      modeSource: outModeSource,
      requestedMode: outRequestedMode,
    ) ? outRequestStatus : null;

    final chips = Wrap(
      alignment: WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: [
        _modeChip(inText, requestStatus: inReq, punchStatus: inAttendanceStatus),
        _modeChip(outText, requestStatus: outReq, punchStatus: outAttendanceStatus),
      ],
    );

    final List<Widget> rejects = [];
    if (inAttendanceStatus == 'REJECTED' && _hasValue(inAttendanceRejectReasonCode)) {
      rejects.add(Text('IN rejected: ${inAttendanceRejectReasonCode!}', style: TextStyle(fontSize: 12, color: Colors.red.shade700)));
    }
    if (outAttendanceStatus == 'REJECTED' && _hasValue(outAttendanceRejectReasonCode)) {
      rejects.add(Text('OUT rejected: ${outAttendanceRejectReasonCode!}', style: TextStyle(fontSize: 12, color: Colors.red.shade700)));
    }

    if (rejects.isEmpty) return chips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chips,
        const SizedBox(height: 6),
        ...rejects,
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

    final flexPart = _hasValue(graceTime) ? ' • ${_graceDisplayWithMode()}' : '';
    final text = timePart.isNotEmpty ? '$name • $timePart$flexPart' : '$name$flexPart';

    return Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis);
  }

  Widget _buildCutoffLine() {
    if (!_hasValue(checkInCutoffTime) && !_hasValue(checkOutCutoffTime)) return const SizedBox.shrink();
    final inTxt = _hasValue(checkInCutoffTime) ? checkInCutoffTime! : '--:--';
    final outTxt = _hasValue(checkOutCutoffTime) ? checkOutCutoffTime! : '--:--';
    return Text('Cutoff • In $inTxt • Out $outTxt', style: TextStyle(fontSize: 12, color: Colors.grey.shade700));
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

  Widget _buildShiftInfoSection() {
    final shiftText = (_hasValue(shiftStart) && _hasValue(shiftEnd))
        ? '${shiftStart!}–${shiftEnd!}'
        : (_hasValue(shiftStart) ? shiftStart! : '--:--');

    final cutoffIn = _hasValue(checkInCutoffTime) ? checkInCutoffTime! : '--:--';
    final cutoffOut = _hasValue(checkOutCutoffTime) ? checkOutCutoffTime! : '--:--';

    final inStart = _hasValue(checkInWindowStart)
        ? checkInWindowStart!
        : (_hasValue(shiftStart) ? shiftStart! : '--:--');
    final inEnd = _hasValue(checkInWindowEnd) ? checkInWindowEnd! : cutoffIn;

    final outStart = _isOnDutyDay
        ? (_hasValue(checkOutWindowStart) ? checkOutWindowStart! : cutoffIn)
        : (_hasValue(checkOutWindowStart)
        ? checkOutWindowStart!
        : (_hasValue(shiftEnd) ? shiftEnd! : '--:--'));
    final outEnd = _hasValue(checkOutWindowEnd) ? checkOutWindowEnd! : cutoffOut;

    final checkInLine = '$inStart – $inEnd';
    // Always show a full range for check-out window.
    // For ON DUTY, backend already sets start to (cutoff_in + 1 minute).
    final checkOutLine = '$outStart – $outEnd';

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
              Expanded(child: _infoChip(_graceDisplayWithMode())),
            ],
          ),
          const SizedBox(height: 8),

          // Attendance windows (one line per type)
          SizedBox(
            width: double.infinity,
            child: _infoChipKV('Check In Window', checkInLine),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _infoChipKV('Check Out Window', checkOutLine),
          ),

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

  Widget _infoChipKV(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
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

  String? _normalizeClockInType(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'before_after' || value == 'before and after' || value == 'before-and-after') {
      return 'before_after';
    }
    if (value == 'after') return 'after';
    return value;
  }

  String _graceModeSymbol() {
    switch (_normalizeClockInType(graceClockInType)) {
      case 'before_after':
        return '±';
      case 'after':
        return '+';
      default:
        return '';
    }
  }

  String _graceDisplayWithMode() {
    final short = _graceShortDisplay();
    final symbol = _graceModeSymbol();
    if (short == '--') return 'Flex In $short';
    if (symbol.isEmpty) return 'Flex In $short';
    return 'Flex In $symbol$short';
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
      case 'WFH':
        return 'WFH';
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

    await _refreshProofSettingsBeforePunch();

    final requirePhoto = isClockIn ? requiresPhotoIn : requiresPhotoOut;
    final requireLocation = locationEnabled || (isClockIn ? requiresLocationIn : requiresLocationOut);

    final pos = requireLocation
        ? (userLocation ?? await _ensureCurrentLocation(showSnackbars: true))
        : userLocation;
    if (requireLocation && pos == null) {
      if (!_locationUnavailableSnackBarShown && mounted) {
        _locationUnavailableSnackBarShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location unavailable. Cannot proceed.')),
        );
      }
      return null;
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

      if (pos != null) {
        request.fields['latitude'] = pos.latitude.toString();
        request.fields['longitude'] = pos.longitude.toString();
        request.fields['accuracy'] = pos.accuracy.toString();
      }
      request.fields['captured_at'] = DateTime.now().toIso8601String();

      final deviceInfoPayload = await HorillaDeviceInfo.getPayload();
      request.fields.addAll(deviceInfoPayload);

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
        isClockIn ? 'Check In Failed' : 'Check Out Failed',
        _extractErrorMessage(response.body),
      );
      await _refreshCanonicalStatusAfterRemoteAttempt();
      return null;
    } catch (e) {
      debugPrint('Clock request failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e')),
        );
      }
      await _refreshCanonicalStatusAfterRemoteAttempt();
      return null;
    }
  }


  double? _wfhHomeLatitude() {
    final raw = wfhProfile?['home_latitude'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  double? _wfhHomeLongitude() {
    final raw = wfhProfile?['home_longitude'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  double? _distanceToWfhHomeMeters(Position pos) {
    final homeLat = _wfhHomeLatitude();
    final homeLng = _wfhHomeLongitude();
    if (homeLat == null || homeLng == null) return null;
    return Geolocator.distanceBetween(homeLat, homeLng, pos.latitude, pos.longitude);
  }

  Future<bool> _submitWfhHomeSetup(Position pos) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');
    if (token == null || typedServerUrl == null) return false;
    final uri = Uri.parse('$typedServerUrl/api/attendance/wfh/home-setup/');
    final response = await http.post(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    }, body: jsonEncode({
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracy': pos.accuracy,
      'captured_at': DateTime.now().toIso8601String(),
    }));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['wfh_profile'] is Map) {
          wfhProfile = Map<String, dynamic>.from(decoded['wfh_profile']);
        }
      } catch (_) {}
      hasHomeLocationConfigured = true;
      requiresHomeReconfiguration = false;
      return true;
    }
    return false;
  }

  Future<bool> _ensureWfhReady({required bool isClockIn}) async {
    final mode = isClockIn ? inMode : outMode;
    if (!_isWfhMode(mode)) return true;

    final pos = userLocation ?? await _ensureCurrentLocation(showSnackbars: true);
    if (pos == null) return false;

    if (!hasHomeLocationConfigured || requiresHomeReconfiguration) {
      if (!mounted) return false;
      final shouldSetup = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Set Up WFH Home Location'),
          content: const Text('Your WFH home location must be set up before you can check in or check out. Use your current location as your home location?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set Up')),
          ],
        ),
      );
      if (shouldSetup != true) return false;
      final ok = await _submitWfhHomeSetup(pos);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save your WFH home location.')));
        }
        return false;
      }
    }

    if (wfhGeofencingEnabled) {
      final distance = _distanceToWfhHomeMeters(pos);
      if (distance != null && distance > wfhRadiusInMeters) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are outside your allowed WFH home radius.')));
        }
        return false;
      }
    }

    userLocation = pos;
    return true;
  }

  Future<void> _doClockIn() async {
    if (!canCheckIn) return;

    await _refreshProofSettingsBeforePunch();
    if (!await _ensureWfhReady(isClockIn: true)) return;
    final requireLocation = locationEnabled || requiresLocationIn || _isWfhMode(inMode);
    final pos = requireLocation
        ? (userLocation ?? await _ensureCurrentLocation(showSnackbars: true))
        : userLocation;
    if (requireLocation && pos == null) return;

    final faceDetection = faceDetectionEnabled || requiresFaceReenrollment;

    if (faceDetection) {
      final launcher = widget.testOverrides?.launchFaceScanner;
      final result = launcher != null
          ? await launcher(
        context,
        isClockIn: true,
        userLocation: pos,
        userDetails: arguments,
      )
          : await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FaceScanner(
            userLocation: pos,
            userDetails: arguments,
            attendanceState: 'NOT_CHECKED_IN',
          ),
        ),
      );

      if (result is Map) {
        final bool didIn = result['checkedIn'] == true;
        final bool didOut = result['checkedOut'] == true;
        final bool shouldRefresh = result['refreshStatus'] == true;

        if (didIn || didOut || shouldRefresh) {
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
      return;
    }

    final res = await _postClock(isClockIn: true);
    if (res != null) {
      await refreshAttendanceStatus();
    }
  }

  Future<void> _doClockOut() async {
    if (!canCheckOut) return;

    await _refreshProofSettingsBeforePunch();
    if (!await _ensureWfhReady(isClockIn: false)) return;
    final requireLocation = locationEnabled || requiresLocationOut || _isWfhMode(outMode);
    final pos = requireLocation
        ? (userLocation ?? await _ensureCurrentLocation(showSnackbars: true))
        : userLocation;
    if (requireLocation && pos == null) return;

    final faceDetection = faceDetectionEnabled || requiresFaceReenrollment;

    if (faceDetection) {
      final launcher = widget.testOverrides?.launchFaceScanner;
      final result = launcher != null
          ? await launcher(
        context,
        isClockIn: false,
        userLocation: pos,
        userDetails: arguments,
      )
          : await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FaceScanner(
            userLocation: pos,
            userDetails: arguments,
            attendanceState: 'CHECKED_IN',
          ),
        ),
      );

      if (result is Map) {
        final bool didOut = result['checkedOut'] == true;
        final bool shouldRefresh = result['refreshStatus'] == true;
        if (didOut || shouldRefresh) {
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

  void _setProcessingDrag(bool value) {
    if (!mounted) {
      _isProcessingDrag = value;
      return;
    }

    setState(() {
      _isProcessingDrag = value;
    });
  }

  Future<void> _handleSwipeSubmit({required bool isClockIn}) async {
    if (_isProcessingDrag) return;

    final bool actionAllowed = isClockIn ? canCheckIn : canCheckOut;
    if (!actionAllowed) return;

    _setProcessingDrag(true);

    try {
      if (isClockIn) {
        await _doClockIn();
      } else {
        await _doClockOut();
      }
    } catch (e, stackTrace) {
      debugPrint('Swipe submit failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to complete attendance action. Please try again.'),
          ),
        );
      }
    } finally {
      _setProcessingDrag(false);
    }
  }

  Future<void> triggerAttendanceSwipeForTest({required bool isClockIn}) async {
    await _handleSwipeSubmit(isClockIn: isClockIn);
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
                Text('00:00', style: TextStyle(color: Colors.white)),
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
    final checkInText = _toHHMMFromAny(firstCheckIn) ?? '-';
    final checkOutText = _toHHMMFromAny(lastCheckOut) ?? '-';
    final note = _statusNote().trim();
    final detailNote = _statusDetailNote()?.trim() ?? '';

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
                  label: 'First Check In',
                  value: Text(checkInText,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                _headerStat(
                  label: 'Last Check Out',
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
                  key: const Key('attendance-header-note'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (detailNote.isNotEmpty) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    detailNote,
                    key: const Key('attendance-header-detail-note'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusErrorCard() {
    final message = _statusLoadErrorMessage?.trim();
    if (message == null || message.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Container(
        key: const Key('attendance-status-error-card'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.red.shade900, fontSize: 13),
              ),
            ),
            TextButton(
              key: const Key('attendance-status-retry-button'),
              onPressed: refreshAttendanceStatus,
              child: const Text('Retry'),
            ),
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
            label: 'Check In Proof',
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
            label: 'Check Out Proof',
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
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [tiles.first]),
        );
      } else {
        proofWidget = Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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

  String _resolveAttendanceDisabledTitle() {
    if (attendanceBlockedRoles.length > 1 || attendanceDisabledReasonCode == 'MULTIPLE_PRIVILEGED_ROLES') {
      return 'Attendance Disabled';
    }

    if (attendanceBlockedRoles.contains('ADMIN') || attendanceDisabledReasonCode == 'ADMIN') {
      return 'Admin Attendance Disabled';
    }

    if (attendanceBlockedRoles.contains('REPORTING_MANAGER') ||
        attendanceDisabledReasonCode == 'REPORTING_MANAGER') {
      return 'Reporting Manager Attendance Disabled';
    }

    return 'Attendance Disabled';
  }

  String _resolveAttendanceDisabledMessage({
    String? explicitMessage,
    String? reasonCode,
    List<String> blockedRoles = const [],
  }) {
    final trimmed = explicitMessage?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }

    if (blockedRoles.length > 1 || reasonCode == 'MULTIPLE_PRIVILEGED_ROLES') {
      return 'Attendance (Check In/Check Out) is disabled because one or more privileged roles assigned to your account are not allowed to attend.';
    }

    if (blockedRoles.contains('ADMIN') || reasonCode == 'ADMIN') {
      return 'Attendance (Check In/Check Out) is disabled for Admin users.';
    }

    if (blockedRoles.contains('REPORTING_MANAGER') || reasonCode == 'REPORTING_MANAGER') {
      return 'Attendance (Check In/Check Out) is disabled for Reporting Managers.';
    }

    return 'Attendance (Check In/Check Out) is disabled for your account.';
  }

  Widget _buildAttendanceDisabledBanner() {
    final msg = attendanceDisabledMessage?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.0),
          color: Colors.blueGrey.shade50,
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Colors.blueGrey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _resolveAttendanceDisabledTitle(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (msg == null || msg.isEmpty)
                        ? _resolveAttendanceDisabledMessage(
                      reasonCode: attendanceDisabledReasonCode,
                      blockedRoles: attendanceBlockedRoles,
                    )
                        : msg,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _swipeSide({required bool enabled, required IconData icon, required Color iconColor}) {
    final sideW = MediaQuery.of(context).size.width * 0.12;
    final sideH = MediaQuery.of(context).size.height * 0.06;

    if (!enabled) {
      // No arrow shown; keep spacing only.
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(width: sideW, height: sideH),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        width: sideW,
        height: sideH,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10.0), color: Colors.white),
        child: Icon(icon, color: iconColor, size: 30.0),
      ),
    );
  }

  Widget _buildSwipeAction() {
    // Show swipe only when an action is available.
    final inEnabled = canCheckIn;
    final outEnabled = canCheckOut;
    final anyEnabled = inEnabled || outEnabled;
    if (!anyEnabled) return const SizedBox.shrink();

    final label = _isProcessingDrag ? 'Processing attendance...' : swipeDirection;

    void handlePanUpdate(DragUpdateDetails details) {
      if (!anyEnabled || _isProcessingDrag) return;
      if (details.delta.dx.abs() <= details.delta.dy.abs() || details.delta.dx.abs() <= 10) return;

      if (details.delta.dx > 0) {
        if (inEnabled) {
          unawaited(_handleSwipeSubmit(isClockIn: true));
        }
      } else {
        if (outEnabled) {
          unawaited(_handleSwipeSubmit(isClockIn: false));
        }
      }
    }

    return AbsorbPointer(
      absorbing: _isProcessingDrag,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _isProcessingDrag ? 0.7 : 1,
        child: GestureDetector(
          onPanUpdate: anyEnabled && !_isProcessingDrag ? handlePanUpdate : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Container(
              key: const Key('attendance-swipe-action'),
              width: MediaQuery.of(context).size.width * 0.95,
              height: MediaQuery.of(context).size.height * 0.07,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.0),
                color: inEnabled ? Colors.green : (outEnabled ? Colors.red : Colors.grey),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _swipeSide(
                    enabled: inEnabled && !_isProcessingDrag,
                    icon: Icons.arrow_forward,
                    iconColor: Colors.green,
                  ),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isProcessingDrag) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              key: const Key('attendance-swipe-label'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.0,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _swipeSide(
                    enabled: outEnabled && !_isProcessingDrag,
                    icon: Icons.arrow_back,
                    iconColor: Colors.red,
                  ),
                ],
              ),
            ),
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
        _buildStatusErrorCard(),
        _buildEmployeeCard(),
        SizedBox(height: MediaQuery.of(context).size.height * 0.02),
        attendanceEnabled ? _buildSwipeAction() : _buildAttendanceDisabledBanner(),
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
      bottomNavigationBar: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        child: AnimatedNotchBottomBar(
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
