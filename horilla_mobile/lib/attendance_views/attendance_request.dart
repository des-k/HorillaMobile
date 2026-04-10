import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../res/utilities/permission_guard.dart';
import '../res/utilities/attendance_request_ui.dart';
import '../res/utilities/attachment_access.dart';
import 'work_mode_request.dart';
import 'package:horilla/res/widgets/authenticated_network_image.dart';

class AttendanceRequest extends StatefulWidget {
  const AttendanceRequest({super.key});

  @override
  _AttendanceRequest createState() => _AttendanceRequest();
}

class _AttendanceRequest extends State<AttendanceRequest>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, String> employeeIdMap = {};
  Map<String, String> shiftIdMap = {};
  Map<String, String> shiftNameById = {};
  Map<String, String> shiftTimeRangeById = {};
  Map<String, int> shiftFlexiMinutesById = {};
  final Map<String, Future<Map<String, String>>> _shiftFlexInfoFutureCache = {};

  Map<String, String> workTypeIdMap = {};
  List<Map<String, dynamic>> filteredRequestedAttendanceRecords = [];
  List<Map<String, dynamic>> filteredAllAttendanceRecords = [];
  List<Map<String, dynamic>> requestsAllRequestedAttendances = [];
  List<Map<String, dynamic>> requestsAllAttendances = [];
  List<Map<String, dynamic>> approvalHistoryAttendanceRecords = [];
  int approvalHistoryCount = 0;
  int approvalHistoryPage = 1;
  bool _loadingApprovalHistory = false;
  String approvalHistoryStatus = 'all';
  String approvalHistoryEmployeeId = '';
  late String approvalHistoryMonth = DateFormat('yyyy-MM').format(DateTime.now());
  String _myStatus = 'all';
  late String _myMonth = DateFormat('yyyy-MM').format(DateTime.now());
  List<Map<String, dynamic>> allEmployeeList = [];
  List<Map<String, dynamic>> approvalHistoryEmployeeOptions = [];
  List<String> shiftDetails = [];
  List<String> workTypeDetails = [];
  bool _validateEmployee = false;
  bool permissionCheck = false;
  bool _validateDate = false;
  bool _validateShift = false;
  bool _validateWorkType = false;
  String searchText = '';
  String workHoursSpent = '';
  String minimumHoursSpent = '';
  String checkInHoursSpent = '';
  String checkOutHoursSpent = '';
  // Shift/Flex info (for Attendance Correction Request UI)
  String? _createShiftInfo;
  String? _createFlexiIn;
  String? _createShiftStart;
  String? _createShiftEnd;
  String? _createCheckInWindowStart;
  String? _createCheckInWindowEnd;
  String? _createCheckOutWindowStart;
  String? _createCheckOutWindowEnd;
  String? _createCheckInCutoffTime;
  String? _createCheckOutCutoffTime;
  bool _loadingCreateShiftFlex = false;
  String? createShift;
  String? createWorkType;
  String? _errorMessage;
  String? _permissionStatusMessage;
  String? _attendanceDateServerError; // server-side validation message for Attendance Date
  String? selectedShiftId;
  String? selectedWorkTypeId;
  String? createEmployee;
  String? selectedEmployeeId;
  // Attendance correction scope: IN / OUT / FULL
  // Used only for the create-attendance request dialog.
  String _attendanceCorrectionScope = 'FULL';
  late String baseUrl = '';
  // Avoid LateInitializationError when user taps profile / create before prefetchData completes.
  Map<String, dynamic> arguments = {};
  var employeeItems = [''];
  final List<Widget> bottomBarPages = [];
  final TextEditingController _typeAheadCreateShiftController =
  TextEditingController();
  final TextEditingController _typeAheadCreateWorkTypeController =
  TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _requestedScrollController = ScrollController();
  final ScrollController _approvalHistoryScrollController = ScrollController();
  final ScrollController _allAttendanceScrollController = ScrollController();
  final GlobalKey<WorkModeRequestTabState> _workModeKey = GlobalKey<WorkModeRequestTabState>();
  final _controller = NotchBottomBarController(index: -1);
  final TextEditingController _typeAheadController = TextEditingController();
  TextEditingController attendanceDateController = TextEditingController();
  TextEditingController workedHoursController = TextEditingController();
  TextEditingController minimumHourController = TextEditingController();
  TextEditingController checkInHoursController = TextEditingController();
  TextEditingController checkoutHoursController = TextEditingController();
  TextEditingController checkOutDateController = TextEditingController();
  TextEditingController checkInDateController = TextEditingController();
  // Attachments (optional) for Attendance Correction Request
  List<PlatformFile> _attendancePickedFiles = [];
  int? _editingAttendanceRequestId;
  TextEditingController requestDescriptionController = TextEditingController();
  int requestedPage = 1;
  int attendancesPage = 1;
  int workModeRequestCount = 0;
  int? currentEmployeeId;
  bool canApproveAttendanceRequests = false;
  int maxCount = 5;
  int allRequestAttendance = 0;
  int myRequestAttendance = 0;
  bool isLoading = true;
  bool isAction = true;
  bool _validateCheckInDate = false;
  bool _validateCheckIn = false;
  bool _validateCheckoutDate = false;
  bool _validateCheckout = false;
  bool _validateWorkingHours = false;
  bool _validateMinimumHours = false;
  bool _validateReason = false;
  bool isSaveClick = true;
  bool permissionOverview = true;
  bool permissionAttendance = false;
  bool permissionAttendanceRequest = false;
  bool permissionHourAccount = false;
  Timer? _debounce;
  bool _notificationContextHandled = false;
  int? _notificationRequestId;

  bool _drawerPermissionOverview = false;
  bool _drawerPermissionAttendance = false;
  bool _drawerPermissionAttendanceRequest = false;
  bool _drawerPermissionHourAccount = false;
  bool _isPermissionCheckComplete = false;
  late String getToken = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notificationContextHandled) return;
    _notificationContextHandled = true;
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    if (routeArgs is! Map) return;
    final args = Map<String, dynamic>.from(routeArgs);
    final tab = (args['tab'] ?? '').toString().trim();
    _notificationRequestId = int.tryParse((args['request_id'] ?? '').toString());
    if (tab == 'work_mode_request') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabController.animateTo(1);
      });
    } else if (tab == 'attendance_request') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabController.animateTo(0);
      });
    }
    if (_notificationRequestId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened request #$_notificationRequestId from notification.')),
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    prefetchData();
    _requestedScrollController.addListener(_requestedScrollListener);
    _approvalHistoryScrollController.addListener(_approvalHistoryScrollListener);
    getAllRequestedAttendances(reset: true);
    prefetchWorkTypeRequestCounts();
    getBaseUrl();
    getEmployees();
    getShiftDetails();
    getShiftScheduleRanges();
    getWorkTypeDetails();
    loadPermissionsFromStorage();
    fetchToken();
    loadCurrentEmployeeId();
    permissionChecks();
  }

  Future<void> prefetchWorkTypeRequestCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      final typedServerUrl = prefs.getString("typed_url");

      if (token == null || token.isEmpty) return;
      if (typedServerUrl == null || typedServerUrl.isEmpty) return;

      final headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      };

      final myUri = Uri.parse(
          "$typedServerUrl/api/attendance/work-type-request/?mine=1&page=1");
      final approvalsUri = Uri.parse(
          "$typedServerUrl/api/attendance/work-type-request-approvals/?queue=all&page=1");

      final responses = await Future.wait([
        http.get(myUri, headers: headers),
        http.get(approvalsUri, headers: headers),
      ]);

      int myCount = 0;
      int approvalsCount = 0;

      if (responses[0].statusCode == 200) {
        final body = jsonDecode(responses[0].body);
        myCount = body["count"] ?? 0;
      }

      if (responses[1].statusCode == 200) {
        final body = jsonDecode(responses[1].body);
        approvalsCount = body["count"] ?? 0;
      } else if (responses[1].statusCode == 403) {
        approvalsCount = 0;
      }

      if (!mounted) return;
      setState(() {
        workModeRequestCount = myCount + approvalsCount;
      });
    } catch (_) {
      // ignore prefetch errors
    }
  }

  Future loadPermissionsFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _drawerPermissionOverview = prefs.getBool("perm_overview") ?? false;
      _drawerPermissionAttendance = prefs.getBool("perm_attendance") ?? false;
      _drawerPermissionAttendanceRequest =
          prefs.getBool("perm_attendance_request") ?? false;
      _drawerPermissionHourAccount =
          prefs.getBool("perm_hour_account") ?? false;
      _isPermissionCheckComplete = true;
    });
  }

  Future<void> fetchToken() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    setState(() {
      getToken = token ?? '';
    });
  }

  Future<void> _simulateLoading() async {
    await Future.delayed(const Duration(seconds: 5));
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _requestedScrollController.removeListener(_requestedScrollListener);
    _requestedScrollController.dispose();
    _approvalHistoryScrollController.removeListener(_approvalHistoryScrollListener);
    _approvalHistoryScrollController.dispose();
    _allAttendanceScrollController.removeListener(_allAttendanceScrollListener);
    _allAttendanceScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
  void _requestedScrollListener() {
    if (_requestedScrollController.position.pixels >=
        _requestedScrollController.position.maxScrollExtent - 60 &&
        !_requestedScrollController.position.outOfRange) {
      // Stop if all pages are loaded
      if (allRequestAttendance != 0 &&
          requestsAllRequestedAttendances.length >= allRequestAttendance) return;
      requestedPage++;
      getAllRequestedAttendances();
    }
  }

  void _approvalHistoryScrollListener() {
    if (_approvalHistoryScrollController.position.pixels >=
        _approvalHistoryScrollController.position.maxScrollExtent - 60 &&
        !_approvalHistoryScrollController.position.outOfRange) {
      if (approvalHistoryCount != 0 &&
          approvalHistoryAttendanceRecords.length >= approvalHistoryCount) return;
      approvalHistoryPage++;
      getApprovalHistoryAttendances();
    }
  }

  void _allAttendanceScrollListener() {
    if (_allAttendanceScrollController.position.pixels >=
        _allAttendanceScrollController.position.maxScrollExtent - 60 &&
        !_allAttendanceScrollController.position.outOfRange) {
      attendancesPage++;
      getAllAttendances();
    }
  }

  void showCreateAnimation() {
    String jsonContent = '''
{
  "imagePath": "Assets/gif22.gif"
}
''';
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    String imagePath = jsonData['imagePath'];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(imagePath),
                    const SizedBox(height: 16),
                    const Text(
                      "Attendance Created Successfully",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pop();
    });
  }

  void showValidateAnimation() {
    String jsonContent = '''
{
  "imagePath": "Assets/gif22.gif"
}
''';
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    String imagePath = jsonData['imagePath'];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(imagePath),
                    const SizedBox(height: 16),
                    const Text(
                      "Attendance Approved Successfully",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pop();
    });
  }

  void showRejectAnimation() {
    String jsonContent = '''
{
  "imagePath": "Assets/gif22.gif"
}
''';
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    String imagePath = jsonData['imagePath'];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(imagePath),
                    const SizedBox(height: 16),
                    const Text(
                      "Attendance Rejected Successfully",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pop();
    });
  }

  void showCancelAnimation() {
    String jsonContent = '''
{
  "imagePath": "Assets/gif22.gif"
}
''';
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    String imagePath = jsonData['imagePath'];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            width: MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(imagePath),
                    const SizedBox(height: 16),
                    const Text(
                      "Request Canceled Successfully",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pop();
    });
  }

  Future<void> getEmployees() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");

    employeeItems.clear();
    employeeIdMap.clear();
    allEmployeeList.clear();

    for (var page = 1;; page++) {
      var uri = Uri.parse(
        '$typedServerUrl/api/employee/employee-selector?page=$page',
      );

      var response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = List<Map<String, dynamic>>.from(data['results']);

        if (results.isEmpty) break; // ✅ Stop if there are no more employees

        setState(() {
          for (var employee in results) {
            final firstName = employee['employee_first_name'] ?? '';
            final lastName = employee['employee_last_name'] ?? '';
            final fullName = '$firstName $lastName'.trim();
            final employeeId = "${employee['id']}";

            employeeItems.add(fullName);
            employeeIdMap[fullName] = employeeId;
          }

          allEmployeeList.addAll(results);
        });
      } else {
        print('Error fetching employees (status: ${response.statusCode})');
        break;
      }
    }
  }

  Future<void> getShiftDetails() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/base/employee-shift/');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      setState(() {
        for (var rec in jsonDecode(response.body)) {
          String shift = "${rec['employee_shift']}";
          String employeeId = "${rec['id']}";
          shiftDetails.add(rec['employee_shift']);
          shiftIdMap[shift] = employeeId;
          shiftNameById[employeeId] = shift;
        }
      });
    }
  }

  Future<void> getShiftScheduleRanges() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");
    if (typedServerUrl == null || typedServerUrl.isEmpty) return;

    final uri = Uri.parse('$typedServerUrl/api/base/employee-shift-schedules/');
    try {
      final response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is! List) return;

        // Count occurrences of (start,end,night) per shift_id.
        final Map<String, Map<String, int>> counts = {};
        for (final item in decoded) {
          if (item is! Map) continue;
          final sid = _idOf(item['shift_id'] ?? item['employee_shift_id'] ?? item['employee_shift'] ?? item['shift']);
          if (sid == null) continue;
          final stRaw = (item['start_time'] ?? item['shift_start_time'] ?? item['shift_start'] ?? item['shift_start_hhmm'])?.toString();
          final enRaw = (item['end_time'] ?? item['shift_end_time'] ?? item['shift_end'] ?? item['shift_end_hhmm'])?.toString();
          if (stRaw == null || enRaw == null) continue;

          final st = stRaw.length >= 5 ? stRaw.substring(0, 5) : stRaw;
          final en = enRaw.length >= 5 ? enRaw.substring(0, 5) : enRaw;

          final graceMin = _graceToMinutes(
              item['grace_time'] ?? item['grace'] ?? item['grace_allowed'] ?? item['allowed_grace'] ?? item['flexi_in'] ?? item['flexi'] ?? item['grace_in']);
          final graceKey = (graceMin ?? 0).toString();

          bool night = false;
          final nightVal = item['is_night_shift'] ?? item['night_shift'] ?? item['is_night'] ?? item['cross_midnight'];
          if (nightVal == true || nightVal == 1 || nightVal == '1') night = true;
          // Safety: if end < start, treat as crossing midnight.
          if (!night && _hhmmToMinutes(en) < _hhmmToMinutes(st)) night = true;

          final key = '$st|$en|$night|$graceKey';
          counts.putIfAbsent(sid, () => {});
          counts[sid]![key] = (counts[sid]![key] ?? 0) + 1;
        }

        if (!mounted) return;
        setState(() {
          for (final entry in counts.entries) {
            final sid = entry.key;
            final best = entry.value.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
            final parts = best.split('|');
            if (parts.length < 2) continue;
            final st = parts[0];
            final en = parts[1];
            final night = parts.length > 2 && parts[2] == 'true';
            final graceStr = parts.length > 3 ? parts[3] : '0';
            shiftTimeRangeById[sid] =
            night ? '$st - $en (next day)' : '$st - $en';
            shiftFlexiMinutesById[sid] = int.tryParse(graceStr) ?? 0;
          }
        });
      }
    } catch (_) {
      // Ignore network/permission errors; UI will fallback to shift name.
      return;
    }
  }

  Future<void> getWorkTypeDetails() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/base/worktypes');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      setState(() {
        for (var rec in jsonDecode(response.body)) {
          String workType = "${rec['work_type']}";
          String workTypeId = "${rec['id']}";
          workTypeDetails.add(rec['work_type']);
          workTypeIdMap[workType] = workTypeId;
        }
      });
    }
  }

  Future<void> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    setState(() {
      baseUrl = typedServerUrl ?? '';
    });
  }

  Future<String?> showCustomDatePicker(
      BuildContext context, DateTime initialDate) async {
    // Attendance Correction Request: only allow selecting yesterday or earlier.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(2000);
    DateTime lastDate = today.subtract(const Duration(days: 1));
    if (lastDate.isBefore(firstDate)) lastDate = firstDate;

    DateTime safeInitial = initialDate;
    if (safeInitial.isAfter(lastDate)) safeInitial = lastDate;
    if (safeInitial.isBefore(firstDate)) safeInitial = firstDate;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDate != null) {
      return DateFormat('yyyy-MM-dd').format(selectedDate);
    }
    return null;
  }

  // --- Helpers for Attendance Correction Request UI ---
  String _normalizeTimeHHMM(String v) {
    final s = v.trim();
    if (s.isEmpty) return '00:00';
    String hh = '00';
    String mm = '00';
    if (s.contains(':')) {
      final parts = s.split(':');
      if (parts.isNotEmpty) hh = parts[0].padLeft(2, '0');
      if (parts.length > 1) mm = parts[1].padRight(2, '0').substring(0, 2);
    } else if (s.length >= 3) {
      // Accept HHMM (e.g., 0830)
      final raw = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (raw.length >= 4) {
        hh = raw.substring(0, 2);
        mm = raw.substring(2, 4);
      }
    }
    final h = int.tryParse(hh) ?? 0;
    final m = int.tryParse(mm) ?? 0;
    if (h < 0 || h > 23 || m < 0 || m > 59) return '00:00';
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  int _hhmmToMinutes(String hhmm) {
    final norm = _normalizeTimeHHMM(hhmm);
    final parts = norm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  String _minutesToHHMM(int minutes) {
    minutes = minutes % (24 * 60);
    if (minutes < 0) minutes += 24 * 60;
    // Integer division in Dart uses ~/ (not //).
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _calcWorkedHHMM({required String inTime, required String outTime}) {
    final inMin = _hhmmToMinutes(inTime);
    final outMin = _hhmmToMinutes(outTime);
    var diff = outMin - inMin;
    // If negative, assume over-midnight (e.g., 22:00 -> 06:00)
    if (diff < 0) diff += 24 * 60;
    return _minutesToHHMM(diff);
  }

  // --- Shift + Flexi In info (reuse from Check In / Check Out screen) ---
  String? _toHHMMFromAny(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'null' || lower == 'none') return null;

    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m != null) {
      final hh = (m.group(1) ?? '0').padLeft(2, '0');
      final mm = (m.group(2) ?? '0').padLeft(2, '0');
      return '$hh:$mm';
    }

    final n = int.tryParse(s);
    if (n != null) {
      // Heuristic: small numbers are minutes; large numbers may be seconds.
      final int minutes = n > 24 * 60 * 2 ? (n / 60).round() : n;
      final h = minutes ~/ 60;
      final mm = minutes % 60;
      return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
    }

    return null;
  }

  int? _graceToMinutes(dynamic raw) {
    final hhmm = _toHHMMFromAny(raw);
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  String _flexMinutesDisplay(int? minutes) {
    if (minutes == null) return '—';
    return '${minutes}m';
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

  String _clockInTypeSymbol(String? raw) {
    switch (_normalizeClockInType(raw)) {
      case 'before_after':
        return '±';
      case 'after':
        return '+';
      default:
        return '';
    }
  }

  String _flexMinutesDisplayWithMode(int? minutes, {String? clockInType}) {
    final flex = _flexMinutesDisplay(minutes);
    final symbol = _clockInTypeSymbol(clockInType);
    if (flex == '—' || symbol.isEmpty) return flex;
    return '$symbol$flex';
  }

  String? _employeeIdForRecord(Map<String, dynamic> record) {
    return _idOf(record['employee_id']) ??
        _idOf(record['employee']) ??
        _cleanValue(record['employee_id']) ??
        _cleanValue(record['employee']);
  }

  String _shiftFlexCacheKeyForRecord(Map<String, dynamic> record) {
    final employeeId = _employeeIdForRecord(record) ?? '';
    final attendanceDate = _cleanValue(record['attendance_date']) ?? '';
    return '$employeeId|$attendanceDate';
  }

  Future<Map<String, String>> _resolvedShiftFlexInfoForRecord(Map<String, dynamic> record) {
    final key = _shiftFlexCacheKeyForRecord(record);
    return _shiftFlexInfoFutureCache.putIfAbsent(key, () async {
      final localShift = (_shiftTimeOnlyForRecord(record) ?? _shiftDisplayForRecord(record)) ?? '—';
      final localFlex = _flexMinutesDisplayWithMode(
        _flexiMinutesForRecord(record),
        clockInType: (record['clock_in_type'] ??
                record['grace_clock_in_type'] ??
                record['grace_type'])
            ?.toString(),
      );

      final employeeId = _employeeIdForRecord(record);
      final attendanceDate = _cleanValue(record['attendance_date']);
      if ((employeeId == null || employeeId.isEmpty) ||
          (attendanceDate == null || attendanceDate.isEmpty)) {
        return {'shift': localShift, 'flexi': localFlex};
      }

      final shiftFlex = await _fetchShiftFlexInfo(
        employeeId: employeeId,
        date: attendanceDate,
      );
      final fetchedShift = _cleanValue(shiftFlex['shift']);
      final fetchedFlex = _cleanValue(shiftFlex['flexi']);
      return {
        'shift': fetchedShift ?? localShift,
        'flexi': fetchedFlex ?? localFlex,
      };
    });
  }

  Future<Map<String, String>> _fetchShiftFlexInfo({String? employeeId, String? date}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    if (token == null || typedServerUrl == null) {
      return {
        'shift': '—',
        'flexi': '—',
        'clock_in_type': '',
        'shift_start': '',
        'shift_end': '',
        'check_in_window_start': '',
        'check_in_window_end': '',
        'check_out_window_start': '',
        'check_out_window_end': '',
        'check_in_cutoff_time': '',
        'check_out_cutoff_time': '',
      };
    }

    String buildUri({required bool includeEmployee}) {
      final parts = <String>[];
      final d = (date ?? '').trim();
      if (d.isNotEmpty) {
        parts.add('date=$d');
        parts.add('attendance_date=$d');
      }
      final eid = (employeeId ?? '').trim();
      if (includeEmployee && eid.isNotEmpty) {
        parts.add('employee_id=$eid');
      }
      final qs = parts.isEmpty ? '' : '?' + parts.join('&');
      return '$typedServerUrl/api/attendance/checking-in$qs';
    }

    Future<http.Response> doGet(String u) async {
      final uri = Uri.parse(u);
      return http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
    }

    http.Response resp;
    try {
      resp = await doGet(buildUri(includeEmployee: true));
      if (resp.statusCode != 200 && (employeeId ?? '').trim().isNotEmpty) {
        resp = await doGet(buildUri(includeEmployee: false));
      }
    } catch (_) {
      return {
        'shift': '—',
        'flexi': '—',
        'clock_in_type': '',
        'shift_start': '',
        'shift_end': '',
        'check_in_window_start': '',
        'check_in_window_end': '',
        'check_out_window_start': '',
        'check_out_window_end': '',
        'check_in_cutoff_time': '',
        'check_out_cutoff_time': '',
      };
    }

    if (resp.statusCode != 200) {
      return {
        'shift': '—',
        'flexi': '—',
        'clock_in_type': '',
        'shift_start': '',
        'shift_end': '',
        'check_in_window_start': '',
        'check_in_window_end': '',
        'check_out_window_start': '',
        'check_out_window_end': '',
        'check_in_cutoff_time': '',
        'check_out_cutoff_time': '',
      };
    }

    try {
      final data = jsonDecode(resp.body);
      if (data is! Map) {
        return {
          'shift': '—',
          'flexi': '—',
          'clock_in_type': '',
          'shift_start': '',
          'shift_end': '',
          'check_in_window_start': '',
          'check_in_window_end': '',
          'check_out_window_start': '',
          'check_out_window_end': '',
          'check_in_cutoff_time': '',
          'check_out_cutoff_time': '',
        };
      }

      final start = _toHHMMFromAny(
          data['shift_start'] ?? data['shift_start_time'] ?? data['shift_start_hhmm']);
      final end = _toHHMMFromAny(
          data['shift_end'] ?? data['shift_end_time'] ?? data['shift_end_hhmm']);

      final graceMin = _graceToMinutes(
          data['grace_time'] ?? data['grace'] ?? data['grace_allowed'] ?? data['allowed_grace']);
      final clockInType = _normalizeClockInType(
          (data['clock_in_type'] ?? data['grace_clock_in_type'] ?? data['grace_type'])?.toString());

      final shiftName = (data['shift_name'] ?? data['employee_shift'] ?? data['shift'] ?? '')
          .toString()
          .trim();

      final checkInWindowStart = _toHHMMFromAny(
          data['check_in_window_start'] ?? data['checkin_window_start'] ?? data['check_in_start']);
      final checkInWindowEnd = _toHHMMFromAny(
          data['check_in_window_end'] ?? data['checkin_window_end'] ?? data['check_in_end']);
      final checkOutWindowStart = _toHHMMFromAny(
          data['check_out_window_start'] ?? data['checkout_window_start'] ?? data['check_out_start']);
      final checkOutWindowEnd = _toHHMMFromAny(
          data['check_out_window_end'] ?? data['checkout_window_end'] ?? data['check_out_end']);
      final checkInCutoff = _toHHMMFromAny(
          data['check_in_cutoff_time'] ?? data['cutoff_in'] ?? data['check_in_cutoff']);
      final checkOutCutoff = _toHHMMFromAny(
          data['check_out_cutoff_time'] ?? data['cutoff_out'] ?? data['check_out_cutoff']);

      final bool noSchedule =
          start == null || end == null || (start == '00:00' && end == '00:00');
      if (noSchedule) {
        return {
          'shift': '-',
          'flexi': '-',
          'clock_in_type': '',
          'shift_start': '',
          'shift_end': '',
          'check_in_window_start': '',
          'check_in_window_end': '',
          'check_out_window_start': '',
          'check_out_window_end': '',
          'check_in_cutoff_time': '',
          'check_out_cutoff_time': '',
        };
      }

      String? shiftInfo;
      if (start != null && end != null) {
        shiftInfo = '$start - $end';
      }
      if (shiftInfo == null && shiftName.isNotEmpty) {
        shiftInfo = shiftName;
      }

      return {
        'shift': shiftInfo ?? '—',
        'flexi': _flexMinutesDisplayWithMode(graceMin, clockInType: clockInType),
        'clock_in_type': clockInType ?? '',
        'shift_start': start ?? '',
        'shift_end': end ?? '',
        'check_in_window_start': checkInWindowStart ?? '',
        'check_in_window_end': checkInWindowEnd ?? '',
        'check_out_window_start': checkOutWindowStart ?? '',
        'check_out_window_end': checkOutWindowEnd ?? '',
        'check_in_cutoff_time': checkInCutoff ?? '',
        'check_out_cutoff_time': checkOutCutoff ?? '',
      };
    } catch (_) {
      return {
        'shift': '—',
        'flexi': '—',
        'clock_in_type': '',
        'shift_start': '',
        'shift_end': '',
        'check_in_window_start': '',
        'check_in_window_end': '',
        'check_out_window_start': '',
        'check_out_window_end': '',
        'check_in_cutoff_time': '',
        'check_out_cutoff_time': '',
      };
    }
  }

  bool _isCreateShiftUnavailable(String? shiftInfo) {
    final value = (shiftInfo ?? '').trim().toLowerCase();
    return value == '-' ||
        value == '—' ||
        value == 'no schedule' ||
        value == 'holiday' ||
        value == 'no shift';
  }

  Future<void> _refreshCreateShiftFlex(StateSetter dialogSetState) async {
    final date = attendanceDateController.text.trim();
    final eid = (selectedEmployeeId ?? '').trim();
    if (date.isEmpty || eid.isEmpty) {
      dialogSetState(() {
        _createShiftInfo = null;
        _createFlexiIn = null;
        _createShiftStart = null;
        _createShiftEnd = null;
        _createCheckInWindowStart = null;
        _createCheckInWindowEnd = null;
        _createCheckOutWindowStart = null;
        _createCheckOutWindowEnd = null;
        _createCheckInCutoffTime = null;
        _createCheckOutCutoffTime = null;
        _loadingCreateShiftFlex = false;
      });
      return;
    }

    dialogSetState(() {
      _loadingCreateShiftFlex = true;
    });

    final info = await _fetchShiftFlexInfo(employeeId: eid, date: date);
    dialogSetState(() {
      _createShiftInfo = info['shift'];
      _createFlexiIn = info['flexi'];
      _createShiftStart = info['shift_start'];
      _createShiftEnd = info['shift_end'];
      _createCheckInWindowStart = info['check_in_window_start'];
      _createCheckInWindowEnd = info['check_in_window_end'];
      _createCheckOutWindowStart = info['check_out_window_start'];
      _createCheckOutWindowEnd = info['check_out_window_end'];
      _createCheckInCutoffTime = info['check_in_cutoff_time'];
      _createCheckOutCutoffTime = info['check_out_cutoff_time'];
      _loadingCreateShiftFlex = false;
    });
  }

  Future<void> _loadCreateShiftFlexForDate() async {
    final date = attendanceDateController.text.trim();
    final eid = (selectedEmployeeId ?? '').trim();
    if (date.isEmpty || eid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _createShiftInfo = null;
        _createFlexiIn = null;
        _createShiftStart = null;
        _createShiftEnd = null;
        _createCheckInWindowStart = null;
        _createCheckInWindowEnd = null;
        _createCheckOutWindowStart = null;
        _createCheckOutWindowEnd = null;
        _createCheckInCutoffTime = null;
        _createCheckOutCutoffTime = null;
        _loadingCreateShiftFlex = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loadingCreateShiftFlex = true;
    });

    final info = await _fetchShiftFlexInfo(employeeId: eid, date: date);
    if (!mounted) return;
    setState(() {
      _createShiftInfo = info['shift'];
      _createFlexiIn = info['flexi'];
      _createShiftStart = info['shift_start'];
      _createShiftEnd = info['shift_end'];
      _createCheckInWindowStart = info['check_in_window_start'];
      _createCheckInWindowEnd = info['check_in_window_end'];
      _createCheckOutWindowStart = info['check_out_window_start'];
      _createCheckOutWindowEnd = info['check_out_window_end'];
      _createCheckInCutoffTime = info['check_in_cutoff_time'];
      _createCheckOutCutoffTime = info['check_out_cutoff_time'];
      _loadingCreateShiftFlex = false;
    });
  }

  bool _hasValue(String? v) {
    if (v == null) return false;
    final s = v.toString().trim();
    if (s.isEmpty) return false;
    return s.toLowerCase() != 'null';
  }

  DateTime? _parseCreateApiDateTime(String? raw, DateTime baseDate) {
    if (!_hasValue(raw)) return null;
    var s = raw!.trim();
    if (!s.contains('T') && s.contains('.') && !s.contains(':') && RegExp(r'^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$').hasMatch(s)) {
      s = s.replaceAll('.', ':');
    }
    if (s.contains('T')) {
      try {
        final dt = DateTime.parse(s).toLocal();
        return DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
      } catch (_) {}
    }
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final hh = int.tryParse(parts[0]) ?? 0;
    final mm = int.tryParse(parts[1]) ?? 0;
    return DateTime(baseDate.year, baseDate.month, baseDate.day, hh, mm);
  }

  DateTime? _adjustForNightShift(DateTime? value, DateTime? shiftStartDt, bool isNightShift) {
    if (value == null) return null;
    if (isNightShift && shiftStartDt != null && value.isBefore(shiftStartDt)) {
      return value.add(const Duration(days: 1));
    }
    return value;
  }

  String? _validateCreateTimeAgainstWindow({
    required String session,
    required String selectedTime,
    required String attendanceDate,
  }) {
    final base = DateTime.tryParse(attendanceDate);
    if (base == null) return null;
    final baseDate = DateTime(base.year, base.month, base.day);

    final shiftStartDt = _parseCreateApiDateTime(_createShiftStart, baseDate);
    final shiftEndDt = _parseCreateApiDateTime(_createShiftEnd, baseDate);
    final bool isNightShift = shiftStartDt != null && shiftEndDt != null && shiftEndDt.isBefore(shiftStartDt);

    final bool isIn = session.toUpperCase() == 'IN';
    final String? configuredStartRaw = isIn
        ? (_hasValue(_createCheckInWindowStart) ? _createCheckInWindowStart : _createShiftStart)
        : (_hasValue(_createCheckOutWindowStart) ? _createCheckOutWindowStart : _createShiftEnd);
    final String? configuredEndRaw = isIn
        ? (_hasValue(_createCheckInWindowEnd) ? _createCheckInWindowEnd : _createCheckInCutoffTime)
        : (_hasValue(_createCheckOutWindowEnd) ? _createCheckOutWindowEnd : _createCheckOutCutoffTime);

    if (!_hasValue(configuredStartRaw) || !_hasValue(configuredEndRaw)) {
      return isIn
          ? 'Check In Time is not allowed because no check-in window is configured for the selected date/shift.'
          : 'Check Out Time is not allowed because no check-out window is configured for the selected date/shift.';
    }

    final winStart = _adjustForNightShift(
      _parseCreateApiDateTime(configuredStartRaw, baseDate),
      shiftStartDt,
      isNightShift,
    );
    final winEnd = _adjustForNightShift(
      _parseCreateApiDateTime(configuredEndRaw, baseDate),
      shiftStartDt,
      isNightShift,
    );
    var candidate = _parseCreateApiDateTime(selectedTime, baseDate);
    candidate = _adjustForNightShift(candidate, shiftStartDt, isNightShift);

    if (winStart == null || winEnd == null || candidate == null) return null;

    if (candidate.isBefore(winStart) || candidate.isAfter(winEnd)) {
      final label = isIn ? 'Check In' : 'Check Out';
      final range = '${DateFormat('HH:mm').format(winStart)} - ${DateFormat('HH:mm').format(winEnd)}';
      return '$label Time must be within $range.';
    }
    return null;
  }

  static const int _maxAttachmentBytes = 20 * 1024 * 1024;
  static const Set<String> _allowedAttachmentExts = {
    'pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'
  };

  String? _validatePickedFiles(List<PlatformFile> files) {
    for (final f in files) {
      final name = (f.name).trim();
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (!_allowedAttachmentExts.contains(ext)) {
        return 'File type .$ext is not allowed. Allowed: PDF, JPG, JPEG, PNG, DOC, DOCX.';
      }
      if (f.size > _maxAttachmentBytes) {
        return 'File ${name.isEmpty ? 'attachment' : name} is too large. Max 20 MB per file.';
      }
    }
    return null;
  }

  Widget _kvBlock(String k, String v, {double bottom = 10}) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          const SizedBox(height: 4),
          Text(v, style: const TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }

  List<MobileAttachmentItem> _attachmentEntriesForRecord(Map<String, dynamic> record) {
    return extractMobileAttachments(
      record,
      baseUrl: baseUrl,
      includeRequestedData: true,
    );
  }

  Future<void> _deleteAttendanceAttachment(MobileAttachmentItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null || token.trim().isEmpty) {
        throw Exception('Missing authentication token');
      }
      final deleteTarget = item.deleteUrl.trim().isNotEmpty
          ? item.deleteUrl
          : item.downloadUrl.trim().isNotEmpty
          ? item.downloadUrl
          : item.legacyUrl;
      final resolvedUrl = absoluteAttachmentUrl(baseUrl, deleteTarget);
      if (resolvedUrl.isEmpty) {
        throw Exception('Attachment delete URL is missing');
      }
      final uri = Uri.parse(resolvedUrl);
      final resp = await http.delete(uri, headers: {
        'Authorization': 'Bearer $token',
      });
      if (resp.statusCode != 204 && resp.statusCode != 200) {
        String msg = 'Failed to delete attachment.';
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map && decoded['error'] != null) {
            msg = decoded['error'].toString();
          }
        } catch (_) {}
        throw Exception(msg);
      }
      await getAllRequestedAttendances(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete attachment: $e')),
      );
    }
  }

  Future<void> _openEmployeePickerBottomSheet(
      BuildContext dialogContext,
      StateSetter dialogSetState,
      ) async {
    final selectedName = await showModalBottomSheet<String>(
      context: dialogContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final searchCtrl = TextEditingController();
        var filtered = List<String>.from(employeeItems);

        void applyFilter(String q, StateSetter ss) {
          final qq = q.trim().toLowerCase();
          ss(() {
            if (qq.isEmpty) {
              filtered = List<String>.from(employeeItems);
            } else {
              filtered = employeeItems
                  .where((e) => e.toLowerCase().contains(qq))
                  .toList();
            }
          });
        }

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 12 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(sheetContext).size.height * 0.75,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Select Employee',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search employee',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => applyFilter(v, setSheetState),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('No employees found'))
                            : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final name = filtered[i];
                            return ListTile(
                              title: Text(name, maxLines: 2),
                              onTap: () =>
                                  Navigator.of(sheetContext).pop(name),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedName == null || selectedName.trim().isEmpty) return;

    dialogSetState(() {
      createEmployee = selectedName;
      selectedEmployeeId = employeeIdMap[selectedName];
      _typeAheadController.text = selectedName;
      _validateEmployee = false;
    });
  }

  void _setCreateEmployeeToSelf() {
    final rawId = arguments['employee_id'];
    final selfId = (rawId ?? currentEmployeeId ?? '').toString();
    final first = (arguments['employee_name'] ?? '').toString().trim();
    if (selfId.isNotEmpty) {
      selectedEmployeeId = selfId;
    }
    if (first.isNotEmpty) {
      createEmployee = first;
      _typeAheadController.text = first;
    }
    _validateEmployee = false;
  }

  void showCreateRequestBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined, color: Colors.red),
                title: const Text('Attendance Correction Request'),
                subtitle: const Text('Request to create/update attendance clock-in/out'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // Attendance Correction Request is self-only (same as web/backend).
                  _setCreateEmployeeToSelf();
                  setState(() {
                    _editingAttendanceRequestId = null;
                    isSaveClick = true;
                    _attendanceCorrectionScope = 'FULL';
                    _errorMessage = null;
                    _attendanceDateServerError = null;
                    createShift = null;
                    createWorkType = null;
                    isAction = false;
                    _validateDate = false;
                    _validateShift = false;
                    _validateCheckInDate = false;
                    _validateCheckIn = false;
                    _validateCheckoutDate = false;
                    _validateCheckout = false;
                    _validateWorkingHours = false;
                    _validateMinimumHours = false;
                    _validateReason = false;
                    attendanceDateController.clear();
                    _typeAheadCreateShiftController.clear();
                    _typeAheadCreateWorkTypeController.clear();
                    checkInDateController.clear();
                    checkInHoursController.clear();
                    checkOutDateController.clear();
                    checkoutHoursController.clear();
                    workedHoursController.clear();
                    minimumHourController.clear();
                    requestDescriptionController.clear();
                    _attendancePickedFiles = [];
                    _createShiftInfo = null;
                    _createFlexiIn = null;
                    _createShiftStart = null;
                    _createShiftEnd = null;
                    _createCheckInWindowStart = null;
                    _createCheckInWindowEnd = null;
                    _createCheckOutWindowStart = null;
                    _createCheckOutWindowEnd = null;
                    _createCheckInCutoffTime = null;
                    _createCheckOutCutoffTime = null;
                    _loadingCreateShiftFlex = false;

                  });
                  showCreateAttendanceDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.work_outline, color: Colors.red),
                title: const Text('Work Type Request'),
                subtitle: const Text('WFA / WFH / ON DUTY (approval workflow)'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _openWorkTypeRequestDialogFromMenu();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void showCreateAttendanceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            final bool needsIn = _attendanceCorrectionScope != 'OUT';
            final bool needsOut = _attendanceCorrectionScope != 'IN';
            final bool hasEmployeeAndDate =
                (selectedEmployeeId ?? '').trim().isNotEmpty &&
                    attendanceDateController.text.trim().isNotEmpty;
            final bool disableSaveForNoShift =
                hasEmployeeAndDate &&
                    !_loadingCreateShiftFlex &&
                    _isCreateShiftUnavailable(_createShiftInfo);
            final bool disableSaveButton =
                isAction || _loadingCreateShiftFlex || disableSaveForNoShift;

            Widget scopeChip(String label, String value) {
              final selected = _attendanceCorrectionScope == value;
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _attendanceCorrectionScope = value;
                    // Clear validators for hidden fields
                    if (value == 'IN') {
                      checkoutHoursController.clear();
                      checkOutHoursSpent = '';
                      _validateCheckout = false;
                      _validateCheckoutDate = false;
                    } else if (value == 'OUT') {
                      checkInHoursController.clear();
                      checkInHoursSpent = '';
                      _validateCheckIn = false;
                      _validateCheckInDate = false;
                    }
                  });
                },
              );
            }

            return Stack(
              children: [
                AlertDialog(
                  backgroundColor: Colors.white,
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Attendance Correction Request",
                          maxLines: 3,
                          softWrap: true,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    width: MediaQuery.of(context).size.width * 0.95,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _errorMessage ?? '',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                          const SizedBox(height: 4),

                          // Attendance date
                          const Text('Attendance Date', style: TextStyle(color: Colors.black)),
                          const SizedBox(height: 8),
                          TextField(
                            readOnly: true,
                            controller: attendanceDateController,
                            onTap: () async {
                              final selectedDate = await showCustomDatePicker(context, DateTime.now());
                              if (selectedDate != null) {
                                final parsedDate = DateFormat('yyyy-MM-dd').parse(selectedDate);
                                final v = DateFormat('yyyy-MM-dd').format(parsedDate);
                                setState(() {
                                  attendanceDateController.text = v;
                                  // Per-hari: set clock-in/out dates same as attendance date
                                  checkInDateController.text = v;
                                  checkOutDateController.text = v;
                                  _validateDate = false;
                                  _validateCheckInDate = false;
                                  _validateCheckoutDate = false;
                                });
                                await _refreshCreateShiftFlex(setState);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Attendance Date',
                              labelStyle: TextStyle(color: Colors.grey[350]),
                              border: const OutlineInputBorder(),
                              errorText: _attendanceDateServerError ?? (_validateDate ? 'Please select an Attendance date' : null),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10.0),
                            ),
                          ),

                          // Shift & Flexi In (read-only) — inline (no separate card)
                          if (_loadingCreateShiftFlex)
                            const LinearProgressIndicator(minHeight: 2),
                          if (_loadingCreateShiftFlex) const SizedBox(height: 10),
                          Row(
                            children: [
                              const Text(
                                'Shift',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _createShiftInfo ?? '-',
                                  style: const TextStyle(color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Text(
                                'Flex In',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _createFlexiIn ?? '-',
                                  style: const TextStyle(color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                          if (disableSaveForNoShift)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'No shift or holiday is assigned on this date. The Save button is disabled.',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                          const SizedBox(height: 16),

                          // Scope
                          const Text('Request For', style: TextStyle(color: Colors.black)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              scopeChip('IN', 'IN'),
                              scopeChip('OUT', 'OUT'),
                              scopeChip('IN & OUT', 'FULL'),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // NOTE: Work Type is not required in Attendance Correction Request (aligned with Web UI).

                          // Times (responsive)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 360;
                              final children = <Widget>[];

                              if (needsIn) {
                                children.add(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Check In', style: TextStyle(color: Colors.black)),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: checkInHoursController,
                                        keyboardType: TextInputType.datetime,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(4),
                                          _TimeInputFormatter(),
                                        ],
                                        onChanged: (v) {
                                          checkInHoursSpent = v;
                                          _validateCheckIn = false;
                                        },
                                        decoration: InputDecoration(
                                          labelText: '00:00',
                                          labelStyle: TextStyle(color: Colors.grey[350]),
                                          border: const OutlineInputBorder(),
                                          errorText: _validateCheckIn ? 'Please Choose a Check In' : null,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10.0),
                                          prefixIcon: IconButton(
                                            icon: const Icon(Icons.access_time),
                                            onPressed: () async {
                                              final picked = await showTimePicker(
                                                context: context,
                                                initialTime: TimeOfDay.now(),
                                              );
                                              if (picked != null) {
                                                final t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                                setState(() {
                                                  checkInHoursController.text = t;
                                                  checkInHoursSpent = t;
                                                  _validateCheckIn = false;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              if (needsOut) {
                                children.add(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Check Out', style: TextStyle(color: Colors.black)),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: checkoutHoursController,
                                        keyboardType: TextInputType.datetime,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(4),
                                          _TimeInputFormatter(),
                                        ],
                                        onChanged: (v) {
                                          checkOutHoursSpent = v;
                                          _validateCheckout = false;
                                        },
                                        decoration: InputDecoration(
                                          labelText: '00:00',
                                          labelStyle: TextStyle(color: Colors.grey[350]),
                                          border: const OutlineInputBorder(),
                                          errorText: _validateCheckout ? 'Please Choose a Check Out' : null,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10.0),
                                          prefixIcon: IconButton(
                                            icon: const Icon(Icons.access_time),
                                            onPressed: () async {
                                              final picked = await showTimePicker(
                                                context: context,
                                                initialTime: TimeOfDay.now(),
                                              );
                                              if (picked != null) {
                                                final t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                                setState(() {
                                                  checkoutHoursController.text = t;
                                                  checkOutHoursSpent = t;
                                                  _validateCheckout = false;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              if (narrow || children.length <= 1) {
                                return Column(
                                  children: [
                                    for (final w in children) ...[
                                      w,
                                      const SizedBox(height: 16),
                                    ]
                                  ],
                                );
                              }

                              // 2 columns
                              return Row(
                                children: [
                                  Expanded(child: children[0]),
                                  const SizedBox(width: 12),
                                  Expanded(child: children[1]),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          const Text('Reason / Note', style: TextStyle(color: Colors.black)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: requestDescriptionController,
                            maxLines: 3,
                            onChanged: (_) {
                              if (_validateReason) {
                                setState(() {
                                  _validateReason = false;
                                });
                              }
                            },
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: 'Write a short reason...',
                              errorText: _validateReason ? 'Reason is required' : null,
                            ),
                          ),

                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: isAction ? null : () async {
                                final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
                                if (picked == null) return;
                                final msg = _validatePickedFiles(picked.files);
                                if (msg != null) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                  return;
                                }
                                setState(() {
                                  _attendancePickedFiles = picked.files;
                                });
                              },
                              icon: const Icon(Icons.attach_file),
                              label: Text(
                                _attendancePickedFiles.isEmpty
                                    ? 'Attach files (optional)'
                                    : 'Attachments (${_attendancePickedFiles.length})',
                              ),
                            ),
                          ),

                        ],
                      ),
                    ),
                  ),
                  actions: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: disableSaveButton ? null : () async {
                          if (disableSaveForNoShift) {
                            return;
                          }

                          if (isSaveClick == true) {
                            isSaveClick = false;
                            setState(() {
                              isAction = true;
                              _errorMessage = null;
                            });

                            // Basic validations
                            if (_editingAttendanceRequestId == null) {
                              _setCreateEmployeeToSelf();
                            }
                            final selfEmployeeId = ((selectedEmployeeId ?? '').trim().isNotEmpty)
                                ? (selectedEmployeeId ?? '').trim()
                                : ((arguments['employee_id'] ?? currentEmployeeId ?? '')).toString().trim();
                            if (selfEmployeeId.isEmpty) {
                              _setCreateEmployeeToSelf();
                            }
                            final resolvedEmployeeId = ((selectedEmployeeId ?? '').trim().isNotEmpty)
                                ? (selectedEmployeeId ?? '').trim()
                                : ((arguments['employee_id'] ?? currentEmployeeId ?? '')).toString().trim();

                            if (attendanceDateController.text.isEmpty) {
                              setState(() {
                                isAction = false;
                                isSaveClick = true;
                                _validateEmployee = false;
                                _validateDate = true;
                                _validateCheckIn = false;
                                _validateCheckout = false;
                              });
                              return;
                            }
                            // Attendance Correction only allowed for yesterday or earlier (not today/future).
                            try {
                              final picked = DateFormat('yyyy-MM-dd')
                                  .parse(attendanceDateController.text.trim());
                              final now = DateTime.now();
                              final today = DateTime(now.year, now.month, now.day);
                              if (!picked.isBefore(today)) {
                                setState(() {
                                  isAction = false;
                                  isSaveClick = true;
                                  _errorMessage =
                                  'Attendance correction hanya bisa untuk tanggal kemarin atau sebelumnya.';
                                });
                                return;
                              }
                            } catch (_) {
                              setState(() {
                                isAction = false;
                                isSaveClick = true;
                                _errorMessage =
                                'Format tanggal tidak valid. Silakan pilih ulang tanggal.';
                              });
                              return;
                            }

                            // Work Type is not required for Attendance Correction Request.
                            if (needsIn && checkInHoursController.text.isEmpty) {
                              setState(() {
                                isAction = false;
                                isSaveClick = true;
                                _validateEmployee = false;
                                _validateDate = false;
                                _validateCheckIn = true;
                                _validateCheckout = false;
                              });
                              return;
                            }

                            if (needsOut && checkoutHoursController.text.isEmpty) {
                              setState(() {
                                isAction = false;
                                isSaveClick = true;
                                _validateEmployee = false;
                                _validateDate = false;
                                _validateCheckIn = false;
                                _validateCheckout = true;
                              });
                              return;
                            }

                            // Reason is required (same as Work Type Request)
                            if (requestDescriptionController.text.trim().isEmpty) {
                              setState(() {
                                isAction = false;
                                isSaveClick = true;
                                _validateReason = true;
                              });
                              return;
                            }

                            final attachmentMsg = _validatePickedFiles(_attendancePickedFiles);
                            if (attachmentMsg != null) {
                              setState(() {
                                isAction = false;
                                isSaveClick = true;
                                _errorMessage = attachmentMsg;
                              });
                              return;
                            }

                            // Do not block Attendance Correction Request by check-in/check-out time windows.
                            // Backend treats out-of-window times as reviewable correction data rather than a hard reject.

                            // Build payload (per-hari, minimal fields)
                            final date = attendanceDateController.text;

                            final createdDetails = <String, dynamic>{
                              'attendance_date': date,
                            };

                            if (needsIn) {
                              final inT = _normalizeTimeHHMM(checkInHoursSpent.isNotEmpty ? checkInHoursSpent : checkInHoursController.text);
                              createdDetails['attendance_clock_in_date'] = date;
                              createdDetails['attendance_clock_in'] = inT;
                            }

                            if (needsOut) {
                              final outT = _normalizeTimeHHMM(checkOutHoursSpent.isNotEmpty ? checkOutHoursSpent : checkoutHoursController.text);
                              createdDetails['attendance_clock_out_date'] = date;
                              createdDetails['attendance_clock_out'] = outT;
                            }

                            if (_editingAttendanceRequestId != null) {
                              await updateAttendanceRequest(_editingAttendanceRequestId!, createdDetails);
                            } else {
                              await createNewAttendance(createdDetails);
                            }
                            setState(() => isAction = false);

                            if (_errorMessage == null || _errorMessage!.isEmpty) {
                              Navigator.of(context).pop(true);
                              if (_editingAttendanceRequestId != null) {
                                _editingAttendanceRequestId = null;
                                showValidateAnimation();
                              } else {
                                showCreateAnimation();
                              }
                            } else {
                              // Keep dialog open to show error
                              setState(() {
                                isSaveClick = true;
                              });
                            }
                          }
                        },
                        style: ButtonStyle(
                          backgroundColor: MaterialStateProperty.resolveWith<Color>(
                                (states) {
                              if (states.contains(MaterialState.disabled)) {
                                return Colors.grey;
                              }
                              return Colors.red;
                            },
                          ),
                          shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          ),
                        ),
                        child: const Text('Save', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
                if (isAction) const Center(child: CircularProgressIndicator()),
              ],
            );
          },
        );
      },
    );
  }
  Future<void> createNewAttendance(Map<String, dynamic> createdDetails) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token") ?? '';
    final typedServerUrl = prefs.getString("typed_url") ?? '';

    if (typedServerUrl.isEmpty) {
      setState(() {
        _errorMessage = 'Server URL belum diset.';
      });
      return;
    }

    final uri = Uri.parse('$typedServerUrl/api/attendance/attendance-request/');

    final payload = <String, String>{
      'attendance_date': (createdDetails['attendance_date'] ?? '').toString(),
      'scope': _attendanceCorrectionScope,
    };
    if (createdDetails.containsKey('attendance_clock_in')) {
      payload['attendance_clock_in_date'] = (createdDetails['attendance_clock_in_date'] ?? '').toString();
      payload['attendance_clock_in'] = (createdDetails['attendance_clock_in'] ?? '').toString();
    }

    if (createdDetails.containsKey('attendance_clock_out')) {
      payload['attendance_clock_out_date'] = (createdDetails['attendance_clock_out_date'] ?? '').toString();
      payload['attendance_clock_out'] = (createdDetails['attendance_clock_out'] ?? '').toString();
    }

    final note = requestDescriptionController.text.trim();
    payload['reason'] = note;

    http.Response response;

    try {
      if (_attendancePickedFiles.isNotEmpty) {
        final req = http.MultipartRequest('POST', uri);
        req.headers['Authorization'] = 'Bearer $token';
        req.fields.addAll(payload);

        for (final f in _attendancePickedFiles) {
          if (f.path == null) continue;
          final rawName = f.path!.split(RegExp(r"[\\/]+")).last;
          final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
          req.files.add(await http.MultipartFile.fromPath('files', f.path!, filename: safeName));
        }

        final streamed = await req.send();
        response = await http.Response.fromStream(streamed);
      } else {
        response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        );
      }
    } catch (e) {
      setState(() {
        isSaveClick = true;
        _errorMessage = 'Tidak bisa terhubung ke server: ${e.toString()}';
      });
      return;
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      isSaveClick = false;
      _errorMessage = null;

      // Reset attachment state after successful submit
      setState(() {
        _attendancePickedFiles = [];
        requestDescriptionController.clear();
      });

      await getAllRequestedAttendances(reset: true);
      return;
    }

    // Error handling
    isSaveClick = true;
    String msg = 'Submit gagal (${response.statusCode}).';
    String? dateErr;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        // Capture attendance_date validation (e.g., Holiday / No Shift) to show under the date field
        if (decoded['attendance_date'] != null) {
          final v = decoded['attendance_date'];
          if (v is List) {
            dateErr = v.join('\n');
          } else {
            dateErr = v.toString();
          }
        }

        if (decoded['error'] != null) {
          msg = decoded['error'].toString();
        } else if (decoded['detail'] != null) {
          msg = decoded['detail'].toString();
        } else if (decoded['non_field_errors'] != null) {
          final v = decoded['non_field_errors'];
          msg = (v is List) ? v.join('\n') : v.toString();
        } else {
          final parts = <String>[];
          decoded.forEach((k, v) {
            if (v is List) {
              parts.add("$k: ${v.join(', ')}");
            } else {
              parts.add("$k: $v");
            }
          });
          if (parts.isNotEmpty) msg = parts.join('\n');
        }
      } else if (decoded != null) {
        msg = decoded.toString();
      }
    } catch (_) {
      final body = response.body.trim();
      if (body.isNotEmpty) msg = body;
    }

    setState(() {
      _errorMessage = msg;
      _attendanceDateServerError = dateErr;
    });
  }

  Future<void> updateAttendanceRequest(int requestId, Map<String, dynamic> createdDetails) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token") ?? '';
    final typedServerUrl = prefs.getString("typed_url") ?? '';

    if (typedServerUrl.isEmpty) {
      setState(() {
        _errorMessage = 'Server URL belum diset.';
      });
      return;
    }

    final uri = Uri.parse('$typedServerUrl/api/attendance/attendance-request/$requestId');
    final payload = <String, String>{
      'attendance_date': (createdDetails['attendance_date'] ?? '').toString(),
      'scope': _attendanceCorrectionScope,
      'reason': requestDescriptionController.text.trim(),
    };

    if (createdDetails.containsKey('attendance_clock_in')) {
      payload['attendance_clock_in_date'] = (createdDetails['attendance_clock_in_date'] ?? '').toString();
      payload['attendance_clock_in'] = (createdDetails['attendance_clock_in'] ?? '').toString();
    }
    if (createdDetails.containsKey('attendance_clock_out')) {
      payload['attendance_clock_out_date'] = (createdDetails['attendance_clock_out_date'] ?? '').toString();
      payload['attendance_clock_out'] = (createdDetails['attendance_clock_out'] ?? '').toString();
    }

    http.Response response;
    try {
      if (_attendancePickedFiles.isNotEmpty) {
        final req = http.MultipartRequest('PUT', uri);
        req.headers['Authorization'] = 'Bearer $token';
        req.fields.addAll(payload);
        for (final f in _attendancePickedFiles) {
          if (f.path == null) continue;
          final rawName = f.path!.split(RegExp(r"[\/]+")).last;
          final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
          req.files.add(await http.MultipartFile.fromPath('files', f.path!, filename: safeName));
        }
        final streamed = await req.send();
        response = await http.Response.fromStream(streamed);
      } else {
        response = await http.put(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        );
      }
    } catch (e) {
      setState(() {
        isSaveClick = true;
        _errorMessage = 'Tidak bisa terhubung ke server: ${e.toString()}';
      });
      return;
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      setState(() {
        isSaveClick = false;
        _errorMessage = null;
        _attendancePickedFiles = [];
      });
      await getAllRequestedAttendances(reset: true);
      return;
    }

    String msg = 'Update gagal (${response.statusCode}).';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        msg = decoded['error'].toString();
      } else if (decoded is Map && decoded['detail'] != null) {
        msg = decoded['detail'].toString();
      } else if (decoded is Map && decoded['non_field_errors'] != null) {
        final v = decoded['non_field_errors'];
        msg = (v is List) ? v.join('\n') : v.toString();
      }
    } catch (_) {
      final body = response.body.trim();
      if (body.isNotEmpty) msg = body;
    }
    setState(() {
      isSaveClick = true;
      _errorMessage = msg;
    });
  }

  Future<String?> _promptAttendanceRequestReason({required String title, required String hintText}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(hintText: hintText),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.of(ctx).pop(value);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> revokeAttendanceRequest(int requestId, {required String reason}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token") ?? '';
    final typedServerUrl = prefs.getString("typed_url") ?? '';
    final uri = Uri.parse('$typedServerUrl/api/attendance/attendance-request-revoke/$requestId');
    final response = await http.put(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    }, body: jsonEncode({'reason': reason}));
    if (response.statusCode == 200) {
      setState(() {
        isSaveClick = false;
      });
      await getAllRequestedAttendances(reset: true);
      return;
    }
    String msg = 'Failed to revoke request.';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        msg = decoded['error'].toString();
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    isSaveClick = true;
  }

  void _prefillAttendanceRequestEditor(Map<String, dynamic> record) {
    final checkIn = (record['requested_check_in_time'] ?? record['proposed_attendance_clock_in'] ?? record['attendance_clock_in'] ?? '').toString();
    final checkOut = (record['requested_check_out_time'] ?? record['proposed_attendance_clock_out'] ?? record['attendance_clock_out'] ?? '').toString();
    final attDate = (record['attendance_date'] ?? '').toString();
    final checkInDate = (record['requested_check_in_date'] ?? record['proposed_attendance_clock_in_date'] ?? record['attendance_clock_in_date'] ?? attDate).toString();
    final checkOutDate = (record['requested_check_out_date'] ?? record['proposed_attendance_clock_out_date'] ?? record['attendance_clock_out_date'] ?? attDate).toString();

    final explicitScope = _cleanValue(record['scope'])?.toUpperCase();
    if (explicitScope == 'IN' || explicitScope == 'OUT' || explicitScope == 'FULL' || explicitScope == 'BOTH') {
      _attendanceCorrectionScope = explicitScope == 'BOTH' ? 'FULL' : explicitScope!;
    } else if ((record['requested_check_in_time'] ?? record['proposed_attendance_clock_in']) != null &&
        (record['requested_check_out_time'] ?? record['proposed_attendance_clock_out']) != null) {
      _attendanceCorrectionScope = 'FULL';
    } else if ((record['requested_check_in_time'] ?? record['proposed_attendance_clock_in']) != null) {
      _attendanceCorrectionScope = 'IN';
    } else if ((record['requested_check_out_time'] ?? record['proposed_attendance_clock_out']) != null) {
      _attendanceCorrectionScope = 'OUT';
    } else {
      _attendanceCorrectionScope = 'FULL';
    }

    final employeeId = (record['employee_id'] ?? currentEmployeeId ?? '').toString();
    final employeeName = ((record['employee_first_name'] ?? '').toString() + ' ' + (record['employee_last_name'] ?? '').toString()).trim();

    selectedEmployeeId = employeeId;
    createEmployee = employeeName.isEmpty ? createEmployee : employeeName;
    if (employeeName.isNotEmpty) {
      _typeAheadController.text = employeeName;
    }
    attendanceDateController.text = attDate;
    checkInDateController.text = checkInDate;
    checkOutDateController.text = checkOutDate;
    checkInHoursController.text = _displayTimeHHMM(checkIn);
    checkoutHoursController.text = _displayTimeHHMM(checkOut);
    requestDescriptionController.text = (record['request_description'] ?? record['reason'] ?? '').toString();
    _attendancePickedFiles = [];
    _attendanceDateServerError = null;
    _errorMessage = null;
    isSaveClick = true;
  }

  Future<void> _openAttendanceRequestEditor(Map<String, dynamic> record) async {
    _editingAttendanceRequestId = int.tryParse((record['id'] ?? '').toString()) ?? record['id'];
    if (_editingAttendanceRequestId == null) {
      return;
    }
    setState(() {
      _prefillAttendanceRequestEditor(record);
    });
    await _loadCreateShiftFlexForDate();
    if (!mounted) return;
    showCreateAttendanceDialog(context);
  }

  Future<void> _showRejectReasonDialog(int requestId) async {
    final controller = TextEditingController();
    String? localError;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Reject Request', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 8),
                    Text(localError!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final reason = controller.text.trim();
                    if (reason.isEmpty) {
                      setLocalState(() {
                        localError = 'Reject reason is required.';
                      });
                      return;
                    }
                    await rejectAttendanceRequest(requestId, reason: reason);
                    if (mounted) Navigator.of(dialogContext).pop();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Reject', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> permissionChecks() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");
    if (typedServerUrl == null || typedServerUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _permissionStatusMessage = 'Server error. Try again later.';
        canApproveAttendanceRequests = false;
        permissionCheck = false;
      });
      return;
    }

    Future<bool?> _tryCheck(String url) async {
      try {
        final uri = Uri.parse(url);
        final resp = await http.get(uri, headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        }).timeout(const Duration(seconds: 12));

        if (resp.statusCode == 404) return null;
        if (resp.statusCode != 200) {
          if (mounted) {
            setState(() {
              _permissionStatusMessage = permissionGuardMessageForStatus(resp.statusCode);
            });
          }
          return false;
        }

        final body = resp.body.trim();
        if (body.isEmpty) return false;

        try {
          final data = jsonDecode(body);
          if (data is Map) {
            final dynamic v = data['can_approve'] ??
                data['canApprove'] ??
                data['permission'] ??
                data['is_manager'] ??
                data['can_approve_attendance_request'] ??
                data['can_approve_attendance_requests'];
            if (v is bool) return v;
            if (v is String) return v.toLowerCase() == 'true';
            if (v is num) return v != 0;
            return false;
          }
          if (data is bool) return data;
          if (data is num) return data != 0;
        } catch (_) {
          return false;
        }

        return false;
      } catch (error) {
        if (mounted) {
          setState(() {
            _permissionStatusMessage = permissionGuardMessageForError(error);
          });
        }
        return null;
      }
    }

    bool canApprove = false;

    final preferred = await _tryCheck(
        '$typedServerUrl/api/attendance/permission-check/attendance-request-approve');
    if (preferred != null) {
      canApprove = preferred;
    } else {
      final legacy = await _tryCheck(
          '$typedServerUrl/api/attendance/permission-check/attendance');
      canApprove = legacy ?? false;
    }

    if (!mounted) return;
    setState(() {
      canApproveAttendanceRequests = canApprove;
      permissionCheck = canApprove;
    });
    if (canApprove) {
      await getApprovalHistoryAttendances(reset: true);
    } else if (mounted) {
      setState(() {
        approvalHistoryAttendanceRecords = [];
        approvalHistoryCount = 0;
      });
    }
  }

  Future<void> _retryPermissionChecks() async {
    setState(() {
      _permissionStatusMessage = null;
    });
    await permissionChecks();
  }

  Future<void> loadCurrentEmployeeId() async {

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentEmployeeId = prefs.getInt('employee_id');
    });
  }

  void prefetchData() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var employeeId = prefs.getInt("employee_id");
    var uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      arguments = {
        'employee_id': responseData['id'],
        'employee_name': responseData['employee_first_name'] +
            ' ' +
            responseData['employee_last_name'],
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
        'employee_profile': responseData['employee_profile']
      };
      _setCreateEmployeeToSelf();
    }
  }

  Future<void> getAllRequestedAttendances({bool reset = false}) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");

    if (reset) {
      requestedPage = 1;
      requestsAllRequestedAttendances.clear();
      filteredRequestedAttendanceRecords.clear();
    }

    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/attendance-request/?page=$requestedPage&search=$searchText');

    try {
      final response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final results = List<Map<String, dynamic>>.from(decoded['results'] ?? []);

        setState(() {
          requestsAllRequestedAttendances.addAll(results);

          // De-duplicate
          String serializeMap(Map<String, dynamic> map) => jsonEncode(map);
          Map<String, dynamic> deserializeMap(String jsonString) => jsonDecode(jsonString);
          final mapStrings = requestsAllRequestedAttendances.map(serializeMap).toList();
          final unique = mapStrings.toSet();
          requestsAllRequestedAttendances = unique.map(deserializeMap).toList();

          allRequestAttendance = decoded['count'] ?? requestsAllRequestedAttendances.length;
          filteredRequestedAttendanceRecords =
              filterRequestedAttendanceRecords(searchText);
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> getApprovalHistoryAttendances({bool reset = false}) async {
    if (!canApproveAttendanceRequests) {
      if (mounted) {
        setState(() {
          approvalHistoryAttendanceRecords = [];
          approvalHistoryCount = 0;
          approvalHistoryEmployeeOptions = [];
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");

    if (reset) {
      approvalHistoryPage = 1;
      approvalHistoryAttendanceRecords.clear();
      approvalHistoryEmployeeOptions.clear();
      _loadingApprovalHistory = true;
    }

    final query = {
      'page': '$approvalHistoryPage',
      'approval_view': 'history',
      'month': approvalHistoryMonth,
      'status': approvalHistoryStatus,
    };
    final employeeId = _cleanValue(approvalHistoryEmployeeId);
    if (employeeId != null) {
      query['employee_id'] = employeeId;
    }

    final uri = Uri.parse('$typedServerUrl/api/attendance/attendance-request/').replace(queryParameters: query);

    try {
      final response = await http.get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      });
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final results = List<Map<String, dynamic>>.from(decoded['results'] ?? []);
        final employeeOptions = List<Map<String, dynamic>>.from(decoded['employee_options'] ?? []);
        setState(() {
          approvalHistoryCount = decoded['count'] ?? results.length;
          approvalHistoryEmployeeOptions = employeeOptions;
          if (reset) {
            approvalHistoryAttendanceRecords = results;
          } else {
            approvalHistoryAttendanceRecords.addAll(results);
            final unique = <String, Map<String, dynamic>>{};
            for (final item in approvalHistoryAttendanceRecords) {
              unique[item['id'].toString()] = item;
            }
            approvalHistoryAttendanceRecords = unique.values.toList();
          }
          _loadingApprovalHistory = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _loadingApprovalHistory = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingApprovalHistory = false;
        });
      }
    }
  }

  String _formatMonthLabel(String rawMonth) {
    try {
      return DateFormat('MMMM yyyy').format(DateTime.parse('$rawMonth-01'));
    } catch (_) {
      return rawMonth;
    }
  }

  Future<String?> _showMonthYearPicker(BuildContext context, String initialMonth) async {
    final parsed = DateTime.tryParse('$initialMonth-01') ?? DateTime.now();
    int selectedYear = parsed.year;
    int selectedMonth = parsed.month;
    final years = List<int>.generate(81, (index) => 2020 + index);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Select month'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedMonth,
                    decoration: _requestFilterFieldDecoration('Month'),
                    style: _requestFilterFieldTextStyle,
                    dropdownColor: Colors.white,
                    iconEnabledColor: Colors.black87,
                    items: List.generate(12, (index) {
                      final month = index + 1;
                      return DropdownMenuItem<int>(
                        value: month,
                        child: Text(DateFormat('MMMM').format(DateTime(2000, month, 1))),
                      );
                    }),
                    onChanged: (value) {
                      if (value == null) return;
                      setStateDialog(() => selectedMonth = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedYear,
                    decoration: _requestFilterFieldDecoration('Year'),
                    style: _requestFilterFieldTextStyle,
                    dropdownColor: Colors.white,
                    iconEnabledColor: Colors.black87,
                    items: years
                        .map((year) => DropdownMenuItem<int>(value: year, child: Text(year.toString())))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setStateDialog(() => selectedYear = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    '${selectedYear.toString().padLeft(4, '0')}-${selectedMonth.toString().padLeft(2, '0')}',
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  InputDecoration _requestFilterFieldDecoration(String label) {
    return const InputDecoration(
      border: OutlineInputBorder(),
      isDense: false,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      labelStyle: TextStyle(color: Colors.black87),
      floatingLabelStyle: TextStyle(color: Colors.black87),
    ).copyWith(labelText: label);
  }

  TextStyle get _requestFilterFieldTextStyle => const TextStyle(
    color: Colors.black87,
    fontSize: 16,
    height: 1.2,
  );

  bool _matchesAttendanceRequestStatus(Map<String, dynamic> record) {
    if (_myStatus == 'all') return true;
    final raw = ((record['status'] ?? record['request_status'] ?? '')).toString().trim().toLowerCase();
    if (_myStatus == 'waiting') {
      return raw == 'waiting' || raw == 'pending';
    }
    if (_myStatus == 'canceled') {
      return raw == 'canceled' || raw == 'cancel';
    }
    return raw == _myStatus;
  }

  bool _matchesAttendanceRequestMonth(Map<String, dynamic> record) {
    final target = DateTime.tryParse('$_myMonth-01');
    final raw = (record['attendance_date'] ?? '').toString().trim();
    final parsed = DateTime.tryParse(raw);
    if (target == null || parsed == null) return true;
    return parsed.year == target.year && parsed.month == target.month;
  }

  Future<void> _openAttendanceMyRequestFilterDialog() async {
    String draftStatus = _myStatus;
    String draftMonth = _myMonth;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('My Request Filters'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: draftStatus,
                      decoration: _requestFilterFieldDecoration('Request Status'),
                      style: _requestFilterFieldTextStyle,
                      dropdownColor: Colors.white,
                      iconEnabledColor: Colors.black87,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All statuses')),
                        DropdownMenuItem(value: 'waiting', child: Text('Waiting')),
                        DropdownMenuItem(value: 'approved', child: Text('Approved')),
                        DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                        DropdownMenuItem(value: 'revoked', child: Text('Revoked')),
                        DropdownMenuItem(value: 'canceled', child: Text('Canceled')),
                      ],
                      onChanged: (value) => setStateDialog(() => draftStatus = value ?? 'all'),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final pickedMonth = await _showMonthYearPicker(context, draftMonth);
                        if (pickedMonth == null) return;
                        setStateDialog(() => draftMonth = pickedMonth);
                      },
                      child: InputDecorator(
                        decoration: _requestFilterFieldDecoration('Month'),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _formatMonthLabel(draftMonth),
                                style: _requestFilterFieldTextStyle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.calendar_today, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _myStatus = draftStatus;
                      _myMonth = draftMonth;
                    });
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> filterApprovalHistoryRecords(String searchText) {
    if (searchText.isEmpty) return approvalHistoryAttendanceRecords;
    return approvalHistoryAttendanceRecords.where((record) {
      final firstName = record['employee_first_name'] ?? '';
      final lastName = record['employee_last_name'] ?? '';
      final fullName = (firstName + ' ' + lastName).toLowerCase();
      final requestDescription = (record['request_description'] ?? '').toString().toLowerCase();
      return fullName.contains(searchText.toLowerCase()) || requestDescription.contains(searchText.toLowerCase());
    }).toList();
  }

  Future<void> getAllAttendances({bool reset = false}) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");

    if (reset) {
      attendancesPage = 1;
      requestsAllAttendances.clear();
      filteredAllAttendanceRecords.clear();
    }

    var uri = Uri.parse(
        '$typedServerUrl/api/attendance/attendance/?page=$attendancesPage&search=$searchText');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });

    if (response.statusCode == 200) {
      setState(() {
        final decoded = jsonDecode(response.body);
        requestsAllAttendances.addAll(
          List<Map<String, dynamic>>.from(decoded['results']),
        );

        String serializeMap(Map<String, dynamic> map) {
          return jsonEncode(map);
        }

        Map<String, dynamic> deserializeMap(String jsonString) {
          return jsonDecode(jsonString);
        }

        List<String> mapStrings = requestsAllAttendances.map(serializeMap).toList();
        Set<String> uniqueMapStrings = mapStrings.toSet();
        requestsAllAttendances = uniqueMapStrings.map(deserializeMap).toList();

        myRequestAttendance = decoded['count'];
        filteredAllAttendanceRecords = filterAllAttendanceRecords(searchText);
        isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> filterRequestedAttendanceRecords(
      String searchText) {
    if (searchText.isEmpty) {
      return requestsAllRequestedAttendances;
    } else {
      return requestsAllRequestedAttendances.where((record) {
        final firstName = record['employee_first_name'] ?? '';
        final lastName = record['employee_last_name'] ?? '';
        final fullName = (firstName + ' ' + lastName).toLowerCase();
        return fullName.contains(searchText.toLowerCase());
      }).toList();
    }
  }

  List<Map<String, dynamic>> filterAllAttendanceRecords(String searchText) {
    if (searchText.isEmpty) {
      return requestsAllAttendances;
    } else {
      return requestsAllAttendances.where((record) {
        final firstName = record['employee_first_name'] ?? '';
        final lastName = record['employee_last_name'] ?? '';
        final fullName = (firstName + ' ' + lastName).toLowerCase();
        return fullName.contains(searchText.toLowerCase());
      }).toList();
    }
  }

  /// Cancel a request created by the current user (Pending -> Canceled).
  Future<void> cancelAttendanceRequest(record) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");
    final int requestId = int.tryParse(record.toString()) ?? 0;

    final uri = Uri.parse('$typedServerUrl/api/attendance/attendance-request-cancel/$requestId');
    final response = await http.put(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });

    if (response.statusCode == 200) {
      isSaveClick = false;
      // Refresh so the request shows updated status (CANCELED).
      await getAllRequestedAttendances(reset: true);
      if (!mounted) return;
      setState(() {});
      return;
    }

    // Show backend error (if any)
    String msg = 'Failed to cancel request.';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        msg = decoded['error'].toString();
      } else if (decoded is Map && decoded['detail'] != null) {
        msg = decoded['detail'].toString();
      }
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    isSaveClick = true;
  }

  /// Reject a request as an approver/manager (Pending -> Rejected).
  Future<void> rejectAttendanceRequest(record, {required String reason}) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    int requestId = record;
    var uri = Uri.parse(
        '$typedServerUrl/api/attendance/attendance-request-reject/$requestId');
    var response = await http.put(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    }, body: jsonEncode({"reason": reason}));
    if (response.statusCode == 200) {
      setState(() {
        isSaveClick = false;
        // Keep the item in the list; backend will mark it as CANCEL and it will stay in My Requests.
        getAllRequestedAttendances(reset: true);
      });
    } else {
      isSaveClick = true;
    }
  }

  Future<void> approveRequest(record) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    int requestId = record;
    var uri = Uri.parse(
        '$typedServerUrl/api/attendance/attendance-request-approve/$requestId');
    var response = await http.put(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      setState(() {
        isSaveClick = false;
        // Keep the item in the list; backend will mark it as CANCEL and it will stay in My Requests.
        getAllRequestedAttendances(reset: true);
      });
    } else {
      isSaveClick = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.menu), // Menu icon
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: const Text(
          'Requests',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      final tabCtx = _scaffoldKey.currentContext ?? context;
                      showCreateRequestBottomSheet(tabCtx);
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(75, 50),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4.0),
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                    child: const Text('CREATE',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          permissionNoticeTile(_permissionStatusMessage, onRetry: _retryPermissionChecks),
          Expanded(
            child: isLoading ? _buildLoadingWidget() : _buildEmployeeDetailsWidget(),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: const EdgeInsets.all(0),
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(),
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: Image.asset('Assets/horilla-logo.png'),
                ),
              ),
            ),
            _isPermissionCheckComplete
                ? Column(
              children: [
                // All other menu items are always visible
                ListTile(
                  title: const Text('Attendance'),
                  onTap: () {
                    Navigator.pushNamed(
                        context, '/attendance_attendance');
                  },
                ),
                ListTile(
                  title: const Text('Punching History'),
                  onTap: () {
                    Navigator.pushNamed(context, '/attendance_punching_history');
                  },
                ),
                ListTile(
                  title: const Text('Requests'),
                  onTap: () {
                    Navigator.pushNamed(context, '/attendance_request');
                  },
                ),
              ],
            )
                : Column(
              // Loading state (shimmer effect)
              children: [
                shimmerListTile(),
                shimmerListTile(),
                shimmerListTile(),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: (bottomBarPages.length <= maxCount)
          ? SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        child: AnimatedNotchBottomBar(
          /// Provide NotchBottomBarController
          notchBottomBarController: _controller,
          color: Colors.red,
          showLabel: true,
          notchColor: Colors.red,
          kBottomRadius: 28.0,
          kIconSize: 24.0,

          /// restart app if you change removeMargins
          removeMargins: false,
          bottomBarWidth: MediaQuery.of(context).size.width * 1,
          durationInMilliSeconds: 300,
          bottomBarItems: const [
            BottomBarItem(
              inActiveItem: Icon(
                Icons.home_filled,
                color: Colors.white,
              ),
              activeItem: Icon(
                Icons.home_filled,
                color: Colors.white,
              ),
              // itemLabel: 'Home',
            ),
            BottomBarItem(
              inActiveItem: Icon(
                Icons.update_outlined,
                color: Colors.white,
              ),
              activeItem: Icon(
                Icons.update_outlined,
                color: Colors.white,
              ),
            ),
            BottomBarItem(
              inActiveItem: Icon(
                Icons.person,
                color: Colors.white,
              ),
              activeItem: Icon(
                Icons.person,
                color: Colors.white,
              ),
            ),
          ],

          onTap: (index) async {
            switch (index) {
              case 0:
                Navigator.pushNamed(context, '/home');
                break;
              case 1:
                Navigator.pushNamed(
                    context, '/employee_checkin_checkout');
                break;
              case 2:
                Navigator.pushNamed(context, '/employees_form',
                    arguments: arguments);
                break;
            }
          },
        ),
      )
          : null,
    );
  }

  Widget shimmerListTile() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListTile(
        title: Container(
          width: double.infinity,
          height: 20.0,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: Card(
                  margin: const EdgeInsets.all(8),
                  elevation: 0,
                  child: Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4.0),
                        border: Border.all(color: Colors.grey),
                        color: Colors.white,
                      ),
                      child: const TextField(
                        decoration: InputDecoration(
                          hintText: 'Search',
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.search),
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 12.0, horizontal: 4.0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.02),
        TabBar(
          controller: _tabController,
          labelColor: Colors.red,
          indicatorColor: Colors.red,
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabs: [
            Tab(
              text: 'Attendance Requests ($allRequestAttendance)',
            ),
            Tab(
              text: 'Work Type Requests ($workModeRequestCount)',
            ),
          ],
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.03),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              buildRequestedLoadingAttendanceContent(
                  requestsAllRequestedAttendances,
                  _requestedScrollController,
                  searchText),
              WorkModeRequestTab(
                key: _workModeKey,
                searchText: searchText,
                employeeOptions: _approvalScopedEmployeeOptions,
                onCountChanged: (c) {
                  if (!mounted) return;
                  setState(() => workModeRequestCount = c);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _normalizeEmployeeIdValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      return _normalizeEmployeeIdValue(raw['id'] ?? raw['employee_id'] ?? raw['employeeId']);
    }
    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'none' || value.toLowerCase() == 'null') {
      return null;
    }
    return value;
  }

  bool _isCurrentEmployeeRequest(Map<String, dynamic> record) {
    // For regular employees who do not have approval access, every item returned by the
    // attendance request API should be treated as their own request. This avoids hiding
    // newly-created requests behind a fragile client-side ownership split.
    if (!canApproveAttendanceRequests) return true;
    if (currentEmployeeId == null) return true;
    final requestEmployeeId = _normalizeEmployeeIdValue(
      record['employee_id'] ?? record['employee'] ?? record['employeeId'],
    );
    final selfId = _normalizeEmployeeIdValue(currentEmployeeId);
    if (requestEmployeeId == null || selfId == null) return true;
    return requestEmployeeId == selfId;
  }

  bool _isMyAttendanceRequest(Map<String, dynamic> record) => _isCurrentEmployeeRequest(record);

  List<Map<String, dynamic>> get _approvalScopedEmployeeOptions {
    final scoped = <String, Map<String, dynamic>>{};

    void addEmployeeRecord(Map<String, dynamic> record) {
      final employeeId = _normalizeEmployeeIdValue(
        record['employee_id'] ?? record['employee'] ?? record['employeeId'] ?? record['id'],
      );
      if (employeeId == null || scoped.containsKey(employeeId)) return;
      final selfId = _normalizeEmployeeIdValue(currentEmployeeId);
      if (selfId != null && employeeId == selfId) return;
      final firstName = (record['employee_first_name'] ?? '').toString();
      final lastName = (record['employee_last_name'] ?? '').toString();
      scoped[employeeId] = {
        'id': employeeId,
        'employee_first_name': firstName,
        'employee_last_name': lastName,
      };
    }

    if (approvalHistoryEmployeeOptions.isNotEmpty) {
      for (final employee in approvalHistoryEmployeeOptions) {
        addEmployeeRecord(employee);
      }
    } else {
      for (final record in requestsAllRequestedAttendances.where((record) => !_isMyAttendanceRequest(record))) {
        addEmployeeRecord(record);
      }
      for (final record in approvalHistoryAttendanceRecords) {
        addEmployeeRecord(record);
      }
    }

    final employees = scoped.values.toList();
    employees.sort((a, b) {
      final aName = ((a['employee_first_name'] ?? '').toString() + ' ' + (a['employee_last_name'] ?? '').toString()).trim().toLowerCase();
      final bName = ((b['employee_first_name'] ?? '').toString() + ' ' + (b['employee_last_name'] ?? '').toString()).trim().toLowerCase();
      return aName.compareTo(bName);
    });
    return employees;
  }

  Future<void> _openWorkTypeRequestDialogFromMenu() async {
    _tabController.animateTo(1);
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(milliseconds: 60));
      final state = _workModeKey.currentState;
      if (state != null) {
        await state.openCreateDialog();
        return;
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _openAttendanceApprovalHistoryFilterDialog() async {
    String draftStatus = approvalHistoryStatus;
    String draftEmployeeId = approvalHistoryEmployeeId;
    String draftMonth = approvalHistoryMonth;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Approval History Filters'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: draftEmployeeId.isEmpty ? '' : draftEmployeeId,
                      isExpanded: true,
                      decoration: _requestFilterFieldDecoration('Employee'),
                      style: _requestFilterFieldTextStyle,
                      dropdownColor: Colors.white,
                      iconEnabledColor: Colors.black87,
                      items: [
                        const DropdownMenuItem<String>(value: '', child: Text('All employees')),
                        ..._approvalScopedEmployeeOptions.map((employee) {
                          final id = (employee['id'] ?? '').toString();
                          final firstName = (employee['employee_first_name'] ?? '').toString();
                          final lastName = (employee['employee_last_name'] ?? '').toString();
                          final name = ('$firstName $lastName').trim();
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(name.isEmpty ? 'Employee' : name),
                          );
                        }),
                      ],
                      onChanged: (value) => setStateDialog(() => draftEmployeeId = value ?? ''),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: draftStatus,
                      decoration: _requestFilterFieldDecoration('Request Status'),
                      style: _requestFilterFieldTextStyle,
                      dropdownColor: Colors.white,
                      iconEnabledColor: Colors.black87,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All statuses')),
                        DropdownMenuItem(value: 'approved', child: Text('Approved')),
                        DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                        DropdownMenuItem(value: 'revoked', child: Text('Revoked')),
                        DropdownMenuItem(value: 'canceled', child: Text('Canceled')),
                      ],
                      onChanged: (value) => setStateDialog(() => draftStatus = value ?? 'all'),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final pickedMonth = await _showMonthYearPicker(context, draftMonth);
                        if (pickedMonth == null) return;
                        setStateDialog(() => draftMonth = pickedMonth);
                      },
                      child: InputDecorator(
                        decoration: _requestFilterFieldDecoration('Month'),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _formatMonthLabel(draftMonth),
                                style: _requestFilterFieldTextStyle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.calendar_today, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      approvalHistoryStatus = draftStatus;
                      approvalHistoryEmployeeId = draftEmployeeId;
                      approvalHistoryMonth = draftMonth;
                    });
                    await getApprovalHistoryAttendances(reset: true);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAttendanceRequestsSubtabs() {
    final my = filteredRequestedAttendanceRecords
        .where((r) => _isMyAttendanceRequest(r))
        .where(_matchesAttendanceRequestStatus)
        .where(_matchesAttendanceRequestMonth)
        .toList();
    final approvals = filteredRequestedAttendanceRecords
        .where((r) => !_isMyAttendanceRequest(r))
        .toList();
    final approvalHistory = filterApprovalHistoryRecords(searchText);

    Widget emptyState(String message) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_outlined,
                  size: 72, color: Colors.grey.shade600),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final myContent = my.isEmpty
        ? emptyState('No attendance requests yet.')
        : buildRequestedAttendanceContent(my, _requestedScrollController, searchText);

    final myView = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Month: ${_formatMonthLabel(_myMonth)} • Status: ${_myStatus == 'all' ? 'ALL' : _myStatus.toUpperCase()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openAttendanceMyRequestFilterDialog,
                icon: const Icon(Icons.filter_list),
                label: const Text('Filters'),
              ),
            ],
          ),
        ),
        Expanded(child: myContent),
      ],
    );

    Widget activeApprovalsView = approvals.isEmpty
        ? emptyState('No attendance requests awaiting your approval.')
        : buildRequestedAttendanceContent(approvals, _requestedScrollController, searchText);

    Widget historyView = _loadingApprovalHistory
        ? const Center(child: CircularProgressIndicator())
        : approvalHistory.isEmpty
        ? emptyState('No approval history found for the selected date.')
        : buildRequestedAttendanceContent(approvalHistory, _approvalHistoryScrollController, searchText);

    final approvalsWorkspace = !canApproveAttendanceRequests
        ? emptyState('You do not have access to approve attendance requests.')
        : DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorColor: Colors.red,
            labelColor: Colors.red,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Approval (${approvals.length})'),
              Tab(text: 'Approval History (${approvalHistoryCount})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                activeApprovalsView,
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Month: ${_formatMonthLabel(approvalHistoryMonth)} • Status: ${approvalHistoryStatus == 'all' ? 'ALL' : approvalHistoryStatus.toUpperCase()}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _openAttendanceApprovalHistoryFilterDialog,
                            icon: const Icon(Icons.filter_list),
                            label: const Text('Filters'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: historyView),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorColor: Colors.red,
            labelColor: Colors.red,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'My Requests (${my.length})'),
              Tab(text: 'Approvals (${approvals.length + approvalHistoryCount})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [myView, approvalsWorkspace],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeDetailsWidget() {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.02),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Card(
                      margin: const EdgeInsets.all(8),
                      elevation: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade50),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TextField(
                          onChanged: (employeeSearchValue) {
                            if (_debounce?.isActive ?? false) {
                              _debounce!.cancel();
                            }
                            _debounce =
                                Timer(const Duration(milliseconds: 1000), () {
                                  setState(() {
                                    searchText = employeeSearchValue;
                                  });
                                  getAllRequestedAttendances(reset: true);
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _workModeKey.currentState?.refresh(reset: true);
                                  });
                                });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide.none,
                            ),
                            hintStyle:
                            TextStyle(color: Colors.blueGrey.shade300),
                            filled: true,
                            fillColor: Colors.grey[100],
                            prefixIcon: Transform.scale(
                              scale: 0.8,
                              child: Icon(Icons.search,
                                  color: Colors.blueGrey.shade300),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 12.0, horizontal: 4.0),
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.02),
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.red,
              labelColor: Colors.red,
              unselectedLabelColor: Colors.grey,
              isScrollable: true,
              tabs: [
                Tab(
                  text: 'Attendance Requests ($allRequestAttendance)',
                ),
                Tab(
                  text: 'Work Type Requests ($workModeRequestCount)',
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAttendanceRequestsSubtabs(),
                  WorkModeRequestTab(
                    key: _workModeKey,
                    searchText: searchText,
                    employeeOptions: _approvalScopedEmployeeOptions,
                    onCountChanged: (c) {
                      if (!mounted) return;
                      setState(() => workModeRequestCount = c);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===== Helpers for Attendance Request UI =====
  String? _cleanValue(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'None' || s == 'null') return null;
    return s;
  }

  /// Extracts an ID string from either a primitive or a nested object (Map).
  /// Many Horilla endpoints return relations as `{id: ..., ...}`.
  String? _idOf(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      // Common id keys
      final cand = v['id'] ?? v['pk'] ?? v['shift_id'] ?? v['employee_shift_id'];
      return _cleanValue(cand);
    }
    return _cleanValue(v);
  }

  Map<String, dynamic> _parseRequestedData(Map<String, dynamic> record) {
    // Cleanup stage 2: attendance correction requests should rely on explicit
    // request entity fields from the API, not legacy requested_data payloads.
    return const <String, dynamic>{};
  }

  String? _proposedOrRecord(Map<String, dynamic> record, String key) {
    final explicit = _cleanValue(record['proposed_$key']);
    if (explicit != null) return explicit;
    final direct = _cleanValue(record['requested_$key']);
    if (direct != null) return direct;
    return null;
  }

  String? _finalOrRecord(Map<String, dynamic> record, String key) {
    final explicit = _cleanValue(record['final_$key']);
    if (explicit != null) return explicit;
    return _cleanValue(record[key]);
  }

  String? _requestedOrRecord(Map<String, dynamic> record, String key) {
    final explicit = _cleanValue(record['effective_$key']);
    if (explicit != null) return explicit;
    final proposed = _proposedOrRecord(record, key);
    if (proposed != null) return proposed;
    return _finalOrRecord(record, key);
  }

  String _displayTimeHHMM(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null' || s.toLowerCase() == 'none') {
      return '—';
    }

    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (match != null) {
      final hh = (match.group(1) ?? '0').padLeft(2, '0');
      final mm = (match.group(2) ?? '0').padLeft(2, '0');
      return '$hh:$mm';
    }

    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return DateFormat('HH:mm').format(dt);
    }

    return s;
  }

  String? _lookupNameById(Map<String, String> nameToId, dynamic id) {
    final sid = _idOf(id);
    if (sid == null) return null;
    for (final e in nameToId.entries) {
      if (e.value == sid) return e.key;
    }
    return null;
  }

  String? _shiftNameForRecord(Map<String, dynamic> record) {
    final name = _cleanValue(record['shift_name']);
    if (name != null) return name;
    return _lookupNameById(shiftIdMap, record['shift_id']);
  }

  String? _shiftDisplayForRecord(Map<String, dynamic> record) {
    final sid = _idOf(record['shift_id'] ?? record['employee_shift_id'] ?? record['employee_shift'] ?? record['shift']);
    final name = _shiftNameForRecord(record);
    final time = (sid != null) ? shiftTimeRangeById[sid] : null;
    if (time != null && name != null) return '$time ($name)';
    return time ?? name;
  }

  /// Returns only the shift time range (e.g., 07:30 - 16:00) when available.
  /// Falls back to null if schedule mapping is not available yet.
  String? _shiftTimeOnlyForRecord(Map<String, dynamic> record) {
    final sid = _idOf(record['shift_id'] ?? record['employee_shift_id'] ?? record['employee_shift'] ?? record['shift']);
    if (sid == null) return null;
    return shiftTimeRangeById[sid];
  }

  /// Returns flexi/grace minutes for the shift when available.
  int? _flexiMinutesForRecord(Map<String, dynamic> record) {
    final sid = _idOf(record['shift_id'] ?? record['employee_shift_id'] ?? record['employee_shift'] ?? record['shift']);
    if (sid == null) return null;
    return shiftFlexiMinutesById[sid];
  }

  String _scopeLabel(String? checkIn, String? checkOut) {
    final hasIn = checkIn != null && checkIn.isNotEmpty;
    final hasOut = checkOut != null && checkOut.isNotEmpty;
    if (hasIn && hasOut) return 'IN & OUT';
    if (hasIn) return 'IN';
    if (hasOut) return 'OUT';
    return '-';
  }

  String? _scopeLabelFromRaw(dynamic rawScope) {
    final scope = _cleanValue(rawScope)?.toUpperCase();
    if (scope == null) return null;
    if (scope == 'IN') return 'IN';
    if (scope == 'OUT') return 'OUT';
    if (scope == 'FULL' || scope == 'BOTH' || scope == 'IN & OUT') {
      return 'IN & OUT';
    }
    return null;
  }

  String _scopeLabelForRecord(Map<String, dynamic> record) {
    final explicit = _scopeLabelFromRaw(
      record['scope_label'] ??
          record['scope'] ??
          record['current_scope'] ??
          record['request_scope'],
    );
    if (explicit != null) return explicit;

    // Fallback only to request/proposed values. Do not derive the scope from
    // final/effective attendance values because the day record can already have
    // both IN and OUT populated even when the request itself only targets one side.
    final proposedIn = _proposedOrRecord(record, 'attendance_clock_in') ??
        _cleanValue(record['requested_check_in_time']);
    final proposedOut = _proposedOrRecord(record, 'attendance_clock_out') ??
        _cleanValue(record['requested_check_out_time']);
    return _scopeLabel(proposedIn, proposedOut);
  }

  String? _attReqStatusText(Map<String, dynamic> r) {
    final raw = (r['status'] ??
        r['request_status'] ??
        r['attendance_request_status'] ??
        r['approval_status'] ??
        r['state'] ??
        '')
        .toString()
        .trim();
    if (raw.isEmpty) return null;

    final up = raw.toUpperCase();

    // Attendance Correction Request status (attachments are optional):
    // WAITING / APPROVED / REJECTED / CANCELED / REVOKED
    // Some backends still send PENDING or VALIDATED; map them to our UI labels.
    if (up.contains('REVOK')) return 'REVOKED';
    if (up.contains('CANCEL')) return 'CANCELED';
    if (up.contains('REJECT')) return 'REJECTED';
    if (up.contains('APPROV') || up.contains('VALID')) return 'APPROVED';
    if (up.contains('WAIT') || up.contains('PEND')) return 'WAITING';
    return up;
  }

  Color _attReqStatusColor(String status) {
    final s = status.toUpperCase();
    if (s == 'APPROVED') return Colors.green;
    if (s == 'REJECTED') return Colors.red;
    if (s == 'REVOKED') return Colors.blueGrey;
    if (s.contains('CANCEL')) return Colors.grey;
    if (s == 'WAITING') return Colors.orange;
    return Colors.blueGrey;
  }

  // --- Action info helpers (similar behavior to Work Type Requests) ---
  String? _attReqActionLabel(Map<String, dynamic> r) {
    final s = (_attReqStatusText(r) ?? '').toUpperCase();
    if (s == 'APPROVED') return 'Approved By';
    if (s == 'REJECTED') return 'Rejected By';
    if (s == 'REVOKED') return 'Revoked By';
    if (s.contains('CANCEL')) return 'Canceled By';
    return null;
  }

  String? _nameFromAny(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is Map) {
      final direct = _cleanValue(v['full_name'] ?? v['name'] ?? v['employee_name'] ?? v['username']);
      if (direct != null) return direct;
      final fn = _cleanValue(v['first_name']);
      final ln = _cleanValue(v['last_name']);
      final combined = [fn, ln]
          .where((e) => (e ?? '').toString().trim().isNotEmpty)
          .join(' ')
          .trim();
      return combined.isEmpty ? null : combined;
    }
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  String? _attReqActionByName(Map<String, dynamic> r) {
    return _nameFromAny(
      r['action_by'] ??
          r['action_by_name'],
    );
  }

  String? _attReqActionAtText(Map<String, dynamic> r) {
    final raw = _cleanValue(
      r['action_at'],
    );
    if (raw == null) return null;
    try {
      final dt = DateTime.tryParse(raw);
      if (dt == null) return raw;
      return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
    } catch (_) {
      return raw;
    }
  }

  Widget buildRequestedAttendanceContent(
      List<Map<String, dynamic>> records, scrollController, searchText) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListView.builder(
        controller: scrollController,
        shrinkWrap: true,
        itemCount: records.length,
        itemBuilder: (context, index) {
          final record = records[index];
          final firstName = record['employee_first_name'] ?? '';
          final lastName = record['employee_last_name'] ?? '';
          final fullName = (firstName.isEmpty ? '' : firstName) +
              (lastName.isEmpty ? '' : ' $lastName');
          final profile = record['employee_profile'];
          return buildRequestedAttendance(
              record, fullName, profile ?? "", baseUrl, getToken);
        },
      ),
    );
  }

  Widget buildRequestedLoadingAttendanceContent(
      List<Map<String, dynamic>> requestsAllRequestedAttendances,
      scrollController,
      searchText) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: 10,
        itemBuilder: (context, index) {
          return Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[50]!),
                  borderRadius: BorderRadius.circular(8.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade400.withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
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
                          children: [
                            Container(
                              width: 40.0,
                              height: 40.0,
                              color: Colors.grey[300],
                            ),
                          ],
                        ),
                        SizedBox(
                            height: MediaQuery.of(context).size.height * 0.005),
                        Container(
                          height: 20.0,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 20.0,
                          width: 80.0,
                          color: Colors.grey[300],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildMyAllAttendanceLoadingContent(
      List<Map<String, dynamic>> requestsAllAttendances, scrollController) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: 10,
        itemBuilder: (context, index) {
          return Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[50]!),
                  borderRadius: BorderRadius.circular(8.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade400.withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
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
                          children: [
                            Container(
                              width: 40.0,
                              height: 40.0,
                              color: Colors.grey[300],
                            ),
                          ],
                        ),
                        SizedBox(
                            height: MediaQuery.of(context).size.height * 0.005),
                        Container(
                          height: 20.0,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 20.0,
                          width: 80.0,
                          color: Colors.grey[300],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildMyAllAttendanceContent(
      List<Map<String, dynamic>> requestsAllAttendances, scrollController) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListView.builder(
        controller: scrollController,
        shrinkWrap: true,
        itemCount: searchText.isEmpty
            ? requestsAllAttendances.length
            : filteredAllAttendanceRecords.length,
        itemBuilder: (context, index) {
          final record = searchText.isEmpty
              ? requestsAllAttendances[index]
              : filteredAllAttendanceRecords[index];
          final firstName = record['employee_first_name'] ?? '';
          final lastName = record['employee_last_name'] ?? '';
          final fullName = (firstName.isEmpty ? '' : firstName) +
              (lastName.isEmpty ? '' : ' $lastName');
          final profile = record['employee_profile'];
          return buildMyAllAttendance(
              record, fullName, profile ?? "", baseUrl, getToken);
        },
      ),
    );
  }

  Widget buildRequestedAttendance(
      Map<String, dynamic> record, fullName, String profile, baseUrl, token) {
    final bool isMyRequest = _isCurrentEmployeeRequest(record);
    final bool showApprovalActions = canShowAttendanceRequestApprovalActions(
      canApproveAttendanceRequests: canApproveAttendanceRequests,
      isMyRequest: isMyRequest,
    );

    // Cleanup stage 2: rely on explicit request entity fields from the API.
    final bool isUpdateRequest = _proposedOrRecord(record, 'attendance_clock_in') != null ||
        _proposedOrRecord(record, 'attendance_clock_out') != null;
    final String? displayCheckIn = _requestedOrRecord(record, 'attendance_clock_in');
    final String? displayCheckOut = _requestedOrRecord(record, 'attendance_clock_out');
    final String? displayCheckInDate = _requestedOrRecord(record, 'attendance_clock_in_date');
    final String? displayCheckOutDate = _requestedOrRecord(record, 'attendance_clock_out_date');
    final String? proposedCheckIn = _proposedOrRecord(record, 'attendance_clock_in');
    final String? proposedCheckOut = _proposedOrRecord(record, 'attendance_clock_out');
    final String? proposedCheckInDate = _proposedOrRecord(record, 'attendance_clock_in_date');
    final String? proposedCheckOutDate = _proposedOrRecord(record, 'attendance_clock_out_date');
    final String? finalCheckIn = _finalOrRecord(record, 'attendance_clock_in');
    final String? finalCheckOut = _finalOrRecord(record, 'attendance_clock_out');
    final String? finalCheckInDate = _finalOrRecord(record, 'attendance_clock_in_date');
    final String? finalCheckOutDate = _finalOrRecord(record, 'attendance_clock_out_date');
    final String? displayShift = _shiftDisplayForRecord(record);
    final String? shiftTimeOnly = _shiftTimeOnlyForRecord(record);
    final int? flexMin = _flexiMinutesForRecord(record);
    final String shiftDisplayValue = (shiftTimeOnly ?? displayShift) ?? '—';
    final String flexDisplayValue = _flexMinutesDisplayWithMode(
      flexMin,
      clockInType: (record['clock_in_type'] ?? record['grace_clock_in_type'] ?? record['grace_type'])?.toString(),
    );

    final String displayScope = _scopeLabelForRecord(record);
    final String? status = _attReqStatusText(record);
    final String? actionLabel = _attReqActionLabel(record);
    final String? actionBy = _attReqActionByName(record);
    final String? actionAt = _attReqActionAtText(record);

    return GestureDetector(
      onTap: () async {
        final shiftFlex = await _resolvedShiftFlexInfoForRecord(record);
        if (!mounted) return;
        final shiftInfo = shiftFlex['shift'] ?? (displayShift ?? '—');
        final flexInfo = shiftFlex['flexi'] ?? flexDisplayValue;
        final detailStatus = _attReqStatusText(record);
        final detailActionLabel = _attReqActionLabel(record);
        final detailActionBy = _attReqActionByName(record);
        final detailActionAt = _attReqActionAtText(record);
        final attachmentEntries = _attachmentEntriesForRecord(record);
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      "Attendance Correction Request",
                      maxLines: 3,
                      softWrap: true,
                      // Avoid truncation on smaller screens.
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.95,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kvBlock(
                        'Employee',
                        (fullName ?? '').toString().trim().isEmpty ? '—' : (fullName ?? '').toString(),
                      ),
                      if (detailStatus != null) _kvBlock('Status', detailStatus!),
                      ...(() {
                        if (detailActionLabel == null || detailActionBy == null) return <Widget>[];
                        return <Widget>[
                          _kvBlock(detailActionLabel!, detailActionBy!),
                          if (detailActionAt != null) _kvBlock('Action At', detailActionAt!),
                        ];
                      })(),
                      _kvBlock('Date', (record['attendance_date'] ?? '—').toString()),
                      _kvBlock('Scope', displayScope),
                      if (proposedCheckIn != null) _kvBlock('Proposed Check In', _displayTimeHHMM(proposedCheckIn)),
                      if (proposedCheckIn == null) _kvBlock('Check In', _displayTimeHHMM(displayCheckIn)),
                      if (proposedCheckOut != null) _kvBlock('Proposed Check Out', _displayTimeHHMM(proposedCheckOut)),
                      if (proposedCheckOut == null) _kvBlock('Check Out', _displayTimeHHMM(displayCheckOut)),
                      if (proposedCheckInDate != null) _kvBlock('Proposed Check In Date', proposedCheckInDate),
                      if (proposedCheckInDate == null) _kvBlock('Check In Date', displayCheckInDate ?? '—'),
                      if (proposedCheckOutDate != null) _kvBlock('Proposed Check Out Date', proposedCheckOutDate),
                      if (proposedCheckOutDate == null) _kvBlock('Check Out Date', displayCheckOutDate ?? '—'),
                      if (proposedCheckIn != null && finalCheckIn != null && finalCheckIn != proposedCheckIn)
                        _kvBlock('Final Check In', _displayTimeHHMM(finalCheckIn)),
                      if (proposedCheckOut != null && finalCheckOut != null && finalCheckOut != proposedCheckOut)
                        _kvBlock('Final Check Out', _displayTimeHHMM(finalCheckOut)),
                      if (proposedCheckInDate != null && finalCheckInDate != null && finalCheckInDate != proposedCheckInDate)
                        _kvBlock('Final Check In Date', finalCheckInDate),
                      if (proposedCheckOutDate != null && finalCheckOutDate != null && finalCheckOutDate != proposedCheckOutDate)
                        _kvBlock('Final Check Out Date', finalCheckOutDate),
                      _kvBlock('Shift Information', shiftInfo),
                      _kvBlock('Flex In', flexInfo),
                      if ((record['request_description'] ?? record['reason'] ?? '').toString().trim().isNotEmpty)
                        _kvBlock('Reason / Note', (record['request_description'] ?? record['reason']).toString(), bottom: attachmentEntries.isEmpty ? 0 : 6),
                      if ((record['request_description'] ?? record['reason'] ?? '').toString().trim().isEmpty)
                        SizedBox(height: attachmentEntries.isEmpty ? 0 : 6),
                      if (attachmentEntries.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Attachments',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        ...List<Widget>.from(
                          attachmentEntries.map((entry) {
                            final name = entry.name.trim().isEmpty ? 'attachment' : entry.name.trim();
                            final canDeleteAttachment = isMyRequest && (detailStatus ?? '').toUpperCase() == 'WAITING';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.attach_file, size: 18, color: Colors.black54),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        try {
                                          await openMobileAttachment(context, entry, baseUrl: baseUrl);
                                        } catch (_) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Failed to open attachment.')),
                                          );
                                        }
                                      },
                                      child: Text(
                                        name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          decoration: TextDecoration.underline,
                                          color: Colors.blue,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.open_in_new, size: 16, color: Colors.black45),
                                  if (canDeleteAttachment)
                                    IconButton(
                                      tooltip: 'Delete attachment',
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                      onPressed: () async {
                                        await _deleteAttendanceAttachment(entry);
                                        if (!mounted) return;
                                        Navigator.of(context).pop(true);
                                      },
                                    ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                // Legacy source-regression guard: if (isMyRequest && (detailStatus ?? '').toUpperCase() == 'WAITING')
                if (canShowAttendanceRequestCancelAction(
                  isMyRequest: isMyRequest,
                  status: detailStatus,
                ))
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 220,
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _openAttendanceRequestEditor(record);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                            child: const Text('Edit', style: TextStyle(fontSize: 18, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 220,
                          child: ElevatedButton(
                            onPressed: () async {
                              await cancelAttendanceRequest(record['id']);
                              if (!mounted) return;
                              Navigator.of(context).pop(true);
                              showCancelAnimation();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                            child: const Text(
                              'Cancel Request',
                              style: TextStyle(fontSize: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Legacy source-regression guard: if (showApprovalActions && (detailStatus ?? '').toUpperCase() == 'WAITING')
                if (canShowAttendanceRequestApproveRejectActions(
                  canApproveAttendanceRequests: canApproveAttendanceRequests,
                  isMyRequest: isMyRequest,
                  status: detailStatus,
                ))
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          await _showRejectReasonDialog(record['id']);
                          if (!mounted) return;
                          Navigator.of(context).pop(true);
                          showRejectAnimation();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: const Text('Reject', style: TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                      SizedBox(width: MediaQuery.of(context).size.width * 0.01),
                      ElevatedButton(
                        onPressed: () async {
                          await approveRequest(record['id']);
                          if (!mounted) return;
                          Navigator.of(context).pop(true);
                          showValidateAnimation();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: const Text('Approve', style: TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                    ],
                  ),
                // Legacy source-regression guard: if (showApprovalActions && (detailStatus ?? '').toUpperCase() == 'APPROVED')
                if (canShowAttendanceRequestRevokeAction(
                  canApproveAttendanceRequests: canApproveAttendanceRequests,
                  isMyRequest: isMyRequest,
                  status: detailStatus,
                ))
                  ElevatedButton(
                    onPressed: () async {
                      final reason = await _promptAttendanceRequestReason(title: 'Revoke Request', hintText: 'Reason for revoke');
                      if (reason == null || reason.trim().isEmpty) return;
                      await revokeAttendanceRequest(record['id'], reason: reason);
                      if (!mounted) return;
                      Navigator.of(context).pop(true);
                      showRejectAnimation();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    child: const Text('Revoke', style: TextStyle(fontSize: 18, color: Colors.white)),
                  ),
              ],
            );
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[50]!),
            borderRadius: BorderRadius.circular(8.0),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade400.withOpacity(0.3),
                spreadRadius: 2,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
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
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName ?? '',
                              style: const TextStyle(
                                  fontSize: 16.0, fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (status != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _attReqStatusColor(status!).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status!,
                            style: TextStyle(
                              color: _attReqStatusColor(status!),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.005),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Date',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      Text('${record['attendance_date'] ?? 'None'}'),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Check In',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      Text(_displayTimeHHMM(displayCheckIn)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Check Out',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      Text(_displayTimeHHMM(displayCheckOut)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Scope',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      Text(displayScope),
                    ],
                  ),
                  FutureBuilder<Map<String, String>>(
                    future: _resolvedShiftFlexInfoForRecord(record),
                    builder: (context, snapshot) {
                      final resolvedShift = snapshot.data?['shift'] ?? shiftDisplayValue;
                      final resolvedFlex = snapshot.data?['flexi'] ?? flexDisplayValue;
                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Shift',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              Flexible(
                                child: Text(
                                  resolvedShift,
                                  textAlign: TextAlign.end,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Flex In',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              Flexible(
                                child: Text(
                                  resolvedFlex,
                                  textAlign: TextAlign.end,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  ...(() {
                    if (actionLabel == null || actionBy == null) return <Widget>[];
                    final line = actionAt == null
                        ? '$actionLabel: $actionBy'
                        : '$actionLabel: $actionBy • $actionAt';
                    return <Widget>[
                      const SizedBox(height: 4),
                      Text(
                        line,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ];
                  })(),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                  if (canShowAttendanceRequestApproveRejectActions(
                    canApproveAttendanceRequests: canApproveAttendanceRequests,
                    isMyRequest: isMyRequest,
                    status: _attReqStatusText(record),
                  ))
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            await _showRejectReasonDialog(record['id']);
                            showRejectAnimation();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          child: const Text('Reject', style: TextStyle(fontSize: 18, color: Colors.white)),
                        ),
                        SizedBox(width: MediaQuery.of(context).size.width * 0.02),
                        ElevatedButton(
                          onPressed: () async {
                            await approveRequest(record['id']);
                            showValidateAnimation();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          child: const Text('Approve', style: TextStyle(fontSize: 18, color: Colors.white)),
                        ),
                      ],
                    ),
                  if (canShowAttendanceRequestRevokeAction(
                    canApproveAttendanceRequests: canApproveAttendanceRequests,
                    isMyRequest: isMyRequest,
                    status: _attReqStatusText(record),
                  ))
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            final reason = await _promptAttendanceRequestReason(title: 'Revoke Request', hintText: 'Reason for revoke');
                            if (reason == null || reason.trim().isEmpty) return;
                            await revokeAttendanceRequest(record['id'], reason: reason);
                            showRejectAnimation();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          child: const Text('Revoke', style: TextStyle(fontSize: 18, color: Colors.white)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildMyAllAttendance(
      Map<String, dynamic> record, fullName, String profile, baseUrl, token) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[50]!),
          borderRadius: BorderRadius.circular(8.0),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade400.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
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
                          if (record['employee_profile_url'] != null &&
                              record['employee_profile_url'].isNotEmpty)
                            Positioned.fill(
                              child: ClipOval(
                                child: AuthenticatedNetworkImage(
                                  imageUrl: record['employee_profile_url'],
                                  baseUrl: baseUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: const Icon(Icons.person,
                                      color: Colors.grey),
                                ),
                              ),
                            ),
                          if (record['employee_profile_url'] == null ||
                              record['employee_profile_url'].isEmpty)
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
                    SizedBox(width: MediaQuery.of(context).size.width * 0.01),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName ?? '',
                            style: const TextStyle(
                                fontSize: 16.0, fontWeight: FontWeight.bold),
                            maxLines: 2,
                          ),
                          Text(
                            record['badge_id'] != null
                                ? '${record['badge_id']}'
                                : '',
                            style: const TextStyle(
                                fontSize: 12.0, fontWeight: FontWeight.normal),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.005),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Date',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    Text('${record['attendance_date'] ?? 'None'}'),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Check In',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    Text(_displayTimeHHMM(record['attendance_clock_in'])),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Shift',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    (() {
                      final sid = _idOf(record['shift_id']);
                      final name = _cleanValue(record['shift_name']);
                      final time = (sid != null) ? shiftTimeRangeById[sid] : null;
                      final display = (time != null && name != null) ? '$time ($name)' : (time ?? name);
                      return Text(display ?? '—');
                    })(),
                  ],
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/my_attendance_view',
                            arguments: {
                              'id': record['id'],
                              'employee_name': record['employee_first_name'] +
                                  ' ' +
                                  record['employee_last_name'],
                              'badge_id': record['badge_id'],
                              'shift_name': record['shift_name'],
                              'attendance_date': record['attendance_date'],
                              'attendance_clock_in_date':
                              record['attendance_clock_in_date'],
                              'attendance_clock_in':
                              _displayTimeHHMM(record['attendance_clock_in']),
                              'attendance_clock_out_date':
                              record['attendance_clock_out_date'],
                              'attendance_clock_out':
                              _displayTimeHHMM(record['attendance_clock_out']),
                              'attendance_worked_hour':
                              record['attendance_worked_hour'],
                              'minimum_hour': record['minimum_hour'],
                              'employee_profile':
                              record['employee_profile_url'],
                              'permission_check': permissionCheck,
                            });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        padding: EdgeInsets.symmetric(
                            horizontal:
                            MediaQuery.of(context).size.width * 0.04,
                            vertical:
                            MediaQuery.of(context).size.height * 0.01),
                      ),
                      child: const Text(
                        "View Attendance",
                        style: TextStyle(fontSize: 18, color: Colors.red),
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
}

class _TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;

    if (text.length == 1 && int.tryParse(text)! > 2) {
      return TextEditingValue(
          text: '0$text:', selection: const TextSelection.collapsed(offset: 3));
    } else if (text.length == 3) {
      return TextEditingValue(
          text: '${text.substring(0, 2)}:${text.substring(2)}',
          selection: const TextSelection.collapsed(offset: 4));
    } else if (text.length == 4) {
      return TextEditingValue(
          text: '${text.substring(0, 2)}:${text.substring(2)}',
          selection: const TextSelection.collapsed(offset: 5));
    } else if (text.length > 5) {
      return TextEditingValue(
        text: text.substring(0, 5),
        selection: const TextSelection.collapsed(offset: 5),
      );
    }
    return newValue;
  }
}