import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../res/utilities/request_payloads.dart';
import '../res/utilities/attachment_access.dart';


class _CreateResult {
  final bool ok;
  final String? message;
  const _CreateResult(this.ok, [this.message]);
}

/// Work Type Requests (WFA / WFH / ON_DUTY)
/// - My Requests: employee creates & can cancel while pending
/// - Approvals: manager/admin can approve/reject
///
/// This widget is meant to be embedded inside AttendanceRequest page.
class WorkModeRequestTab extends StatefulWidget {
  const WorkModeRequestTab({
    super.key,
    required this.searchText,
    this.employeeOptions = const [],
    this.onCountChanged,
  });

  final String searchText;
  final List<Map<String, dynamic>> employeeOptions;
  final ValueChanged<int>? onCountChanged;

  @override
  WorkModeRequestTabState createState() => WorkModeRequestTabState();
}

class WorkModeRequestTabState extends State<WorkModeRequestTab>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {

  void _notifyParentCount() {
    final total = _myCount + _approvalsCount + _approvalHistoryCount;
    widget.onCountChanged?.call(total);
  }

  final ScrollController _myScrollController = ScrollController();
  final ScrollController _approvalsScrollController = ScrollController();
  final ScrollController _approvalHistoryScrollController = ScrollController();
  Timer? _debounce;

  late final TabController _tabController;

  // My requests
  List<Map<String, dynamic>> _myAll = [];
  int _myCount = 0;
  int _myPage = 1;

  // Approvals (manager/admin)
  List<Map<String, dynamic>> _approvalsAll = [];
  int _approvalsCount = 0;
  int _approvalsPage = 1;
  List<Map<String, dynamic>> _approvalHistoryAll = [];
  List<Map<String, dynamic>> _historyEmployeeOptions = [];
  int _approvalHistoryCount = 0;
  int _approvalHistoryPage = 1;

  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingApprovals = false;
  bool _loadingMoreApprovals = false;
  bool _loadingMoreApprovalHistory = false;
  bool _loadingApprovalHistory = false;

  String _myStatus = 'all';
  late String _myMonth = DateFormat('yyyy-MM').format(DateTime.now());
  String _historyStatus = 'all';
  String _historyEmployeeId = '';
  late String _historyMonth = DateFormat('yyyy-MM').format(DateTime.now());

  int? _currentEmployeeId;
  bool _canApprove = false;
  List<PlatformFile> _pickedFiles = [];

  String get _baseUrl => _cachedBaseUrl ?? '';
  String? _cachedBaseUrl;

  static const int _maxAttachmentBytes = 20 * 1024 * 1024;
  static const Set<String> _allowedAttachmentExts = {
    'jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'
  };

  String? _validatePickedFiles(List<PlatformFile> files) {
    for (final f in files) {
      final name = (f.name).trim();
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (!_allowedAttachmentExts.contains(ext)) {
        return 'File type .$ext is not allowed. Allowed: JPG, JPEG, PNG, PDF, DOC, DOCX.';
      }
      if (f.size > _maxAttachmentBytes) {
        return 'File ${name.isEmpty ? 'attachment' : name} is too large. Max 20 MB per file.';
      }
    }
    return null;
  }

  List<MobileAttachmentItem> _attachmentEntries(Map<String, dynamic> r) {
    return extractMobileAttachments(r, baseUrl: _baseUrl);
  }

  String _actionTypeText(Map<String, dynamic> r) {
    final raw = (r['action_type'] ?? '').toString().trim().toUpperCase();
    return raw;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _myScrollController.addListener(_onScroll);
    _approvalsScrollController.addListener(_onApprovalsScroll);
    _approvalHistoryScrollController.addListener(_onApprovalHistoryScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _myScrollController.removeListener(_onScroll);
    _approvalsScrollController.removeListener(_onApprovalsScroll);
    _approvalHistoryScrollController.removeListener(_onApprovalHistoryScroll);
    _myScrollController.dispose();
    _approvalsScrollController.dispose();
    _approvalHistoryScrollController.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedBaseUrl = prefs.getString('typed_url') ?? '';
    _currentEmployeeId = prefs.getInt('employee_id') ??
        int.tryParse(prefs.getString('employee_id') ?? '');
    await _fetchApprovePermission();
    await refreshMy(reset: true);
    await refreshApprovals(reset: true);
    await refreshApprovalHistory(reset: true);
  }

  Future<void> _fetchApprovePermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final typedServerUrl = prefs.getString('typed_url');
      final uri = Uri.parse(
          '$typedServerUrl/api/attendance/permission-check/work-type-request-approve');
      final resp = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
      if (resp.statusCode == 200) {
        try {
          final decoded = jsonDecode(resp.body);
          final can = (decoded is Map && decoded['can_approve'] == true);
          setState(() => _canApprove = can);
        } catch (_) {
          setState(() => _canApprove = false);
        }
      } else {
        setState(() => _canApprove = false);
      }
    } catch (_) {
      setState(() {
        _canApprove = false;
      });
    }
  }

  void _onScroll() {
    if (_tabController.index != 0) return;
    if (_myScrollController.position.pixels >=
        _myScrollController.position.maxScrollExtent - 60 &&
        !_myScrollController.position.outOfRange) {
      _loadMoreMy();
    }
  }

  void _onApprovalsScroll() {
    if (_tabController.index != 1) return;
    if (_approvalsScrollController.position.pixels >=
        _approvalsScrollController.position.maxScrollExtent - 60 &&
        !_approvalsScrollController.position.outOfRange) {
      _loadMoreApprovals();
    }
  }

  void _onApprovalHistoryScroll() {
    if (_tabController.index != 1) return;
    if (_approvalHistoryScrollController.position.pixels >=
        _approvalHistoryScrollController.position.maxScrollExtent - 60 &&
        !_approvalHistoryScrollController.position.outOfRange) {
      _loadMoreApprovalHistory();
    }
  }

  Future<void> _loadMoreMy() async {
    if (_loadingMore || _loading) return;
    // if already loaded all
    if (_myAll.length >= _myCount && _myCount != 0) return;

    setState(() {
      _loadingMore = true;
      _myPage += 1;
    });

    await _fetchMyPage(page: _myPage, append: true);

    setState(() {
      _loadingMore = false;
    });
  }

  Future<void> refreshMy({required bool reset}) async {
    if (reset) {
      setState(() {
        _myPage = 1;
        _myAll = [];
        _myCount = 0;
        _loading = true;
      });
    }

    await _fetchMyPage(page: _myPage, append: !reset);

    setState(() {
      _loading = false;
    });
  }

  Future<void> refreshApprovals({required bool reset}) async {
    if (reset) {
      setState(() {
        _approvalsPage = 1;
        _approvalsAll = [];
        _approvalsCount = 0;
        _loadingApprovals = true;
      });
    }

    await _fetchApprovalsPage(page: _approvalsPage, append: !reset);

    setState(() {
      _loadingApprovals = false;
    });
  }

  Future<void> refreshApprovalHistory({required bool reset}) async {
    if (!_canApprove) {
      setState(() {
        _approvalHistoryAll = [];
        _historyEmployeeOptions = [];
        _approvalHistoryCount = 0;
      });
      _notifyParentCount();
      return;
    }
    if (reset) {
      setState(() {
        _approvalHistoryPage = 1;
        _approvalHistoryAll = [];
        _historyEmployeeOptions = [];
        _approvalHistoryCount = 0;
        _loadingApprovalHistory = true;
      });
    }
    await _fetchApprovalHistoryPage(page: _approvalHistoryPage, append: !reset);
    setState(() {
      _loadingApprovalHistory = false;
    });
  }

  /// Refresh both tabs (My Requests + Approvals).
  /// Used by parent (Attendance > Requests) to force refresh after actions.
  Future<void> refresh({bool reset = false}) async {
    await refreshMy(reset: reset);
    await refreshApprovals(reset: reset);
    await refreshApprovalHistory(reset: reset);
  }

  Future<void> _fetchMyPage({required int page, required bool append}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    // Backend supports mine=1, month, and status; search stays local for consistent UX.
    final query = <String, String>{
      'mine': '1',
      'page': '$page',
      'month': _myMonth,
    };
    if (_myStatus != 'all') {
      query['status'] = _myStatus;
    }
    final uri = Uri.parse('$typedServerUrl/api/attendance/work-type-request/').replace(queryParameters: query);

    final resp = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      final results = List<Map<String, dynamic>>.from(body['results'] ?? []);
      final count = body['count'] ?? 0;

      setState(() {
        _myCount = count;
        if (append) {
          _myAll.addAll(results);
        } else {
          _myAll = results;
        }
        _dedupeMy();
      });

      _notifyParentCount();
    } else {
      // keep old list, but stop loading
      _notifyParentCount();
    }
  }

  Future<void> _fetchApprovalsPage({required int page, required bool append}) async {
    if (!_canApprove) {
      setState(() {
        _approvalsAll = [];
        _approvalsCount = 0;
      });
      _notifyParentCount();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/work-type-request-approvals/?queue=all&page=$page');

    final resp = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      final results = List<Map<String, dynamic>>.from(body['results'] ?? []);
      final count = body['count'] ?? 0;

      setState(() {
        _approvalsCount = count;
        if (append) {
          _approvalsAll.addAll(results);
        } else {
          _approvalsAll = results;
        }
        _approvalsAll.sort((a, b) {
          final aq = (_queueTypeText(a) ?? 'zzz');
          final bq = (_queueTypeText(b) ?? 'zzz');
          final cmp = aq.compareTo(bq);
          if (cmp != 0) return cmp;
          return (b['id'] ?? 0).toString().compareTo((a['id'] ?? 0).toString());
        });
        _dedupeApprovals();
      });
      _notifyParentCount();
    } else {
      if (resp.statusCode == 403) {
        setState(() {
          _canApprove = false;
          _approvalsAll = [];
          _approvalsCount = 0;
        });
        _notifyParentCount();
      }
    }
  }

  Future<void> _fetchApprovalHistoryPage({required int page, required bool append}) async {
    if (!_canApprove) {
      setState(() {
        _approvalHistoryAll = [];
        _historyEmployeeOptions = [];
        _approvalHistoryCount = 0;
      });
      _notifyParentCount();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');
    final query = <String, String>{
      'queue': 'history',
      'page': '$page',
      'month': _historyMonth,
      'status': _historyStatus,
    };
    final employeeId = _historyEmployeeId.trim();
    if (employeeId.isNotEmpty) {
      query['employee_id'] = employeeId;
    }

    final uri = Uri.parse('$typedServerUrl/api/attendance/work-type-request-approvals/').replace(queryParameters: query);

    final resp = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      final results = List<Map<String, dynamic>>.from(body['results'] ?? []);
      final count = body['count'] ?? 0;
      final employeeOptions = List<Map<String, dynamic>>.from(body['employee_options'] ?? []);

      setState(() {
        _approvalHistoryCount = count;
        _historyEmployeeOptions = employeeOptions;
        if (append) {
          _approvalHistoryAll.addAll(results);
        } else {
          _approvalHistoryAll = results;
        }
        final unique = <String, Map<String, dynamic>>{};
        for (final item in _approvalHistoryAll) {
          unique[item['id'].toString()] = item;
        }
        _approvalHistoryAll = unique.values.toList();
      });
      _notifyParentCount();
    } else if (resp.statusCode == 403) {
      setState(() {
        _canApprove = false;
        _approvalHistoryAll = [];
        _historyEmployeeOptions = [];
        _approvalHistoryCount = 0;
      });
      _notifyParentCount();
    }
  }

  Future<void> _loadMoreApprovals() async {
    if (!_canApprove) return;
    if (_loadingMoreApprovals || _loadingApprovals) return;
    if (_approvalsAll.length >= _approvalsCount && _approvalsCount != 0) return;

    setState(() {
      _loadingMoreApprovals = true;
      _approvalsPage += 1;
    });

    await _fetchApprovalsPage(page: _approvalsPage, append: true);

    setState(() {
      _loadingMoreApprovals = false;
    });
  }

  Future<void> _loadMoreApprovalHistory() async {
    if (!_canApprove) return;
    if (_loadingMoreApprovalHistory || _loadingApprovalHistory) return;
    if (_approvalHistoryAll.length >= _approvalHistoryCount && _approvalHistoryCount != 0) return;

    setState(() {
      _loadingMoreApprovalHistory = true;
      _approvalHistoryPage += 1;
    });

    await _fetchApprovalHistoryPage(page: _approvalHistoryPage, append: true);

    setState(() {
      _loadingMoreApprovalHistory = false;
    });
  }

  void _dedupeMy() {
    String serializeMap(Map<String, dynamic> map) => jsonEncode(map);
    Map<String, dynamic> deserializeMap(String s) => jsonDecode(s);
    final mapStrings = _myAll.map(serializeMap).toList();
    final unique = mapStrings.toSet();
    _myAll = unique.map(deserializeMap).toList();
  }

  void _dedupeApprovals() {
    String serializeMap(Map<String, dynamic> map) => jsonEncode(map);
    Map<String, dynamic> deserializeMap(String s) => jsonDecode(s);
    final mapStrings = _approvalsAll.map(serializeMap).toList();
    final unique = mapStrings.toSet();
    _approvalsAll = unique.map(deserializeMap).toList();
  }

  List<Map<String, dynamic>> get _myRequests {
    final q = widget.searchText.trim().toLowerCase();
    if (q.isEmpty) return _myAll;
    return _myAll.where((r) {
      final hay = [
        _modeText(r),
        _scopeText(r),
        _statusText(r),
        _queueTypeText(r) ?? '',
        _dateText(r),
        _employeeName(r),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _approvalQueue {
    final q = widget.searchText.trim().toLowerCase();
    if (q.isEmpty) return _approvalsAll;
    return _approvalsAll.where((r) {
      final hay = [
        _modeText(r),
        _scopeText(r),
        _statusText(r),
        _queueTypeText(r) ?? '',
        _dateText(r),
        _employeeName(r),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
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
              title: const Text('Select month'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedMonth,
                    style: _requestFilterFieldTextStyle,
                    dropdownColor: Colors.white,
                    iconEnabledColor: Colors.black87,
                    decoration: const InputDecoration(
                      labelText: 'Month',
                      border: OutlineInputBorder(),
                    ),
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
                    style: _requestFilterFieldTextStyle,
                    dropdownColor: Colors.white,
                    iconEnabledColor: Colors.black87,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
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

  List<Map<String, dynamic>> get _approvalHistory {
    final q = widget.searchText.trim().toLowerCase();
    if (q.isEmpty) return _approvalHistoryAll;
    return _approvalHistoryAll.where((r) {
      final hay = [
        _modeText(r),
        _scopeText(r),
        _statusText(r),
        _queueTypeText(r) ?? '',
        _dateText(r),
        _employeeName(r),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _approvalEmployeeOptions {
    final scoped = <String, Map<String, dynamic>>{};

    void ingest(Iterable<Map<String, dynamic>> records) {
      for (final record in records) {
        final employeeId = (record['employee_id'] ?? record['employee_id_id'] ?? record['employee'] ?? record['employeeId'] ?? record['id'])?.toString().trim();
        if (employeeId == null || employeeId.isEmpty || scoped.containsKey(employeeId)) continue;
        if (_currentEmployeeId != null && employeeId == _currentEmployeeId.toString()) continue;
        final firstName = (record['employee_first_name'] ?? '').toString();
        final lastName = (record['employee_last_name'] ?? '').toString();
        scoped[employeeId] = {
          'id': employeeId,
          'employee_first_name': firstName,
          'employee_last_name': lastName,
        };
      }
    }

    if (_historyEmployeeOptions.isNotEmpty) {
      ingest(_historyEmployeeOptions);
    } else if (widget.employeeOptions.isNotEmpty) {
      ingest(widget.employeeOptions);
    }
    ingest(_approvalsAll);
    ingest(_approvalHistoryAll);

    final employees = scoped.values.toList();
    employees.sort((a, b) {
      final aName = ((a['employee_first_name'] ?? '').toString() + ' ' + (a['employee_last_name'] ?? '').toString()).trim().toLowerCase();
      final bName = ((b['employee_first_name'] ?? '').toString() + ' ' + (b['employee_last_name'] ?? '').toString()).trim().toLowerCase();
      return aName.compareTo(bName);
    });
    return employees;
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

  Future<void> _openMyRequestFilterDialog() async {
    String draftStatus = _myStatus;
    String draftMonth = _myMonth;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
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
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'waiting_for_approval', child: Text('Waiting for approval')),
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
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _myStatus = draftStatus;
                      _myMonth = draftMonth;
                    });
                    await refreshMy(reset: true);
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

  Future<void> _openApprovalHistoryFilterDialog() async {
    String draftStatus = _historyStatus;
    String draftEmployeeId = _historyEmployeeId;
    String draftMonth = _historyMonth;

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
                        ..._approvalEmployeeOptions.map((employee) {
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
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _historyStatus = draftStatus;
                      _historyEmployeeId = draftEmployeeId;
                      _historyMonth = draftMonth;
                    });
                    await refreshApprovalHistory(reset: true);
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

  String? _queueTypeText(Map<String, dynamic> r) {
    final raw = (r['queue_type'] ?? '').toString().trim().toLowerCase();
    if (raw == 'approval') return 'Approval';
    if (raw == 'document_review') return 'Document Review';
    return null;
  }

  String _statusText(Map<String, dynamic> r) {
    final raw = (r['status'] ?? '').toString();
    if (raw.isEmpty) return '-';
    final up = raw.toUpperCase();
    if (up.contains('WAIT')) return 'WAITING';
    return up;
  }

  String _modeText(Map<String, dynamic> r) {
    final raw = (r['work_type'] ?? r['mode'] ?? r['work_mode'] ?? '').toString().toLowerCase();
    if (raw == 'wfa') return 'WFA';
    if (raw == 'wfh') return 'WFH';
    if (raw == 'on_duty') return 'ON DUTY';
    return raw.isEmpty ? '-' : raw;
  }

  String _scopeText(Map<String, dynamic> r) {
    final raw = (r['scope'] ?? '').toString().toLowerCase();
    if (raw == 'in') return 'IN';
    if (raw == 'out') return 'OUT';
    if (raw == 'full') return 'FULL';
    return raw.isEmpty ? '-' : raw;
  }

  String _dateText(Map<String, dynamic> r) {
    final start = r['start_date']?.toString();
    final end = r['end_date']?.toString();
    if (start == null || start.isEmpty) return '-';
    if (end == null || end.isEmpty || end == start) return start;
    return '$start → $end';
  }

  String _employeeName(Map<String, dynamic> r) {
    final fn = r['employee_first_name'] ?? '';
    final ln = r['employee_last_name'] ?? '';
    final full = ('$fn $ln').trim();
    return full.isEmpty ? 'Employee' : full;
  }

  bool _isOwner(Map<String, dynamic> r) {
    if (_currentEmployeeId == null) return false;
    final eid = r['employee_id'] ?? r['employee_id_id'] ?? r['employee'] ?? r['employeeId'];
    if (eid == null) return false;
    return eid.toString() == _currentEmployeeId.toString();
  }


  String? _actionByName(Map<String, dynamic> r) {
    final v = (r['action_by_name'] ?? r['approved_by_name'] ?? r['approved_by_full_name'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }

  String? _actionAtText(Map<String, dynamic> r) {
    final raw = (r['action_at'] ?? r['approved_at'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    try {
      final dt = DateTime.tryParse(raw);
      if (dt == null) return raw;
      return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
    } catch (_) {
      return raw;
    }
  }

  String? _actionLabel(Map<String, dynamic> r) {
    final type = _actionTypeText(r);
    if (type == 'APPROVED') return 'Approved by';
    if (type == 'REJECTED') return 'Rejected by';
    if (type == 'VERIFIED') return 'Verified by';
    if (type == 'DOCUMENT_REJECTED') return 'Document rejected by';
    if (type == 'REOPENED') return 'Reopened by';
    if (type == 'REVOKED') return 'Revoked by';
    if (type == 'CANCELED') return 'Canceled by';
    final status = _statusText(r);
    if (status == 'APPROVED') return 'Approved by';
    if (status == 'REJECTED') return 'Rejected by';
    if (status == 'REVOKED') return 'Revoked by';
    if (status == 'CANCELED') return 'Canceled by';
    return null;
  }

  String? _actionNote(Map<String, dynamic> r) {
    final value = (r['action_reason'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  String _onDutyLifecycleText(Map<String, dynamic> r) {
    final status = _statusText(r);
    final docStatus = _documentStatusText(r);
    if (status == 'PENDING') {
      return 'Pending request. Attendance effect has not started yet because the request is still waiting for the assignment letter/upload path.';
    }
    if (status == 'WAITING') {
      return 'Waiting for approval. Attendance effect has not started yet until the request is approved.';
    }
    if (status == 'APPROVED' && docStatus == 'Verified') {
      return 'Approved and document verified. Attendance effect is final.';
    }
    if (status == 'APPROVED' && (docStatus == 'Rejected' || docStatus == 'Not Uploaded')) {
      return 'Approved, but the document is not verified yet. Attendance effect is provisional and may change after upload/review.';
    }
    if (status == 'APPROVED') {
      return 'Approved, but document review is still in progress. Attendance effect remains provisional until verification is completed.';
    }
    if (status == 'REJECTED') {
      return 'Rejected request. No On Duty attendance effect applies.';
    }
    if (status == 'REVOKED') {
      return 'Revoked request. Any prior On Duty attendance effect is no longer active.';
    }
    if (status == 'CANCELED') {
      return 'Canceled request. No On Duty attendance effect applies.';
    }
    return 'On Duty follows approval and document verification workflow.';
  }

  String _documentStatusText(Map<String, dynamic> r) {
    final raw = (r['document_status'] ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty) return '-';
    if (raw == 'not_uploaded') return 'Not Uploaded';
    if (raw == 'submitted') return 'Submitted';
    if (raw == 'pending_verification') return 'Pending Verification';
    if (raw == 'verified') return 'Verified';
    if (raw == 'rejected') return 'Rejected';
    return raw.replaceAll('_', ' ');
  }

  bool _isOnDuty(Map<String, dynamic> r) => _modeText(r) == 'ON DUTY';

  bool _documentLocked(Map<String, dynamic> r) =>
      (r['document_status'] ?? '').toString().toLowerCase() == 'verified';

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return Colors.green;
      case 'WAITING':
        return Colors.orange;
      case 'REJECTED':
        return Colors.red;
      case 'REVOKED':
        return Colors.redAccent;
      case 'CANCELED':
        return Colors.grey;
      case 'PENDING':
      default:
        return Colors.orange;
    }
  }

  /// Called by parent to open create dialog.
  Future<void> openCreateDialog() async {
    await _showCreateWorkModeRequestDialog(context);
  }

  Future<void> _showCreateWorkModeRequestDialog(BuildContext context) async {
    String workMode = 'wfa';
    String scope = 'full';
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    final descCtrl = TextEditingController();
    final dutyLocationCtrl = TextEditingController();

    bool submitting = false;
    String? submitError;
    String? reasonError;

    DateTime _todayDate() {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }

    Future<String?> pickDate(DateTime initial, {DateTime? firstDate}) async {
      final selected = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: firstDate ?? _todayDate(),
        lastDate: DateTime(2100),
        builder: (context, child) {
          return Theme(
            data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(primary: Colors.blue),
            ),
            child: child!,
          );
        },
      );
      if (selected == null) return null;
      return DateFormat('yyyy-MM-dd').format(selected);
    }

    // Use the parent page context for snackbars AFTER the dialog is closed.
    final pageMessenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            // Helper for responsive date picking controls.
            Widget _dateButton({
              required String label,
              required DateTime date,
              required VoidCallback onPressed,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: submitting ? null : onPressed,
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(date),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              );
            }

            Widget _errorBox(String msg) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.error_outline, color: Colors.red, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        msg,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              title: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Create Work Type Request',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: submitting
                        ? null
                        : () {
                      setState(() => _pickedFiles = []);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.95,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (submitError != null) _errorBox(submitError!),
                      const SizedBox(height: 4),

                      const Text('Work Type', style: TextStyle(color: Colors.black)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: workMode,
                        isExpanded: true,
                        isDense: false,
                        // Allow taller items so long labels can wrap to 2 lines on small screens.
                        itemHeight: 72,
                        selectedItemBuilder: (context) => const [
                          Text(
                            'WFA (Needs approval before punch)',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'WFH (Needs approval before punch)',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'ON DUTY (Needs approval before punch)',
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        items: const [
                          DropdownMenuItem(
                            value: 'wfa',
                            child: Text(
                              'WFA (Needs approval before punch)',
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'wfh',
                            child: Text(
                              'WFH (Needs approval before punch)',
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'on_duty',
                            child: Text(
                              'ON DUTY (Needs approval before punch)',
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: submitting
                            ? null
                            : (v) {
                          if (v == null) return;
                          setStateDialog(() {
                            workMode = v;
                            if (scope != 'full') endDate = startDate;
                          });
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),

                      const SizedBox(height: 12),
                      const Text('Scope', style: TextStyle(color: Colors.black)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('IN'),
                            selected: scope == 'in',
                            onSelected: submitting
                                ? null
                                : (_) => setStateDialog(() {
                              scope = 'in';
                              endDate = startDate;
                            }),
                          ),
                          ChoiceChip(
                            label: const Text('OUT'),
                            selected: scope == 'out',
                            onSelected: submitting
                                ? null
                                : (_) => setStateDialog(() {
                              scope = 'out';
                              endDate = startDate;
                            }),
                          ),
                          ChoiceChip(
                            label: const Text('FULL'),
                            selected: scope == 'full',
                            onSelected: submitting ? null : (_) => setStateDialog(() => scope = 'full'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      Text(
                        scope == 'full' ? 'Date Range' : 'Date',
                        style: const TextStyle(color: Colors.black),
                      ),
                      const SizedBox(height: 6),
                      if (scope == 'full')
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final startWidget = _dateButton(
                              label: 'Start Date',
                              date: startDate,
                              onPressed: () async {
                                final s = await pickDate(startDate);
                                if (s == null) return;
                                setStateDialog(() {
                                  startDate = DateTime.parse(s);
                                  if (endDate.isBefore(startDate)) endDate = startDate;
                                });
                              },
                            );
                            final endWidget = _dateButton(
                              label: 'End Date',
                              date: endDate,
                              onPressed: () async {
                                final s = await pickDate(endDate, firstDate: startDate);
                                if (s == null) return;
                                setStateDialog(() {
                                  endDate = DateTime.parse(s);
                                  if (endDate.isBefore(startDate)) endDate = startDate;
                                });
                              },
                            );

                            if (constraints.maxWidth < 360) {
                              return Column(
                                children: [
                                  startWidget,
                                  const SizedBox(height: 8),
                                  endWidget,
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: startWidget),
                                const SizedBox(width: 8),
                                Expanded(child: endWidget),
                              ],
                            );
                          },
                        )
                      else
                        _dateButton(
                          label: 'Date',
                          date: startDate,
                          onPressed: () async {
                            final s = await pickDate(startDate);
                            if (s == null) return;
                            setStateDialog(() {
                              startDate = DateTime.parse(s);
                              endDate = startDate;
                            });
                          },
                        ),

                      const SizedBox(height: 12),
                      const Text('Reason / Note', style: TextStyle(color: Colors.black)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        enabled: !submitting,
                        onChanged: (v) {
                          if (reasonError != null && v.trim().isNotEmpty) {
                            setStateDialog(() => reasonError = null);
                          }
                        },
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Write a short reason…',
                          errorText: reasonError,
                        ),
                      ),

                      if (workMode == 'on_duty') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: dutyLocationCtrl,
                          enabled: !submitting,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Duty Destination Location',
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: submitting
                              ? null
                              : () async {
                            final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
                            if (picked == null) return;
                            final msg = _validatePickedFiles(picked.files);
                            if (msg != null) {
                              setStateDialog(() => submitError = msg);
                              return;
                            }
                            setStateDialog(() {
                              _pickedFiles = picked.files;
                            });
                          },
                          icon: const Icon(Icons.attach_file),
                          label: Text(
                            _pickedFiles.isEmpty ? 'Attach files' : 'Attachments (${_pickedFiles.length})',
                          ),
                        ),
                      ),

                      if (workMode == 'on_duty') ...[
                        const SizedBox(height: 8),
                        const Text(
                          'On Duty requires destination and at least one document when the request is created. After approval the attendance effect is provisional until the document is verified. Rejected, reopened, or revoked documents can change the final result.',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                      // Client-side guard: never allow past dates (server will enforce too).
                      final today = _todayDate();
                      if (startDate.isBefore(today)) {
                        setStateDialog(() {
                          submitError = 'Tanggal request tidak boleh mundur (sebelum hari ini).';
                        });
                        return;
                      }

                      final reason = descCtrl.text.trim();
                      if (reason.isEmpty) {
                        setStateDialog(() {
                          reasonError = 'Reason / Note is required.';
                          submitError = null;
                        });
                        return;
                      }

                      if (workMode == 'on_duty' && dutyLocationCtrl.text.trim().isEmpty) {
                        setStateDialog(() {
                          submitError = 'Duty Destination Location is required for On Duty requests.';
                        });
                        return;
                      }
                      if (workMode == 'on_duty' && _pickedFiles.isEmpty) {
                        setStateDialog(() {
                          submitError = 'At least one file is required for On Duty requests.';
                        });
                        return;
                      }

                      final attachmentMsg = _validatePickedFiles(_pickedFiles);
                      if (attachmentMsg != null) {
                        setStateDialog(() {
                          submitError = attachmentMsg;
                        });
                        return;
                      }

                      setStateDialog(() {
                        submitting = true;
                        submitError = null;
                      });

                      final result = await _createWorkModeRequest(
                        workMode: workMode,
                        scope: scope,
                        startDate: DateFormat('yyyy-MM-dd').format(startDate),
                        endDate: DateFormat('yyyy-MM-dd').format(endDate),
                        description: reason,
                        dutyDestinationLocation: dutyLocationCtrl.text.trim(),
                      );

                      if (!result.ok) {
                        setStateDialog(() {
                          submitting = false;
                          submitError = result.message ?? 'Submit failed.';
                        });
                        return;
                      }

                      if (!mounted) return;
                      Navigator.of(ctx).pop();
                      await refreshMy(reset: true);
                      await refreshApprovals(reset: true);

                      pageMessenger.showSnackBar(
                        const SnackBar(content: Text('Work Type Request submitted')),
                      );
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all<Color>(Colors.red),
                    ),
                    child: submitting
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Text('Submit', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_CreateResult> _createWorkModeRequest({
    required String workMode,
    required String scope,
    required String startDate,
    required String endDate,
    required String description,
    String dutyDestinationLocation = '',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final typedServerUrl = prefs.getString('typed_url');

      if (typedServerUrl == null || typedServerUrl.isEmpty) {
        return const _CreateResult(false, 'Server URL belum diset.');
      }
      if (token == null || token.isEmpty) {
        return const _CreateResult(false, 'Session/login sudah habis. Silakan login ulang.');
      }

      final uri = Uri.parse('$typedServerUrl/api/attendance/work-type-request/');
      final String normalizedEndDate = (scope == 'full') ? endDate : startDate;

      final attachmentMsg = _validatePickedFiles(_pickedFiles);
      if (attachmentMsg != null) {
        return _CreateResult(false, attachmentMsg);
      }
      if (workMode == 'on_duty' && dutyDestinationLocation.trim().isEmpty) {
        return const _CreateResult(false, 'Duty Destination Location is required for On Duty requests.');
      }
      if (workMode == 'on_duty' && _pickedFiles.isEmpty) {
        return const _CreateResult(false, 'At least one file is required for On Duty requests.');
      }

      http.Response resp;

      if (_pickedFiles.isNotEmpty) {
        final req = http.MultipartRequest('POST', uri);
        req.headers['Authorization'] = 'Bearer $token';
        req.fields['work_type'] = workMode;
        req.fields['mode'] = workMode;
        req.fields['scope'] = scope;
        req.fields['start_date'] = startDate;
        req.fields['end_date'] = normalizedEndDate;
        req.fields['reason'] = description;
        if (dutyDestinationLocation.isNotEmpty) req.fields['duty_destination_location'] = dutyDestinationLocation;

        for (final f in _pickedFiles) {
          if (f.path == null) continue;
          req.files.add(await http.MultipartFile.fromPath('files', f.path!));
        }

        final streamed = await req.send();
        resp = await http.Response.fromStream(streamed);
      } else {
        resp = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'work_type': workMode,
            'mode': workMode,
            'scope': scope,
            'start_date': startDate,
            'end_date': normalizedEndDate,
            'reason': description,
            'duty_destination_location': dutyDestinationLocation,
          }),
        );
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        if (mounted) {
          setState(() => _pickedFiles = []);
        }
        return const _CreateResult(true);
      }

      String msg = 'Submit gagal (${resp.statusCode}).';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          if (decoded['error'] != null) {
            msg = decoded['error'].toString();
          } else if (decoded['detail'] != null) {
            msg = decoded['detail'].toString();
          } else {
            final parts = <String>[];
            decoded.forEach((k, v) {
              final key = k.toString();
              // Clean UX: show non_field_errors without the "non_field_errors:" prefix.
              if (key == 'non_field_errors' ||
                  key == 'non_field_error' ||
                  key == 'nonFieldErrors' ||
                  key == 'nonFieldError') {
                if (v is List) {
                  parts.add(v.join('\n'));
                } else {
                  parts.add(v.toString());
                }
                return;
              }

              if (v is List) {
                parts.add('$key: ${v.join(', ')}');
              } else {
                parts.add('$key: $v');
              }
            });
            if (parts.isNotEmpty) msg = parts.join('\n');
          }
        } else if (decoded != null) {
          msg = decoded.toString();
        }
      } catch (_) {
        final body = resp.body.trim();
        if (body.isNotEmpty) msg = body;
      }

      // Final cleanup: if server sends prefixed strings, strip them.
      msg = msg.replaceFirst(RegExp(r'^\s*non_field_errors\s*:\s*'), '');
      msg = msg.replaceFirst(RegExp(r'^\s*non_field_error\s*:\s*'), '');

      return _CreateResult(false, msg);
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') || s.contains('No route to host')) {
        return const _CreateResult(false, 'Tidak bisa terhubung ke server. Cek IP/URL & jaringan.');
      }
      return _CreateResult(false, 'Terjadi error: $s');
    }
  }

  Future<void> _handleActionResponse(http.Response resp) async {
    if (resp.statusCode == 200) return;
    String msg = 'Action failed.';
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['error'] != null) {
        msg = decoded['error'].toString();
      } else if (decoded is Map && decoded['detail'] != null) {
        msg = decoded['detail'].toString();
      } else if (decoded != null) {
        msg = decoded.toString();
      }
    } catch (_) {
      final body = resp.body.trim();
      if (body.isNotEmpty) msg = body;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _approve(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/work-type-request-approve/$id');

    final resp = await http.put(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    await _handleActionResponse(resp);
    if (resp.statusCode == 200) {
      await refreshMy(reset: true);
      await refreshApprovals(reset: true);
      await refreshApprovalHistory(reset: true);
    }
  }

  Future<void> _reject(int id, {String? comment}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/work-type-request-reject/$id');

    final payload = buildWorkModeRejectPayload(comment: comment);

    final resp = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    await _handleActionResponse(resp);
    if (resp.statusCode == 200) {
      await refreshMy(reset: true);
      await refreshApprovals(reset: true);
      await refreshApprovalHistory(reset: true);
    }
  }

  Future<void> _showRejectDialog(BuildContext ctx, int id) async {
    final noteController = TextEditingController();
    await showDialog(
      context: ctx,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reject Request'),
          content: TextField(
            controller: noteController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Reason / Note',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                final comment = noteController.text.trim();
                await _reject(id, comment: comment);
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all<Color>(Colors.red),
              ),
              child: const Text('Reject', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showActionRemarkDialog({
    required BuildContext ctx,
    required String title,
    required String label,
    required Future<void> Function(String remark) onSubmit,
    bool requiredRemark = false,
    String submitLabel = 'Submit',
  }) async {
    final noteController = TextEditingController();
    String? errorText;
    await showDialog(
      context: ctx,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: noteController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final remark = noteController.text.trim();
                    if (requiredRemark && remark.isEmpty) {
                      setStateDialog(() => errorText = '$label is required.');
                      return;
                    }
                    await onSubmit(remark);
                    if (!mounted) return;
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(submitLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _cancel(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/work-type-request-cancel/$id');

    final resp = await http.put(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    await _handleActionResponse(resp);
    if (resp.statusCode == 200) {
      await refreshMy(reset: true);
      await refreshApprovals(reset: true);
      await refreshApprovalHistory(reset: true);
    }
  }

  Future<void> _requestDocumentAction(int id, String action, {String? remark}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');
    if (token == null || token.isEmpty || typedServerUrl == null || typedServerUrl.isEmpty) {
      return;
    }

    final uri = Uri.parse(
      '$typedServerUrl/api/attendance/work-type-request-action/$id/$action',
    );

    final resp = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(buildWorkModeDocumentActionPayload(remark: remark)),
    );

    await _handleActionResponse(resp);
    if (resp.statusCode == 200) {
      await refreshMy(reset: true);
      await refreshApprovals(reset: true);
      await refreshApprovalHistory(reset: true);
    }
  }

  Future<void> _uploadFiles(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');
    if (token == null || typedServerUrl == null) return;

    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (picked == null || picked.files.isEmpty) return;
    final attachmentMsg = _validatePickedFiles(picked.files);
    if (attachmentMsg != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(attachmentMsg)),
        );
      }
      return;
    }

    final uri = Uri.parse('$typedServerUrl/api/attendance/work-type-request/$id');
    final req = http.MultipartRequest('PATCH', uri);
    req.headers['Authorization'] = 'Bearer $token';

    for (final f in picked.files) {
      if (f.path == null) continue;
      req.files.add(await http.MultipartFile.fromPath('files', f.path!));
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode == 200) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Files uploaded')));
      }
      await refreshMy(reset: true);
      await refreshApprovals(reset: true);
      await refreshApprovalHistory(reset: true);
    } else {
      String message = 'Upload failed (${resp.statusCode})';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          if (decoded['error'] != null) {
            message = decoded['error'].toString();
          } else if (decoded['files'] is List && (decoded['files'] as List).isNotEmpty) {
            message = (decoded['files'] as List).join('\n');
          }
        }
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return _buildLoading();
    }

    final approvalHistory = _approvalHistory;

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          indicatorColor: Colors.red,
          labelColor: Colors.red,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: 'My Requests (${_myRequests.length})'),
            Tab(text: 'Approvals (${_canApprove ? (_approvalQueue.length + _approvalHistoryCount) : 0})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Month: ${_formatMonthLabel(_myMonth)} • Status: ${_myStatus == 'all' ? 'ALL' : _myStatus.replaceAll('_', ' ').toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openMyRequestFilterDialog,
                          icon: const Icon(Icons.filter_alt_outlined, size: 18),
                          label: const Text('Filters'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _buildList(_myRequests, isMyList: true, controller: _myScrollController),
                  ),
                ],
              ),
              _canApprove
                  ? DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      indicatorColor: Colors.red,
                      labelColor: Colors.red,
                      unselectedLabelColor: Colors.grey,
                      tabs: [
                        Tab(text: 'Approval (${_approvalQueue.length})'),
                        Tab(text: 'Approval History (${_approvalHistoryCount})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildList(
                            _approvalQueue,
                            isMyList: false,
                            controller: _approvalsScrollController,
                            isHistoryList: false,
                          ),
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Month: ${_formatMonthLabel(_historyMonth)} • Status: ${_historyStatus.toUpperCase()}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _openApprovalHistoryFilterDialog,
                                      icon: const Icon(Icons.filter_alt_outlined, size: 18),
                                      label: const Text('Filters'),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _buildList(
                                  approvalHistory,
                                  isMyList: false,
                                  controller: _approvalHistoryScrollController,
                                  isHistoryList: true,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
                  : _buildNoPermission(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return ListView.builder(
      itemCount: 8,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.grey.shade200,
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoPermission() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.lock_outline, size: 64, color: Colors.black54),
            SizedBox(height: 12),
            Text(
              'You do not have approval access for Work Type Requests.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
      List<Map<String, dynamic>> list, {
        required bool isMyList,
        required ScrollController controller,
        bool isHistoryList = false,
      }) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.inventory_outlined, color: Colors.black, size: 92),
              SizedBox(height: 10),
              Text(
                'There are no requests to display',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: controller,
      itemCount: list.length + ((isMyList ? _loadingMore : (isHistoryList ? _loadingMoreApprovalHistory : _loadingMoreApprovals)) ? 1 : 0),
      itemBuilder: (context, index) {
        final isLoadingMore = isMyList ? _loadingMore : (isHistoryList ? _loadingMoreApprovalHistory : _loadingMoreApprovals);
        if (isLoadingMore && index == list.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final r = list[index];
        final status = _statusText(r);
        return GestureDetector(
          onTap: () => _openDetail(r, isMyList: isMyList),
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
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _employeeName(r),
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: _statusColor(status),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (!isMyList && _queueTypeText(r) != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _queueTypeText(r)!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                      ),
                    ],
                    Text(
                      'Work Type: ${_modeText(r)}   •   Scope: ${_scopeText(r)}',
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text('Date: ${_dateText(r)}'),
                    if (_isOnDuty(r)) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Document: ${_documentStatusText(r)}',
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                    ...(() {
                      final label = _actionLabel(r);
                      final by = _actionByName(r);
                      if (label == null || by == null) return <Widget>[];
                      final at = _actionAtText(r);
                      return <Widget>[
                        const SizedBox(height: 4),
                        Text(
                          at == null ? '$label: $by' : '$label: $by • $at',
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ];
                    })(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDetail(Map<String, dynamic> r, {required bool isMyList}) async {
    final id = r['id'];
    final status = _statusText(r);

    final bool canCancel = (status == 'PENDING' || status == 'WAITING') && isMyList;
    final bool isOwner = _isOwner(r);
    final bool isWaiting = status == 'WAITING';
    final bool isPending = status == 'PENDING';
    final bool isApproved = status == 'APPROVED';
    final bool isOnDuty = _modeText(r) == 'ON DUTY';
    final String docStatus = _documentStatusText(r);
    final bool canApproveAction = r['can_approve'] == true;
    final bool canRejectAction = r['can_reject'] == true;
    final bool canRevokeAction = r['can_revoke'] == true;
    final bool canVerifyDocument = r['can_verify_document'] == true;
    final bool canReopenDocument = r['can_reopen_document'] == true;
    final bool canUploadLetter = r['can_upload_document'] == true ||
        (isMyList && isOnDuty && !_documentLocked(r) && (isPending || isWaiting || isApproved));

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Work Type Request',
                  maxLines: 3,
                  softWrap: true,
                  // Allow wrapping instead of truncating on smaller screens
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(ctx).size.width * 0.95,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Employee', _employeeName(r)),
                  _kv('Status', status),
                  ...(() {
                    final label = _actionLabel(r);
                    final by = _actionByName(r);
                    if (label == null || by == null) return <Widget>[];
                    final at = _actionAtText(r);
                    return <Widget>[
                      _kv(label, by),
                      if (at != null) _kv('Action At', at),
                    ];
                  })(),
                  _kv('Work Type', _modeText(r)),
                  _kv('Scope', _scopeText(r)),
                  _kv('Date', _dateText(r)),
                  if (isOnDuty) _kv('Document Status', docStatus),
                  if (isOnDuty && (r['duty_destination_location'] ?? '').toString().trim().isNotEmpty) _kv('Duty Destination', (r['duty_destination_location']).toString()),
                  if ((r['reason'] ?? r['description'] ?? '').toString().trim().isNotEmpty)
                    _kv('Reason', (r['reason'] ?? r['description']).toString()),
                  if (_actionNote(r) != null)
                    _kv('Action Note', _actionNote(r)!),
                  if (isOnDuty)
                    _kv('On Duty Workflow', _onDutyLifecycleText(r)),
                  ...(() {
                    final attachmentEntries = _attachmentEntries(r);
                    if (attachmentEntries.isEmpty) return <Widget>[];
                    return <Widget>[
                      const SizedBox(height: 10),
                      const Text(
                        'Attachments',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      ...List<Widget>.from(
                        attachmentEntries.map((entry) {
                          final name = entry.name.trim().isEmpty ? 'attachment' : entry.name.trim();
                          return InkWell(
                            onTap: () async {
                              try {
                                await openMobileAttachment(context, entry, baseUrl: _baseUrl);
                              } catch (_) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Failed to open attachment.')),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.attach_file, size: 18, color: Colors.black54),
                                  const SizedBox(width: 6),
                                  Expanded(
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
                                  const SizedBox(width: 6),
                                  const Icon(Icons.open_in_new, size: 16, color: Colors.black45),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ];
                  })(),
                ],
              ),
            ),
          ),
          actions: [
            if (canUploadLetter) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await _uploadFiles(id);
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Upload Letter'),
                ),
              ),
            ],
            if (canUploadLetter && (canCancel || canApproveAction || canRejectAction))
              const SizedBox(height: 8),
            if (canCancel) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await _cancel(id);
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                  },
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.all<Color>(Colors.red),
                  ),
                  child: const Text(
                    'Cancel Request',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
            ] else if (!isMyList && (canApproveAction || canRejectAction)) ...[
              if (isOwner)
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'You cannot approve/reject your own request. Ask another approver.',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                )
              else if (canApproveAction && isWaiting)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _showRejectDialog(context, id);
                        },
                        style: ButtonStyle(
                          backgroundColor:
                          MaterialStateProperty.all<Color>(Colors.red),
                        ),
                        child: const Text('Reject',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await _approve(id);
                          if (!mounted) return;
                          Navigator.of(ctx).pop();
                        },
                        style: ButtonStyle(
                          backgroundColor:
                          MaterialStateProperty.all<Color>(Colors.green),
                        ),
                        child: const Text('Approve',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                )
              else if (canRejectAction)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _showRejectDialog(context, id);
                      },
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.all<Color>(Colors.red),
                      ),
                      child: const Text(
                        'Reject Request',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  )
            ],
            if (!isMyList && !isOwner && isApproved && isOnDuty && (canVerifyDocument || canReopenDocument || canRevokeAction)) ...[
              if (canVerifyDocument && (docStatus == 'Submitted' || docStatus == 'Pending Verification'))
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _showActionRemarkDialog(
                            ctx: context,
                            title: 'Reject Document',
                            label: 'Document Rejection Remark',
                            requiredRemark: true,
                            submitLabel: 'Reject',
                            onSubmit: (remark) => _requestDocumentAction(id, 'reject-document', remark: remark),
                          );
                        },
                        style: ButtonStyle(backgroundColor: MaterialStateProperty.all<Color>(Colors.red)),
                        child: const Text('Reject Document', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await _requestDocumentAction(id, 'verify');
                          if (!mounted) return;
                          Navigator.of(ctx).pop();
                        },
                        style: ButtonStyle(backgroundColor: MaterialStateProperty.all<Color>(Colors.green)),
                        child: const Text('Verify Document', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              if (canReopenDocument && (docStatus == 'Verified' || docStatus == 'Rejected'))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _showActionRemarkDialog(
                        ctx: context,
                        title: 'Reopen Document Review',
                        label: 'Reopen Remark',
                        submitLabel: 'Reopen',
                        onSubmit: (remark) => _requestDocumentAction(id, 'reopen-document', remark: remark),
                      );
                    },
                    child: const Text('Reopen Document Review'),
                  ),
                ),
              if (canRevokeAction)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _showActionRemarkDialog(
                        ctx: context,
                        title: 'Revoke Request',
                        label: 'Revoke Reason',
                        submitLabel: 'Revoke',
                        onSubmit: (remark) => _requestDocumentAction(id, 'revoke', remark: remark),
                      );
                    },
                    child: const Text('Revoke Request'),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 4),
          Text(v, style: const TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }
}
