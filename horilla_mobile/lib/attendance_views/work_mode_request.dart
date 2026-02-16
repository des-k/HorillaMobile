import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Work Mode Requests (WFA / ON_DUTY)
/// - My Requests: employee creates & can cancel while pending
/// - Approvals: manager/admin can approve/reject
///
/// This widget is meant to be embedded inside AttendanceRequest page.
class WorkModeRequestTab extends StatefulWidget {
  const WorkModeRequestTab({
    super.key,
    required this.searchText,
    this.onCountChanged,
  });

  final String searchText;
  final ValueChanged<int>? onCountChanged;

  @override
  WorkModeRequestTabState createState() => WorkModeRequestTabState();
}

class WorkModeRequestTabState extends State<WorkModeRequestTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  List<Map<String, dynamic>> _all = [];
  int _count = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;

  int? _currentEmployeeId;
  bool _canApprove = false;

  String get _baseUrl => _cachedBaseUrl ?? '';
  String? _cachedBaseUrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedBaseUrl = prefs.getString('typed_url') ?? '';
    _currentEmployeeId = prefs.getInt('employee_id');
    await _fetchApprovePermission();
    await refresh(reset: true);
  }

  Future<void> _fetchApprovePermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final typedServerUrl = prefs.getString('typed_url');
      final uri = Uri.parse(
          '$typedServerUrl/api/attendance/work-mode-request-approve-perm-check/');
      final resp = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
      setState(() {
        _canApprove = resp.statusCode == 200;
      });
    } catch (_) {
      setState(() {
        _canApprove = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 60 &&
        !_scrollController.position.outOfRange) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    // if already loaded all
    if (_all.length >= _count && _count != 0) return;

    setState(() {
      _loadingMore = true;
      _page += 1;
    });

    await _fetchPage(page: _page, append: true);

    setState(() {
      _loadingMore = false;
    });
  }

  Future<void> refresh({required bool reset}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _all = [];
        _count = 0;
        _loading = true;
      });
    }

    await _fetchPage(page: _page, append: !reset);

    setState(() {
      _loading = false;
    });
  }

  Future<void> _fetchPage({required int page, required bool append}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final search = (widget.searchText).trim();
    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/work-mode-request/?page=$page&search=$search');

    final resp = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body);
      final results = List<Map<String, dynamic>>.from(body['results'] ?? []);
      final count = body['count'] ?? 0;

      setState(() {
        _count = count;
        if (append) {
          _all.addAll(results);
        } else {
          _all = results;
        }
        _dedupe();
      });

      widget.onCountChanged?.call(_count);
    } else {
      // keep old list, but stop loading
      widget.onCountChanged?.call(_count);
    }
  }

  void _dedupe() {
    String serializeMap(Map<String, dynamic> map) => jsonEncode(map);
    Map<String, dynamic> deserializeMap(String s) => jsonDecode(s);
    final mapStrings = _all.map(serializeMap).toList();
    final unique = mapStrings.toSet();
    _all = unique.map(deserializeMap).toList();
  }

  List<Map<String, dynamic>> get _myRequests {
    if (_currentEmployeeId == null) return _all;
    return _all.where((r) => '${r['employee_id']}' == '$_currentEmployeeId').toList();
  }

  List<Map<String, dynamic>> get _approvalQueue {
    if (_currentEmployeeId == null) return [];
    return _all.where((r) => '${r['employee_id']}' != '$_currentEmployeeId').toList();
  }

  String _statusText(Map<String, dynamic> r) {
    final raw = (r['status'] ?? '').toString();
    if (raw.isEmpty) return '-';
    return raw.toUpperCase();
  }

  String _modeText(Map<String, dynamic> r) {
    final raw = (r['work_mode'] ?? '').toString().toLowerCase();
    if (raw == 'wfa') return 'WFA';
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

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
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

    Future<String?> pickDate(DateTime initial) async {
      final selected = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
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

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Create Work Mode Request',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
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
                      const SizedBox(height: 8),
                      const Text('Work Mode', style: TextStyle(color: Colors.black)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: workMode,
                        items: const [
                          DropdownMenuItem(value: 'wfa', child: Text('WFA (Needs approval before punch)')),
                          DropdownMenuItem(value: 'on_duty', child: Text('On Duty (Punch allowed while pending)')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setStateDialog(() {
                            workMode = v;
                            if (workMode == 'wfa') {
                              scope = 'full';
                            }
                          });
                        },
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      if (workMode == 'on_duty') ...[
                        const Text('On Duty Type', style: TextStyle(color: Colors.black)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('IN'),
                              selected: scope == 'in',
                              onSelected: (_) => setStateDialog(() => scope = 'in'),
                            ),
                            ChoiceChip(
                              label: const Text('OUT'),
                              selected: scope == 'out',
                              onSelected: (_) => setStateDialog(() => scope = 'out'),
                            ),
                            ChoiceChip(
                              label: const Text('FULL'),
                              selected: scope == 'full',
                              onSelected: (_) => setStateDialog(() => scope = 'full'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text('Date Range', style: TextStyle(color: Colors.black)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final s = await pickDate(startDate);
                                if (s == null) return;
                                setStateDialog(() {
                                  startDate = DateTime.parse(s);
                                  if (endDate.isBefore(startDate)) endDate = startDate;
                                });
                              },
                              child: Text('Start: ${DateFormat('yyyy-MM-dd').format(startDate)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final s = await pickDate(endDate);
                                if (s == null) return;
                                setStateDialog(() {
                                  endDate = DateTime.parse(s);
                                  if (endDate.isBefore(startDate)) endDate = startDate;
                                });
                              },
                              child: Text('End: ${DateFormat('yyyy-MM-dd').format(endDate)}'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Reason / Notes', style: TextStyle(color: Colors.black)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Write a short reason…',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Attachment (surat tugas) can be added later on web (or after you add file upload in mobile).',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final ok = await _createWorkModeRequest(
                        workMode: workMode,
                        scope: scope,
                        startDate: DateFormat('yyyy-MM-dd').format(startDate),
                        endDate: DateFormat('yyyy-MM-dd').format(endDate),
                        description: descCtrl.text.trim(),
                      );
                      if (!ok) return;
                      if (!mounted) return;
                      Navigator.of(ctx).pop();
                      await refresh(reset: true);
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all<Color>(Colors.red),
                    ),
                    child: const Text('Submit', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _createWorkModeRequest({
    required String workMode,
    required String scope,
    required String startDate,
    required String endDate,
    required String description,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final uri = Uri.parse('$typedServerUrl/api/attendance/work-mode-request/');

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'work_mode': workMode,
        'scope': scope,
        'start_date': startDate,
        'end_date': endDate,
        'description': description,
      }),
    );

    return resp.statusCode == 201 || resp.statusCode == 200;
  }

  Future<void> _approve(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/work-mode-request-approve/$id');

    await http.put(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    await refresh(reset: true);
  }

  Future<void> _reject(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/work-mode-request-reject/$id');

    await http.put(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    await refresh(reset: true);
  }

  Future<void> _cancel(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final typedServerUrl = prefs.getString('typed_url');

    final uri = Uri.parse(
        '$typedServerUrl/api/attendance/work-mode-request-cancel/$id');

    await http.put(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    await refresh(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return _buildLoading();
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorColor: Colors.red,
            labelColor: Colors.red,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'My Requests (${_myRequests.length})'),
              Tab(text: 'Approvals (${_approvalQueue.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildList(_myRequests, isMyList: true),
                _canApprove
                    ? _buildList(_approvalQueue, isMyList: false)
                    : _buildNoPermission(),
              ],
            ),
          ),
        ],
      ),
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
              'You do not have approval access for Work Mode Requests.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, {required bool isMyList}) {
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
      controller: _scrollController,
      itemCount: list.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_loadingMore && index == list.length) {
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
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
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
                    Text('Mode: ${_modeText(r)}   •   Type: ${_scopeText(r)}'),
                    const SizedBox(height: 4),
                    Text('Date: ${_dateText(r)}'),
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

    final bool isPending = status == 'PENDING';

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Work Mode Request',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
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
                  _kv('Mode', _modeText(r)),
                  _kv('Type', _scopeText(r)),
                  _kv('Date', _dateText(r)),
                  if ((r['description'] ?? '').toString().trim().isNotEmpty)
                    _kv('Notes', (r['description'] ?? '').toString()),
                ],
              ),
            ),
          ),
          actions: [
            if (isPending && isMyList) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await _cancel(id);
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                  },
                  style: ButtonStyle(
                    backgroundColor:
                    MaterialStateProperty.all<Color>(Colors.red),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                ),
              )
            ] else if (isPending && !isMyList && _canApprove) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _reject(id);
                        if (!mounted) return;
                        Navigator.of(ctx).pop();
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
