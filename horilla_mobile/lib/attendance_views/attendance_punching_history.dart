import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

class AttendancePunchingHistoryPage extends StatefulWidget {
  const AttendancePunchingHistoryPage({super.key});

  @override
  State<AttendancePunchingHistoryPage> createState() =>
      _AttendancePunchingHistoryPageState();
}

class _AttendancePunchingHistoryPageState
    extends State<AttendancePunchingHistoryPage> {
  String _baseUrl = '';
  String _token = '';
  int? _currentEmployeeId;
  String _currentEmployeeName = '';

  Map<String, dynamic> _profileArguments = {};

  bool _permissionAttendanceRequest = false;

  final TextEditingController _employeeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final NotchBottomBarController _bottomController =
  NotchBottomBarController(index: -1);

  final List<_EmployeeOption> _employeeOptions = [];
  final List<PunchingHistoryItem> _items = [];

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String? _selectedEmployeeId;
  bool _showEmployeeFilter = false;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _nextPageUrl;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleListScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _employeeController.dispose();
    _scrollController.removeListener(_handleListScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();

    final typedUrl = prefs.getString('typed_url') ?? '';
    final token = prefs.getString('token') ?? '';
    final int? employeeId = prefs.getInt('employee_id') ??
        int.tryParse(prefs.getString('employee_id') ?? '');

    setState(() {
      _baseUrl = typedUrl;
      _token = token;
      _currentEmployeeId = employeeId;
      _selectedEmployeeId = employeeId?.toString();
      _permissionAttendanceRequest =
          prefs.getBool('perm_attendance_request') ?? false;
    });

    await _loadCurrentEmployeeProfile();
    await _fetchPunchingHistory(showLoader: true, reset: true);
  }

  Future<http.Response?> _safeGet(Uri uri) async {
    if (_token.isEmpty) return null;
    try {
      return await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _parseBoolLike(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' ||
        text == '1' ||
        text == 'yes' ||
        text == 'y' ||
        text == 'on';
  }

  String _cleanNamePart(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower == 'none' || lower == 'null') return '';
    return s;
  }

  String _cleanDisplayName(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final normalized = raw
        .split(RegExp(r'\s+'))
        .map(_cleanNamePart)
        .where((part) => part.isNotEmpty)
        .join(' ')
        .trim();
    return normalized;
  }

  bool _shouldShowEmployeeFilter(
      List<_EmployeeOption> options,
      dynamic showEmployeeFilterValue,
      ) {
    if (_parseBoolLike(showEmployeeFilterValue)) {
      return true;
    }

    if (options.length > 1) {
      return true;
    }

    final currentId = (_currentEmployeeId ?? '').toString();
    return options.any((option) {
      final optionId = option.id.trim();
      return optionId.toLowerCase() == 'all' || optionId != currentId;
    });
  }

  Future<void> _loadCurrentEmployeeProfile() async {
    final employeeId = _currentEmployeeId;
    if (employeeId == null || _baseUrl.isEmpty || _token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _currentEmployeeName = employeeId == null ? '' : 'Employee #$employeeId';
        _employeeController.text = _currentEmployeeName;
        _profileArguments = employeeId == null ? {} : {'employee_id': employeeId};
      });
      return;
    }

    final uri = Uri.parse('$_baseUrl/api/employee/employees/$employeeId/');
    final res = await _safeGet(uri);

    if (res != null && res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final first = _cleanNamePart(data['employee_first_name']);
      final last = _cleanNamePart(data['employee_last_name']);
      final name = [first, last].where((e) => e.isNotEmpty).join(' ').trim();

      if (!mounted) return;
      setState(() {
        _currentEmployeeName = name.isEmpty ? 'Employee #$employeeId' : name;
        _employeeController.text = _currentEmployeeName;
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

  Uri _buildFirstPageUri() {
    final query = <String, String>{
      'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
      'end_date': DateFormat('yyyy-MM-dd').format(_endDate),
    };

    if (_selectedEmployeeId != null && _selectedEmployeeId!.trim().isNotEmpty) {
      query['employee_id'] = _selectedEmployeeId!;
    }

    return Uri.parse('$_baseUrl/api/attendance/punching-history/').replace(
      queryParameters: query,
    );
  }

  Future<void> _fetchPunchingHistory({
    required bool showLoader,
    required bool reset,
    String? pageUrl,
  }) async {
    if (_baseUrl.isEmpty || _token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'Missing configuration. Please login again.';
        _isLoading = false;
        _isRefreshing = false;
        _isLoadingMore = false;
      });
      return;
    }

    if (reset) {
      if (showLoader) {
        setState(() {
          _isLoading = true;
          _error = null;
          _nextPageUrl = null;
        });
      } else {
        setState(() {
          _isRefreshing = true;
          _error = null;
        });
      }
    } else {
      if (_isLoadingMore || _nextPageUrl == null) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    final uri = pageUrl != null ? Uri.parse(pageUrl) : _buildFirstPageUri();
    final res = await _safeGet(uri);

    if (res == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _isLoadingMore = false;
        if (reset) _items.clear();
        _error = reset ? 'Request timeout / network error' : _error;
      });
      if (!reset) _showSnack('Failed to load more data');
      return;
    }

    if (res.statusCode != 200) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _isLoadingMore = false;
        if (reset) _items.clear();
        _error = reset ? 'Failed to load (HTTP ${res.statusCode})' : _error;
      });
      if (!reset) _showSnack('Failed to load more data');
      return;
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> results = (decoded['results'] as List?) ?? const [];
    final fetchedItems = results
        .whereType<Map<String, dynamic>>()
        .map(PunchingHistoryItem.fromJson)
        .toList();

    final employeeOptions = ((decoded['employee_options'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) {
      final id = (e['id'] ?? '').toString().trim();
      final cleanedName = _cleanDisplayName(e['name']);
      final name = cleanedName.isEmpty
          ? (id.toLowerCase() == 'all' ? 'All Employee' : 'Employee #$id')
          : cleanedName;
      return _EmployeeOption(id: id, name: name);
    })
        .where((e) => e.id.isNotEmpty)
        .toList();

    final selectedEmployeeId = (decoded['selected_employee_id'] ?? '')
        .toString()
        .trim();
    final shouldShowEmployeeFilter = _shouldShowEmployeeFilter(
      employeeOptions,
      decoded['show_employee_filter'],
    );

    String? nextSelectedEmployeeId = _selectedEmployeeId;
    if (selectedEmployeeId.isNotEmpty) {
      nextSelectedEmployeeId = selectedEmployeeId;
    }

    final hasSelectedOption = employeeOptions.any(
          (option) => option.id == nextSelectedEmployeeId,
    );

    if (shouldShowEmployeeFilter && employeeOptions.isNotEmpty && !hasSelectedOption) {
      _EmployeeOption? fallbackOption;

      for (final option in employeeOptions) {
        if (option.id.trim().toLowerCase() == 'all') {
          fallbackOption = option;
          break;
        }
      }

      fallbackOption ??= employeeOptions.first;
      nextSelectedEmployeeId = fallbackOption.id;
    }

    if (!mounted) return;
    setState(() {
      if (reset) {
        _items
          ..clear()
          ..addAll(fetchedItems);
      } else {
        _items.addAll(fetchedItems);
      }

      _nextPageUrl = decoded['next']?.toString();
      _showEmployeeFilter = shouldShowEmployeeFilter;
      _employeeOptions
        ..clear()
        ..addAll(employeeOptions);
      _selectedEmployeeId = nextSelectedEmployeeId;

      final selected = _employeeOptions.cast<_EmployeeOption?>().firstWhere(
            (e) => e?.id == _selectedEmployeeId,
        orElse: () => null,
      );

      if (selected != null) {
        _employeeController.text = selected.name;
      } else {
        _employeeController.text = _currentEmployeeName;
      }

      _isLoading = false;
      _isRefreshing = false;
      _isLoadingMore = false;
      _error = null;
    });
  }

  Future<void> _refresh() async {
    await _fetchPunchingHistory(showLoader: false, reset: true);
  }

  void _handleListScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 180 &&
        !_scrollController.position.outOfRange &&
        !_isLoading &&
        !_isLoadingMore &&
        _nextPageUrl != null) {
      _fetchPunchingHistory(
        showLoader: false,
        reset: false,
        pageUrl: _nextPageUrl,
      );
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;

    setState(() {
      _startDate = picked;
      if (_startDate.isAfter(_endDate)) {
        _endDate = _startDate;
      }
    });

    await _fetchPunchingHistory(showLoader: true, reset: true);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;

    setState(() {
      _endDate = picked;
      if (_endDate.isBefore(_startDate)) {
        _startDate = _endDate;
      }
    });

    await _fetchPunchingHistory(showLoader: true, reset: true);
  }

  String _absoluteUrl(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '$_baseUrl$raw';
  }

  Future<void> _openMap(String url) async {
    final raw = url.trim();
    if (raw.isEmpty) return;
    final uri = Uri.parse(raw);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _showPhotoPreview(PunchingHistoryItem item) async {
    if ((item.photoUrl ?? '').trim().isEmpty) return;

    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: const Text('Punch Photo'),
                actions: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    _absoluteUrl(item.photoUrl),
                    headers: {
                      'Authorization': 'Bearer $_token',
                    },
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('-', textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
        title: const Text('Punching History'),
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
              onRefresh: _refresh,
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
        padding: EdgeInsets.zero,
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
            title: const Text('Attendances'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/attendance_attendance');
            },
          ),
          ListTile(
            title: const Text('Punching History'),
            onTap: () {
              Navigator.pop(context);
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
        bottomBarWidth: MediaQuery.of(context).size.width,
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
                      icon: Icons.calendar_today_outlined,
                      label: DateFormat('dd MMM yyyy').format(_startDate),
                      onTap: _pickStartDate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FilterChipButton(
                      icon: Icons.event,
                      label: DateFormat('dd MMM yyyy').format(_endDate),
                      onTap: _pickEndDate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Employee',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              _showEmployeeFilter
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

                  await _fetchPunchingHistory(showLoader: true, reset: true);
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
    final bottomPad = MediaQuery.of(context).padding.bottom + 96;

    if (_isLoading) {
      return _buildShimmerList(bottomPad: bottomPad);
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
                    onPressed: () =>
                        _fetchPunchingHistory(showLoader: true, reset: true),
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

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('No punching history found')),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
      itemCount: _items.length + (_isRefreshing ? 1 : 0) + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isRefreshing && index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        final adjustedIndex = _isRefreshing ? index - 1 : index;
        if (adjustedIndex >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return _PunchHistoryCard(
          item: _items[adjustedIndex],
          token: _token,
          absoluteUrl: _absoluteUrl,
          onOpenMap: _openMap,
          onOpenPhoto: _showPhotoPreview,
        );
      },
    );
  }

  Widget _buildShimmerList({required double bottomPad}) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
      itemCount: 6,
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
                  Container(
                    height: 16,
                    width: 180,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(height: 52, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(height: 52, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(height: 52, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(height: 52, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PunchingHistoryItem {
  final int id;
  final String punchDate;
  final String punchTime;
  final String source;
  final String decisionStatus;
  final String decisionSource;
  final String workMode;
  final bool showDecisionSource;
  final bool showWorkMode;
  final String deviceInfo;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final String locationDisplay;
  final String? googleMapsUrl;
  final bool acceptedToAttendance;
  final String reason;

  PunchingHistoryItem({
    required this.id,
    required this.punchDate,
    required this.punchTime,
    required this.source,
    required this.decisionStatus,
    required this.decisionSource,
    required this.workMode,
    required this.showDecisionSource,
    required this.showWorkMode,
    required this.deviceInfo,
    required this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.locationDisplay,
    required this.googleMapsUrl,
    required this.acceptedToAttendance,
    required this.reason,
  });

  factory PunchingHistoryItem.fromJson(Map<String, dynamic> json) {
    double? parseCoord(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    String safeText(dynamic value) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return '-';
      return text;
    }

    String? safePhotoUrl(dynamic value) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty) return null;

      final lowered = text.toLowerCase();
      if (lowered == 'null' || lowered == 'none' || lowered == '-') {
        return null;
      }

      return text;
    }

    return PunchingHistoryItem(
      id: int.tryParse((json['id'] ?? '').toString()) ?? 0,
      punchDate: safeText(json['punch_date']),
      punchTime: safeText(json['punch_time']),
      source: safeText(json['source']),
      decisionStatus: safeText(json['decision_status']),
      decisionSource: safeText(json['decision_source']),
      workMode: safeText(json['work_mode']),
      showDecisionSource: json.containsKey('decision_source'),
      showWorkMode: json.containsKey('work_mode'),
      deviceInfo: safeText(json['device_info']),
      photoUrl: safePhotoUrl(json['photo_url']),
      latitude: parseCoord(json['latitude']),
      longitude: parseCoord(json['longitude']),
      locationDisplay: safeText(json['location_display']),
      googleMapsUrl: (json['google_maps_url'] ?? '').toString().trim().isEmpty
          ? null
          : json['google_maps_url'].toString().trim(),
      acceptedToAttendance: json['accepted_to_attendance'] == true,
      reason: safeText(json['reason']),
    );
  }
}

class _PunchHistoryCard extends StatelessWidget {
  final PunchingHistoryItem item;
  final String token;
  final String Function(String?) absoluteUrl;
  final Future<void> Function(String) onOpenMap;
  final Future<void> Function(PunchingHistoryItem) onOpenPhoto;

  const _PunchHistoryCard({
    required this.item,
    required this.token,
    required this.absoluteUrl,
    required this.onOpenMap,
    required this.onOpenPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acceptedColor = item.acceptedToAttendance
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.errorContainer;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatDate(item.punchDate)} • ${item.punchTime}',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _HeaderMetaCell(
                    label: 'Source',
                    value: item.source,
                    icon: Icons.input_outlined,
                    backgroundColor:
                    theme.colorScheme.primaryContainer.withOpacity(0.45),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeaderMetaCell(
                    label: 'Decision',
                    value: item.decisionStatus,
                    icon: item.acceptedToAttendance
                        ? Icons.check_circle_outline
                        : Icons.rule_outlined,
                    backgroundColor: acceptedColor.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ],
        ),
        children: [
          _InfoCell(
            label: 'Reason',
            value: item.reason,
            multiline: true,
          ),
          const SizedBox(height: 12),
          if (item.showDecisionSource) ...[
            _InfoCell(
              label: 'Decision Source',
              value: item.decisionSource,
              multiline: true,
            ),
            const SizedBox(height: 12),
          ],
          if (item.showWorkMode) ...[
            _InfoCell(
              label: 'Work Mode',
              value: item.workMode,
            ),
            const SizedBox(height: 12),
          ],
          _InfoCell(
            label: 'Device Info',
            value: item.deviceInfo,
            multiline: true,
          ),
          const SizedBox(height: 12),
          _DetailBlock(
            label: 'Location',
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    item.locationDisplay,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.googleMapsUrl != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => onOpenMap(item.googleMapsUrl!),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open Map'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _DetailBlock(
            label: 'Photo',
            child: item.photoUrl == null
                ? const Center(child: Text('-'))
                : InkWell(
              onTap: () => onOpenPhoto(item),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: 140,
                  maxHeight: 180,
                ),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.45),
                ),
                child: Image.network(
                  absoluteUrl(item.photoUrl),
                  headers: {
                    'Authorization': 'Bearer $token',
                  },
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('-'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(String raw) {
    if (raw.trim().isEmpty || raw.trim() == '-') return '-';
    final dt = DateTime.tryParse(raw.trim());
    if (dt == null) return raw;
    return DateFormat('dd MMM yyyy').format(dt);
  }
}

class _EmployeeOption {

  final String id;
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
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        alignment: Alignment.centerLeft,
      ),
    );
  }
}

class _HeaderMetaCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color backgroundColor;

  const _HeaderMetaCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: backgroundColor,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String label;
  final Widget child;

  const _DetailBlock({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
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
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;
  final bool centered;

  const _InfoCell({
    required this.label,
    required this.value,
    this.multiline = false,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment:
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            maxLines: multiline ? null : 2,
            overflow: multiline ? TextOverflow.visible : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EmployeePickerDialog extends StatefulWidget {
  final List<_EmployeeOption> options;
  final String? initialSelectedId;

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
        : widget.options
        .where((e) => e.name.toLowerCase().contains(q))
        .toList();

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
