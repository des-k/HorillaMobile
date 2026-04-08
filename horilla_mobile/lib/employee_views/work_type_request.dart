import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../attendance_views/work_mode_request.dart';

class WorkTypeRequestPage extends StatefulWidget {
  final String selectedEmployerId;
  final String selectedEmployeeFullName;

  const WorkTypeRequestPage({
    super.key,
    required this.selectedEmployerId,
    required this.selectedEmployeeFullName,
  });

  @override
  State<WorkTypeRequestPage> createState() => _WorkTypeRequestPageState();
}

class _WorkTypeRequestPageState extends State<WorkTypeRequestPage> {
  final GlobalKey<WorkModeRequestTabState> _workModeKey =
  GlobalKey<WorkModeRequestTabState>();
  final TextEditingController _searchController = TextEditingController();

  String _searchText = '';
  int? _currentEmployeeId;
  int _requestCount = 0;

  bool get _isSelfView {
    if (_currentEmployeeId == null) return false;
    return widget.selectedEmployerId == _currentEmployeeId.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentEmployee();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentEmployee() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('employee_id') ??
        int.tryParse(prefs.getString('employee_id') ?? '');
    if (!mounted) return;
    setState(() {
      _currentEmployeeId = id;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('Work Type Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _workModeKey.currentState?.refresh(reset: true),
          ),
          if (_isSelfView)
            IconButton(
              tooltip: 'Create request',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _workModeKey.currentState?.openCreateDialog(),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE3E6EF)),
            ),
            child: Text(
              _isSelfView
                  ? 'This screen now uses the canonical Attendance > Requests work type flow (WFA / WFH / ON DUTY).'
                  : 'Legacy employee-profile work type requests were retired. Use Attendance > Requests for self-service requests and manager approvals.',
              style: const TextStyle(color: Colors.black87),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchText = value),
              decoration: InputDecoration(
                hintText: 'Search work type requests',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchText.isEmpty
                    ? null
                    : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchText = '');
                  },
                  icon: const Icon(Icons.close),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isSelfView
                ? WorkModeRequestTab(
              key: _workModeKey,
              searchText: _searchText,
              onCountChanged: (count) {
                if (!mounted) return;
                setState(() => _requestCount = count);
              },
            )
                : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 72,
                      color: Colors.black54,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Work Type Requests are now managed from Attendance > Requests. The employee-profile request view is no longer used.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context)
                          .pushNamed('/attendance_request'),
                      child: const Text('Open Attendance Requests'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _requestCount > 0
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Total visible requests: $_requestCount',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      )
          : null,
    );
  }
}
