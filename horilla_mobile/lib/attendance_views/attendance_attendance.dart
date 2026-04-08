import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:open_file/open_file.dart';

/// Attendance -> Attendance
///
/// NOTE:
/// - UI only (mobile DOES NOT calculate shift/late/earlyout/duty/holiday/correction).
/// - All values are displayed as returned by backend.
/// - Data source: GET {typed_url}/api/attendance/attendances-recap/?employee_id=<id>&month=YYYY-MM
class AttendanceAttendance extends StatefulWidget {
  const AttendanceAttendance({super.key});

  @override
  State<AttendanceAttendance> createState() => _AttendanceAttendanceState();
}

class _AttendanceAttendanceState extends State<AttendanceAttendance> {
  // SharedPreferences values
  String _baseUrl = '';
  String _token = '';
  int? _currentEmployeeId;

  // Used by bottom navigation to open Profile page.
  Map<String, dynamic> _profileArguments = {};

  // Drawer permissions (follow existing app pattern)
  bool _permissionOverview = false;
  bool _permissionAttendanceRequest = false;

  // Filters
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final DateFormat _monthFormat = DateFormat('yyyy-MM');

  // Employee selector
  bool _canSelectEmployee = false;
  int? _selectedEmployeeId;
  String _currentEmployeeName = '';
  final TextEditingController _employeeController = TextEditingController();
  final List<_EmployeeOption> _employeeOptions = [];

  // Bottom navigation
  final NotchBottomBarController _bottomController = NotchBottomBarController(index: -1);
  final int _maxCount = 5;

  // Data state
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isExporting = false;
  String? _error;
  List<MonthlyAttendanceRow> _rows = [];
  MonthlyAttendanceSummary _summary = const MonthlyAttendanceSummary();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _employeeController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();

    final typedUrl = prefs.getString('typed_url') ?? '';
    final token = prefs.getString('token') ?? '';

    final int? employeeId = prefs.getInt('employee_id') ??
        int.tryParse(prefs.getString('employee_id') ?? '');

    // Load permissions already stored by the app (same keys as the legacy page)
    final permOverview = prefs.getBool('perm_overview') ?? false;
    final permAttReq = prefs.getBool('perm_attendance_request') ?? false;

    setState(() {
      _baseUrl = typedUrl;
      _token = token;
      _currentEmployeeId = employeeId;
      _selectedEmployeeId = null;

      _permissionOverview = permOverview;
      _permissionAttendanceRequest = permAttReq;

      // Spec: employee selector only for admin/HR.
      // We determine this reliably via backend permission check (employee.view_employee).
      _canSelectEmployee = false;
    });

    await _loadCurrentEmployeeProfile();

    await _fetchMonthlyAttendance(showLoader: true);
  }

  Future<http.Response?> _safeGet(Uri uri) async {
    if (_token.isEmpty) return null;
    try {
      return await http
          .get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      })
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCurrentEmployeeProfile() async {
    final employeeId = _currentEmployeeId;
    if (employeeId == null || _baseUrl.isEmpty || _token.isEmpty) {
      setState(() {
        _currentEmployeeName = employeeId == null ? '' : 'Employee #$employeeId';
        _employeeController.text = _currentEmployeeName;
        _profileArguments = employeeId == null ? {} : {'employee_id': employeeId};
      });
      return;
    }

    // Use trailing slash to avoid 301.
    final uri = Uri.parse('$_baseUrl/api/employee/employees/$employeeId/');
    final res = await _safeGet(uri);

    if (res != null && res.statusCode == 200) {
      final data = jsonDecode(res.body);

      final first = (data['employee_first_name'] ?? '').toString();
      final last = (data['employee_last_name'] ?? '').toString();
      final name = ('$first $last').trim();

      if (!mounted) return;
      setState(() {
        _currentEmployeeName = name.isEmpty ? 'Employee #$employeeId' : name;
        _employeeController.text = _currentEmployeeName;

        // Keep same shape as existing code that navigates to EmployeeForm.
        _profileArguments = {
          'employee_id': data['id'] ?? employeeId,
          'employee_name': _currentEmployeeName,
          'badge_id': data['badge_id'],
          'email': data['email'],
          'phone': data['phone'],
          'date_of_birth': data['dob'],
          'gender': data['gender'],
          'address': data['address'],
          'country': data['country'],
          'state': data['state'],
          'city': data['city'],
          'qualification': data['qualification'],
          'experience': data['experience'],
          'marital_status': data['marital_status'],
          'children': data['children'],
          'emergency_contact': data['emergency_contact'],
          'emergency_contact_name': data['emergency_contact_name'],
          'employee_work_info_id': data['employee_work_info_id'],
          'employee_bank_details_id': data['employee_bank_details_id'],
          'employee_profile': data['employee_profile'],
          'job_position_name': data['job_position_name'],
        };
      });
    } else {
      if (!mounted) return;
      setState(() {
        _currentEmployeeName = 'Employee #$employeeId';
        _employeeController.text = _currentEmployeeName;
        _profileArguments = {'employee_id': employeeId};
      });
    }
  }

  Future<void> _pickMonth() async {
    // Month picker (YYYY-MM) - custom lightweight dialog (no extra deps).
    final now = DateTime.now();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        int year = _selectedMonth.year;
        const minYear = 2000;
        final int maxYear = now.year; // cannot pick future years

        String monthLabel(int m) {
          // Uses device locale for month short name.
          return DateFormat('MMM').format(DateTime(2000, m, 1));
        }

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.calendar_month),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Select Month',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous Year',
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        padding: EdgeInsets.zero,
                        onPressed: year > minYear ? () => setStateDialog(() => year -= 1) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            year.toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next Year',
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        padding: EdgeInsets.zero,
                        onPressed: year < maxYear ? () => setStateDialog(() => year += 1) : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int m = 1; m <= 12; m++)
                      ChoiceChip(
                        label: Text(monthLabel(m)),
                        selected: year == _selectedMonth.year && m == _selectedMonth.month,
                        onSelected: (year == now.year && m > now.month)
                            ? null
                            : (_) {
                          Navigator.of(context).pop(DateTime(year, m, 1));
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _selectedMonth = picked;
    });

    await _fetchMonthlyAttendance(showLoader: true);
  }


  Future<void> _fetchMonthlyAttendance({required bool showLoader}) async {
    final employeeId = _selectedEmployeeId;

    if (_baseUrl.isEmpty || _token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _error = 'Missing configuration. Please login again.';
        _rows = [];
        _summary = const MonthlyAttendanceSummary();
      });
      return;
    }

    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _isRefreshing = true;
        _error = null;
      });
    }

    final month = _monthFormat.format(_selectedMonth);

    try {
      final query = <String, String>{'month': month};
      if (employeeId != null) {
        query['employee_id'] = employeeId.toString();
      }
      final uri = Uri.parse('$_baseUrl/api/attendance/attendances-recap/').replace(
        queryParameters: query,
      );

      final res = await _safeGet(uri);

      if (res != null && res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final List<dynamic> rowsJson = (decoded['rows'] as List?) ??
            (decoded['results'] as List?) ??
            (decoded['data'] as List?) ??
            const [];

        final rows = rowsJson
            .whereType<Map<String, dynamic>>()
            .map((e) => MonthlyAttendanceRow.fromJson(e))
            .toList();
        final summaryJson = decoded['summary'];
        final summary = summaryJson is Map<String, dynamic>
            ? MonthlyAttendanceSummary.fromJson(summaryJson)
            : summaryJson is Map
            ? MonthlyAttendanceSummary.fromJson(Map<String, dynamic>.from(summaryJson))
            : const MonthlyAttendanceSummary();

        final employeeOptions = ((decoded['employee_options'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => _EmployeeOption(
                  id: int.tryParse((item['id'] ?? '').toString()) ?? 0,
                  name: (item['name'] ?? '').toString().trim().isEmpty
                      ? 'Employee #${item['id']}'
                      : (item['name'] ?? '').toString(),
                ))
            .where((option) => option.id != 0)
            .toList();

        final dynamic rawSelectedEmployeeId = decoded['selected_employee_id'];
        final int? selectedEmployeeId = rawSelectedEmployeeId is int
            ? rawSelectedEmployeeId
            : int.tryParse(rawSelectedEmployeeId?.toString() ?? '');
        final showEmployeeFilter = decoded['show_employee_filter'] == true;

        if (!mounted) return;
        setState(() {
          _rows = rows;
          _summary = summary;
          _selectedEmployeeId = selectedEmployeeId;
          _canSelectEmployee = showEmployeeFilter;
          _employeeOptions
            ..clear()
            ..addAll(employeeOptions);
          if (_employeeOptions.isEmpty && _currentEmployeeId != null) {
            _employeeOptions.add(
              _EmployeeOption(
                id: _currentEmployeeId!,
                name: _currentEmployeeName.isEmpty
                    ? 'Employee #$_currentEmployeeId'
                    : _currentEmployeeName,
              ),
            );
          }
          final selected = _employeeOptions.cast<_EmployeeOption?>().firstWhere(
                (option) => option?.id == _selectedEmployeeId,
                orElse: () => null,
              );
          _employeeController.text = selected?.name ?? _currentEmployeeName;
          _isLoading = false;
          _isRefreshing = false;
          _error = null;
        });
      } else {
        final msg = res == null ? 'Request timeout / network error' : 'Failed to load (HTTP ${res.statusCode})';
        if (!mounted) return;
        setState(() {
          _rows = [];
          _summary = const MonthlyAttendanceSummary();
          _isLoading = false;
          _isRefreshing = false;
          _error = msg;
        });
        _showSnack(msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _summary = const MonthlyAttendanceSummary();
        _isLoading = false;
        _isRefreshing = false;
        _error = 'Error: $e';
      });
      _showSnack('Failed to load data');
    }
  }


  Future<void> _exportMonthlyAttendancePdf() async {
    if (_isExporting) return;

    final employeeId = _selectedEmployeeId;
    if (_baseUrl.isEmpty || _token.isEmpty) {
      _showSnack('Missing configuration. Please login again.');
      return;
    }

    final lang = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Choose language'),
            SizedBox(height: 12),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('en'),
            child: const Text('English'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('id'),
            child: const Text('Indonesian'),
          ),
        ],
      ),
    );

    if (lang == null) return;

    if (!mounted) return;
    setState(() {
      _isExporting = true;
    });

    _showExportProgressDialog();
    var progressShown = true;

    final month = _monthFormat.format(_selectedMonth);
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/attendance/attendances-recap/export-pdf/?employee_id=$employeeId&month=$month&lang=$lang',
      );

      final res = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (progressShown) {
        Navigator.of(context, rootNavigator: true).pop();
        progressShown = false;
      }

      if (res.statusCode == 200) {
        if (res.bodyBytes.isEmpty) {
          _showSnack('Downloaded file is empty');
          return;
        }

        final file = await _saveExportedPdf(
          bytes: res.bodyBytes,
          month: month,
          employeeId: employeeId ?? _currentEmployeeId ?? 0,
          lang: lang,
        );

        if (!mounted) return;
        await _showExportReadyDialog(file);
        return;
      }

      _showSnack(_exportErrorMessage(res.statusCode));
    } on TimeoutException {
      if (mounted) {
        if (progressShown) {
          Navigator.of(context, rootNavigator: true).pop();
          progressShown = false;
        }
        _showSnack('Download timeout. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        if (progressShown) {
          Navigator.of(context, rootNavigator: true).pop();
          progressShown = false;
        }
        _showSnack('Failed to download PDF');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  void _showExportProgressDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text('Downloading PDF...'),
            ),
          ],
        ),
      ),
    );
  }

  Future<File> _saveExportedPdf({
    required List<int> bytes,
    required String month,
    required int employeeId,
    required String lang,
  }) async {
    final safeMonth = month.replaceAll(RegExp(r'[^0-9-]'), '_');
    final fileName =
        'monthly_attendance_${employeeId}_${safeMonth}_${lang}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final directory = Directory.systemTemp;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _showExportReadyDialog(File file) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF ready'),
        content: Text(file.path.split(Platform.pathSeparator).last),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _shareExportedPdf(file);
            },
            child: const Text('Share'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              final opened = await _openExportedPdf(file);
              if (!opened) {
                _showSnack('Unable to open PDF');
              }
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Open PDF'),
          ),
        ],
      ),
    );
  }

  Future<bool> _openExportedPdf(File file) async {
    try {
      if (!await file.exists()) {
        return false;
      }

      final result = await OpenFile.open(
        file.path,
        type: 'application/pdf',
      );

      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  Future<void> _shareExportedPdf(File file) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Monthly attendance PDF',
        subject: 'Monthly attendance PDF',
      );
    } catch (_) {
      _showSnack('Unable to share PDF');
    }
  }

  String _exportErrorMessage(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'Session expired (401). Please login again.';
      case 403:
        return 'You do not have permission to export this PDF (403).';
      case 500:
        return 'Server failed to generate PDF (500).';
      default:
        return 'Failed to export PDF (HTTP $statusCode).';
    }
  }

  Future<void> _onRefresh() async {
    await _fetchMonthlyAttendance(showLoader: false);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'Punching History',
            onPressed: () => Navigator.pushNamed(context, '/attendance_punching_history'),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      extendBody: true,
      bottomNavigationBar: _buildBottomNav(context),
      body: Column(
        children: [
          _buildFilters(context),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: _buildBody(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
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
          ListTile(
            title: const Text('Attendance'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/attendance_attendance');
            },
          ),
          ListTile(
            title: const Text('Punching History'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/attendance_punching_history');
            },
          ),
          if (_permissionAttendanceRequest)
            ListTile(
              title: const Text('Requests'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/attendance_request');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    // Keep same behavior as legacy page.
    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: AnimatedNotchBottomBar(
        notchBottomBarController: _bottomController,
        color: Colors.red,
        showLabel: true,
        notchColor: Colors.red,
        kBottomRadius: 28.0,
        kIconSize: 24.0,
        removeMargins: false,
        bottomBarWidth: MediaQuery.of(context).size.width * 1,
        durationInMilliSeconds: 300,
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
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushNamed(context, '/home');
              break;
            case 1:
              Navigator.pushNamed(context, '/employee_checkin_checkout');
              break;
            case 2:
              Navigator.pushNamed(
                context,
                '/employees_form',
                arguments: _profileArguments,
              );
              break;
          }
        },
      ),
    );
  }


  Widget _buildFilters(BuildContext context) {
    final monthText = _monthFormat.format(_selectedMonth);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _FilterChipButton(
                      icon: Icons.calendar_month,
                      label: monthText,
                      onTap: _pickMonth,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterIconButton(
                    icon: _isExporting ? null : Icons.picture_as_pdf_outlined,
                    tooltip: 'Export PDF',
                    onTap: (_isLoading || _selectedEmployeeId == null || _isExporting)
                        ? null
                        : _exportMonthlyAttendancePdf,
                    child: _isExporting
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Employee',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              _canSelectEmployee
                  ? GestureDetector(
                onTap: () async {
                  if (_employeeOptions.isEmpty) {
                    _showSnack('No employees available');
                    return;
                  }

                  final selected = await showDialog<_EmployeeOption>(
                    context: context,
                    builder: (context) => _EmployeePickerDialog(
                      options: _employeeOptions,
                      initialSelectedId: _selectedEmployeeId,
                    ),
                  );

                  if (selected == null) return;

                  setState(() {
                    _selectedEmployeeId = selected.id;
                    _employeeController.text = selected.name;
                  });

                  await _fetchMonthlyAttendance(showLoader: true);
                },
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: _employeeController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      hintText: 'Select Employee',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
              )
                  : TextFormField(
                controller: _employeeController,
                readOnly: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final bottomPad = _listBottomPadding(context);
    if (_isLoading) {
      return _buildShimmerList(context, bottomPad: bottomPad);
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        children: [
          const SizedBox(height: 64),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _fetchMonthlyAttendance(showLoader: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
      children: [
        if (_isRefreshing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        _MonthlyAttendanceSummarySection(summary: _summary),
        if (_rows.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 28),
            child: Center(child: Text('No data')),
          )
        else
          ..._rows.map((row) => _MonthlyAttendanceCard(row: row)),
      ],
    );
  }

  double _listBottomPadding(BuildContext context) {
    // Push list content above the bottom notch navigation bar.
    // Notch bar height varies; adding 96 keeps the last card visible.
    return MediaQuery.of(context).padding.bottom + 96;
  }

  Widget _buildShimmerList(BuildContext context, {required double bottomPad}) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: 160, color: Colors.white),
                  const SizedBox(height: 12),
                  Container(height: 10, width: double.infinity, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(height: 10, width: double.infinity, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 200, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MonthlyAttendanceRow {
  final int? no;
  final String date;
  final String shiftInformation;
  final String checkIn;
  final String checkOut;
  final String workType;
  final String late;
  final String earlyOut;
  final String lateMinutes;
  final String earlyOutMinutes;
  final String note;
  final bool isOff;

  MonthlyAttendanceRow({
    required this.no,
    required this.date,
    required this.shiftInformation,
    required this.checkIn,
    required this.checkOut,
    required this.workType,
    required this.late,
    required this.earlyOut,
    required this.lateMinutes,
    required this.earlyOutMinutes,
    required this.note,
    required this.isOff,
  });

  factory MonthlyAttendanceRow.fromJson(Map<String, dynamic> json) {
    return MonthlyAttendanceRow(
      no: _toIntOrNull(json['no']),
      date: (json['date'] ?? '').toString(),
      shiftInformation: (json['shift_information'] ?? '').toString(),
      checkIn: (json['check_in'] ?? '').toString(),
      checkOut: (json['check_out'] ?? '').toString(),
      workType: (json['work_type'] ?? '').toString(),
      late: (json['late'] ?? '').toString(),
      earlyOut: (json['early_out'] ?? '').toString(),
      lateMinutes: _toSafeMinuteText(json['late_minutes']),
      earlyOutMinutes: _toSafeMinuteText(json['early_out_minutes']),
      note: (json['note'] ?? '').toString(),
      isOff: (json['is_off'] == true),
    );
  }

  static int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}

class MonthlyAttendanceSummary {
  final String lateMinutes;
  final String earlyOutMinutes;
  final String totalMinutes;

  const MonthlyAttendanceSummary({
    this.lateMinutes = '0',
    this.earlyOutMinutes = '0',
    this.totalMinutes = '0',
  });

  factory MonthlyAttendanceSummary.fromJson(Map<String, dynamic> json) {
    return MonthlyAttendanceSummary(
      lateMinutes: _toSafeMinuteText(json['late_minutes'], fallback: '0'),
      earlyOutMinutes: _toSafeMinuteText(json['early_out_minutes'], fallback: '0'),
      totalMinutes: _toSafeMinuteText(json['total_minutes'], fallback: '0'),
    );
  }
}

String _toSafeMinuteText(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is num) {
    return _normalizeMinuteText(value.toString(), fallback: fallback);
  }
  return _normalizeMinuteText(value.toString(), fallback: fallback);
}

String _normalizeMinuteText(String raw, {String fallback = ''}) {
  final text = raw.trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  final parsed = num.tryParse(text);
  if (parsed == null) return fallback;
  final safe = parsed < 0 ? 0 : parsed;
  final normalized = safe.toString();
  if (!normalized.contains('.')) return normalized;

  // Dart String.replaceFirst/replaceAll use the replacement text literally here,
  // so using r'\1' can leak a trailing "\1" into the output (for example
  // "256.0" -> "256\1"). Use a mapped replacement to keep the captured decimal
  // portion safely and then trim any trailing dot.
  final withoutTrailingZeros = normalized.replaceFirstMapped(
    RegExp(r'([.][0-9]*?)0+$'),
    (match) => match.group(1) ?? '',
  );
  return withoutTrailingZeros.replaceFirst(RegExp(r'[.]$'), '');
}

class _EmployeeOption {
  final int id;
  final String name;

  const _EmployeeOption({required this.id, required this.name});
}

class _FilterChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  final IconData? icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Widget? child;

  const _FilterIconButton({
    this.icon,
    required this.tooltip,
    required this.onTap,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled
        ? Theme.of(context).disabledColor
        : Theme.of(context).colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            alignment: Alignment.center,
            child: child ?? Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

class _MonthlyAttendanceCard extends StatelessWidget {
  final MonthlyAttendanceRow row;

  const _MonthlyAttendanceCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg = row.isOff
        ? theme.colorScheme.surfaceVariant.withOpacity(0.55)
        : theme.colorScheme.surface;

    final titleText = _formatDate(row.date);

    final cleanedShift = _cleanText(row.shiftInformation);
    final shiftLabel = (cleanedShift.trim().isEmpty)
        ? 'No Shift Information'
        : cleanedShift;
    final workTypeLabel = _cleanWorkType(row.workType);

    final checkInText = _formatCheckInOut(_cleanText(row.checkIn), row.date);
    final checkOutText = _formatCheckInOut(_cleanText(row.checkOut), row.date);

    return Card(
      color: bg,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row.no ?? ''}${row.no == null ? '' : '. '} $titleText'.trim(),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (workTypeLabel.isNotEmpty)
                  _Badge(
                    text: workTypeLabel,
                    icon: Icons.badge,
                  ),
                _Badge(
                  text: shiftLabel,
                  icon: Icons.schedule,
                ),
              ],
            ),
          ],
        ),
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InfoCell(
                  label: 'Check In',
                  value: checkInText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoCell(
                  label: 'Check Out',
                  value: checkOutText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoCell(
                  label: 'Late',
                  value: _formatPenaltyText(row.lateMinutes, row.late),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoCell(
                  label: 'Early Out',
                  value: _formatPenaltyText(row.earlyOutMinutes, row.earlyOut),
                ),
              ),
            ],
          ),
          if (row.note.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _InfoCell(
                label: 'Note',
                value: _cleanText(row.note),
                multiline: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Attempts to remove odd characters coming from backend responses.
  /// - strips HTML tags
  /// - decodes common HTML entities
  /// - removes NBSP/zero-width
  /// - fixes common mojibake (UTF-8 mis-decoded as latin1)
  static String _cleanText(String input) {
    var s = input;
    if (s.isEmpty) return s;

    // Remove HTML tags.
    s = s.replaceAll(RegExp(r'<[^>]*>'), ' ');

    // Decode common HTML entities.
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");

    // Remove NBSP and zero-width characters.
    s = s
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp('[\u200B-\u200D\uFEFF]'), ' ');

    // Fix common mojibake patterns.
    if (s.contains('Ã') || s.contains('Â') || s.contains('â')) {
      try {
        final bytes = latin1.encode(s);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        s = decoded;
      } catch (_) {
        s = s.replaceAll('Â', '');
      }
    }

    // Normalize fancy dashes/quotes.
    s = s
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'");

    // Collapse whitespace.
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _cleanWorkType(String raw) {
    final t = _cleanText(raw);
    if (t.isEmpty || t.toLowerCase() == 'null') return '-';

    // For holiday / no-work-type rows, show a normal dash just like Check In / Check Out
    // instead of rendering odd punctuation or mojibake characters.
    if (!RegExp(r'[A-Za-z0-9]').hasMatch(t)) return '-';

    return t;
  }

  static String _safeText(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t.toLowerCase() == 'null') return '-';
    return t;
  }


  static String _formatPenaltyText(String minuteValue, String legacyValue) {
    final minuteText = minuteValue.trim();
    if (minuteText.isNotEmpty) {
      return '$minuteText Minutes';
    }
    return _safeText(legacyValue);
  }

  static String _formatDate(String rawDate) {
    final t = rawDate.trim();
    if (t.isEmpty) return '-';
    final dt = DateTime.tryParse(t);
    if (dt == null) return t;
    return DateFormat('dd MMM yyyy').format(dt);
  }

  /// D+1 handling (ONLY for Check In / Check Out on this page):
  /// - If backend already sends "D+1" inside string -> show as-is.
  /// - If backend sends raw datetime (parseable) -> show HH:mm (+ "D+1" if date is next day relative to row.date).
  /// - Else show raw.
  static String _formatCheckInOut(String raw, String rowDate) {
    final v = raw.trim();
    if (v.isEmpty || v.toLowerCase() == 'null') return '-';

    if (v.contains('D+1')) return v;

    // If it's already just a time, show as-is.
    final timeOnly = RegExp(r'^\d{1,2}:\d{2}$');
    if (timeOnly.hasMatch(v)) return v;

    final dt = DateTime.tryParse(v);
    if (dt == null) return v;

    final timeText = DateFormat('HH:mm').format(dt);

    final rd = DateTime.tryParse(rowDate.trim());
    if (rd != null) {
      final rowD = DateTime(rd.year, rd.month, rd.day);
      final dtD = DateTime(dt.year, dt.month, dt.day);
      if (dtD.difference(rowD).inDays == 1) {
        return '$timeText D+1';
      }
    }

    return timeText;
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Badge({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.primaryContainer.withOpacity(0.45),
      ),
      // Use RichText so the badge content can wrap nicely on small screens.
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(icon, size: 14),
            ),
            const WidgetSpan(child: SizedBox(width: 6)),
            TextSpan(text: text),
          ],
        ),
        softWrap: true,
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _InfoCell({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: multiline ? null : 1,
            overflow: multiline ? TextOverflow.visible : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MonthlyAttendanceSummarySection extends StatelessWidget {
  final MonthlyAttendanceSummary summary;

  const _MonthlyAttendanceSummarySection({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryMetricCard(
                  label: 'LATE',
                  minutes: summary.lateMinutes,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMetricCard(
                  label: 'EARLY OUT',
                  minutes: summary.earlyOutMinutes,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SummaryMetricCard(
            label: 'TOTAL LATE + EARLY OUT',
            minutes: summary.totalMinutes,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  final String label;
  final String minutes;
  final bool fullWidth;

  const _SummaryMetricCard({
    required this.label,
    required this.minutes,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: theme.colorScheme.onSurface.withOpacity(0.72),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                '$minutes',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Minutes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.70),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmployeePickerDialog extends StatefulWidget {
  final List<_EmployeeOption> options;
  final int? initialSelectedId;

  const _EmployeePickerDialog({
    required this.options,
    required this.initialSelectedId,
  });

  @override
  State<_EmployeePickerDialog> createState() => _EmployeePickerDialogState();
}

class _EmployeePickerDialogState extends State<_EmployeePickerDialog> {
  late final TextEditingController _controller;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() {
      if (!mounted) return;
      setState(() {
        _query = _controller.text;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final availableHeight = mq.size.height - mq.viewInsets.bottom;
    final dialogHeight = (availableHeight * 0.70).clamp(320.0, 520.0);

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options.where((e) => e.name.toLowerCase().contains(q)).toList();

    return AlertDialog(
      title: const Text('Select Employee'),
      content: SizedBox(
        width: double.maxFinite,
        height: dialogHeight,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Search employee',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No employees found'))
                  : ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final e = filtered[index];
                  final selected = e.id == widget.initialSelectedId;
                  return ListTile(
                    dense: true,
                    title: Text(e.name),
                    trailing: selected ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(context).pop(e),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
