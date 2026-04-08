import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shimmer/shimmer.dart';
import '../res/utilities/permission_guard.dart';
import 'notification_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {

  Future<void> _openLeaveModule() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedServerUrl = prefs.getString("typed_url");
    if (!mounted) return;
    if (typedServerUrl == null || typedServerUrl.isEmpty) {
      Navigator.pushNamed(context, '/my_leave_request');
      return;
    }

    final result = await guardedPermissionGet(
      Uri.parse('$typedServerUrl/api/leave/check-perm/'),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
    );
    if (!mounted) return;
    if (result.isAllowed) {
      Navigator.pushNamed(context, '/leave_overview');
      return;
    }
    if (result.isUnauthorized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Session expired, please log in again.')),
      );
      return;
    }
    Navigator.pushNamed(context, '/my_leave_request');
  }

  Future<http.Response?> _safeGet(Uri uri, String? token) async {
    if (token == null) return null;
    try {
      return await http
          .get(uri, headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      })
          .timeout(const Duration(seconds: 5));
    } on TimeoutException catch (e) {
      debugPrint('GET timeout: $uri -> $e');
      return null;
    } on SocketException catch (e) {
      debugPrint('GET socket error: $uri -> $e');
      return null;
    } catch (e) {
      debugPrint('GET error: $uri -> $e');
      return null;
    }
  }
  late StreamSubscription subscription;
  var isDeviceConnected = false;
  final ScrollController _scrollController = ScrollController();
  final _pageController = PageController(initialPage: 0);
  final _controller = NotchBottomBarController(index: 0);
  late Map<String, dynamic> arguments = {};
  bool permissionCheck = false;
  bool isLoading = true;
  bool isFirstFetch = true;
  bool isAlertSet = false;
  bool permissionWardCheck = false;
  int initialTabIndex = 0;
  int notificationsCount = 0;
  int maxCount = 5;
  String? duration;
  List<Map<String, dynamic>> notifications = [];
  Timer? _notificationTimer;
  Set<int> seenNotificationIds = {};
  int currentPage = 0;
  late final AnimatedMapController _mapController;
  bool _isPermissionLoading = true;
  bool isAuthenticated = true;


  @override
  void initState() {
    super.initState();
    clearPermissionGuardCache();
    _mapController = AnimatedMapController(vsync: this);
    _scrollController.addListener(_scrollListener);
    _initializePermissionsAndData();
  }


  Future _initializePermissionsAndData() async {
    await checkAllPermissions();
    await Future.wait([
      permissionWardChecks(),
      fetchNotifications(),
      unreadNotificationsCount(),
      prefetchData(),
      fetchData(),
    ]);
    setState(() {
      _isPermissionLoading = false;
      isLoading = false;
    });
  }



  void getConnectivity() {
    subscription = InternetConnectionChecker().onStatusChange.listen((status) {
      setState(() {
        isDeviceConnected = status == InternetConnectionStatus.connected;
        if (!isDeviceConnected && !isAlertSet) {
          showSnackBar();
          isAlertSet = true;
        } else if (isDeviceConnected && isAlertSet) {
          isAlertSet = false;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      });
    });
  }

  final List<Widget> bottomBarPages = [
    const Home(),
    const Overview(),
    const User(),
  ];

  void _scrollListener() {
    if (_scrollController.offset >=
        _scrollController.position.maxScrollExtent &&
        !_scrollController.position.outOfRange) {
      currentPage++;
      fetchNotifications();
    }
  }

  Future<void> fetchData() async {
    await permissionWardChecks();
    setState(() {});
  }

  void permissionChecks() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri =
    Uri.parse('$typedServerUrl/api/attendance/permission-check/attendance');
    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    setState(() {
      permissionCheck = response.statusCode == 200;
    });
  }

  Future<void> permissionWardChecks() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse('$typedServerUrl/api/ward/check-ward/');
    final response = await _safeGet(uri, token);

    if (response == null) return;
    if (!mounted) return;
    setState(() {
      permissionWardCheck = response.statusCode == 200;
    });
  }

  Future<void> prefetchData() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var employeeId = prefs.getInt("employee_id");
    var uri = Uri.parse('$typedServerUrl/api/employee/employees/$employeeId');
    final response = await _safeGet(uri, token);

    if (response == null) return;

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        arguments = {
          'employee_id': responseData['id'] ?? '',
          'employee_name': (responseData['employee_first_name'] ?? '') +
              ' ' +
              (responseData['employee_last_name'] ?? ''),
          'badge_id': responseData['badge_id'] ?? '',
          'email': responseData['email'] ?? '',
          'phone': responseData['phone'] ?? '',
          'date_of_birth': responseData['dob'] ?? '',
          'gender': responseData['gender'] ?? '',
          'address': responseData['address'] ?? '',
          'country': responseData['country'] ?? '',
          'state': responseData['state'] ?? '',
          'city': responseData['city'] ?? '',
          'qualification': responseData['qualification'] ?? '',
          'experience': responseData['experience'] ?? '',
          'marital_status': responseData['marital_status'] ?? '',
          'children': responseData['children'] ?? '',
          'emergency_contact': responseData['emergency_contact'] ?? '',
          'emergency_contact_name': responseData['emergency_contact_name'] ?? '',
          'employee_work_info_id': responseData['employee_work_info_id'] ?? '',
          'employee_bank_details_id':
          responseData['employee_bank_details_id'] ?? '',
          'employee_profile': responseData['employee_profile'] ?? '',
          'job_position_name': responseData['job_position_name'] ?? ''
        };
      });
    }
  }

  Future<void> fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");

    List<Map<String, dynamic>> allNotifications = [];
    int page = 1;
    bool hasMore = true;

    while (hasMore) {
      var uri = Uri.parse(
          '$typedServerUrl/api/notifications/notifications/list/unread?page=$page');

      final response = await _safeGet(uri, token);

      if (response == null) return;

      if (response.statusCode == 200) {
        var responseData = jsonDecode(response.body);
        var results = responseData['results'] as List;

        if (results.isEmpty) break;

        // Filter out deleted notifications
        List<Map<String, dynamic>> fetched = results
            .where((n) => n['deleted'] == false)
            .cast<Map<String, dynamic>>()
            .toList();

        allNotifications.addAll(fetched);

        // Check if there's a next page
        if (responseData['next'] == null) {
          hasMore = false;
        } else {
          page++;
        }
      } else {
        print('Failed to fetch notifications: ${response.statusCode}');
        hasMore = false;
      }
    }

    // Deduplicate notifications by converting to JSON strings
    Set<String> uniqueMapStrings = allNotifications
        .map((notification) => jsonEncode(notification))
        .toSet();
    if (!mounted) return;
    setState(() {
      notifications = uniqueMapStrings
          .map((jsonString) => jsonDecode(jsonString))
          .cast<Map<String, dynamic>>()
          .toList();
      notificationsCount = notifications.length;
      isLoading = false;
    });
  }

  Future<void> unreadNotificationsCount() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse(
        '$typedServerUrl/api/notifications/notifications/list/unread');
    final response = await _safeGet(uri, token);

    if (response == null) return;

    if (response.statusCode == 200) {
      if (!mounted) return;
      setState(() {
        notificationsCount = jsonDecode(response.body)['count'];
        isLoading = false;
      });
    }
  }

  Future<void> markReadNotification(int notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse(
        '$typedServerUrl/api/notifications/notifications/$notificationId/');
    var response = await http.post(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      setState(() {
        notifications.removeWhere((item) => item['id'] == notificationId);
        unreadNotificationsCount();
        fetchNotifications();
      });
    }
  }


  Future<void> _openNotificationForRecord(Map<String, dynamic> record) async {
    final notificationId = record['id'];
    if (notificationId is int && record['unread'] == true) {
      await markReadNotification(notificationId);
    }
    if (!mounted) return;
    await openNotificationFromRecord(context, record);
  }

  Future<void> markAllReadNotification() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri =
    Uri.parse('$typedServerUrl/api/notifications/notifications/bulk-read/');
    var response = await http.post(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      setState(() {
        notifications.clear();
        unreadNotificationsCount();
        fetchNotifications();
      });
    }
  }

  Future checkAllPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");

    Future<bool> _getPerm(String endpoint) async {
      try {
        var uri = Uri.parse('$typedServerUrl$endpoint');
        var res = await http.get(uri, headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        });
        return res.statusCode == 200;
      } catch (e) {
        print("Permission check failed for $endpoint: $e");
        return false;
      }
    }

    bool overview = await _getPerm("/api/attendance/permission-check/attendance");
    bool att = true;
    bool attReq = true;
    bool hourAcc = true;



    await prefs.setBool("perm_overview", overview);
    await prefs.setBool("perm_attendance", att);
    await prefs.setBool("perm_attendance_request", attReq);
    await prefs.setBool("perm_hour_account", hourAcc);

    print("✅ Permissions saved in SharedPreferences");
  }

  Future<void> clearAllUnreadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString("token");
    var typedServerUrl = prefs.getString("typed_url");
    var uri = Uri.parse(
        '$typedServerUrl/api/notifications/notifications/bulk-delete-unread/');
    var response = await http.delete(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    });
    if (response.statusCode == 200) {
      setState(() {
        notifications.clear();
        unreadNotificationsCount();
        fetchNotifications();
      });
    }
  }

  Future<void> clearToken(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    // Stop timers before wiping everything
    _notificationTimer?.cancel();
    _notificationTimer = null;

    // Clear ALL cached data (token, typed_url, face cache, employee_id, etc.)
    await prefs.clear();

    isAuthenticated = false;

    if (!mounted) return;

    // Use replacement so user can't go back into Home
    Navigator.pushReplacementNamed(context, "/login");
  }



  Future<void> showSavedAnimation() async {
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
                    Image.asset(imagePath,
                        width: 180, height: 180, fit: BoxFit.cover),
                    const SizedBox(height: 16),
                    const Text(
                      "Values Marked Successfully",
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
    Future.delayed(const Duration(seconds: 3), () async {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(),
        ),
      );
    });
  }

  void _showUnreadNotifications(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Stack(
              children: [
                AlertDialog(
                  backgroundColor: Colors.white,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Notifications",
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width * 0.05,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await markAllReadNotification();
                              Navigator.pop(context);
                              _showUnreadNotifications(context);
                            },
                            icon: Icon(Icons.done_all,
                                color: Colors.red,
                                size:
                                MediaQuery.of(context).size.width * 0.0357),
                            label: Text(
                              'Mark as Read',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: MediaQuery.of(context).size.width *
                                      0.0368),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await clearAllUnreadNotifications();
                              Navigator.pop(context);
                              _showUnreadNotifications(context);
                            },
                            icon: Icon(Icons.clear,
                                color: Colors.red,
                                size:
                                MediaQuery.of(context).size.width * 0.0357),
                            label: Text(
                              'Clear all',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: MediaQuery.of(context).size.width *
                                      0.0368),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16.0),
                      Container(
                        width: MediaQuery.of(context).size.width * 0.8,
                        height: MediaQuery.of(context).size.height * 0.3,
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.8,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal:
                              MediaQuery.of(context).size.width * 0.0357),
                          child: Center(
                            child: isLoading
                                ? Shimmer.fromColors(
                              baseColor: Colors.grey[300]!,
                              highlightColor: Colors.grey[100]!,
                              child: ListView.builder(
                                itemCount: 3,
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8.0),
                                  child: Container(
                                    width: double.infinity,
                                    height: MediaQuery.of(context)
                                        .size
                                        .height *
                                        0.0616,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                                : notifications.isEmpty
                                ? Center(
                              child: Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.notifications,
                                    color: Colors.black,
                                    size: MediaQuery.of(context)
                                        .size
                                        .width *
                                        0.2054,
                                  ),
                                  SizedBox(
                                      height: MediaQuery.of(context)
                                          .size
                                          .height *
                                          0.0205),
                                  Text(
                                    "There are no notification records to display",
                                    style: TextStyle(
                                      fontSize: MediaQuery.of(context)
                                          .size
                                          .width *
                                          0.0268,
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )
                                : Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: notifications.length,
                                    itemBuilder: (context, index) {
                                      final record =
                                      notifications[index];
                                      return Padding(
                                        padding:
                                        const EdgeInsets.all(4.0),
                                        child: Column(
                                          children: [
                                            if (record['verb'] !=
                                                null)
                                              buildListItem(context,
                                                  record, index),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                  actions: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/notifications_list');
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                              horizontal:
                              MediaQuery.of(context).size.width * 0.0134,
                              vertical:
                              MediaQuery.of(context).size.width * 0.0134),
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'View all notifications',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize:
                              MediaQuery.of(context).size.width * 0.0335),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget buildListItem(
      BuildContext context, Map<String, dynamic> record, int index) {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: GestureDetector(
        onTap: () async {
          await _openNotificationForRecord(record);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red.shade100),
            borderRadius: BorderRadius.circular(8.0),
            color: Colors.red.shade100,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.3),
                spreadRadius: 2,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
                vertical: MediaQuery.of(context).size.height * 0.0082),
            child: Container(
              color: Colors.red.shade100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, top: 6.0),
                    child: Container(
                      margin: EdgeInsets.only(
                          right: MediaQuery.of(context).size.width * 0.0357),
                      width: MediaQuery.of(context).size.width * 0.0223,
                      height: MediaQuery.of(context).size.width * 0.0223,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.shade500,
                        border: Border.all(
                            color: Colors.grey,
                            width: MediaQuery.of(context).size.width * 0.0022),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record['verb'],
                          style: TextStyle(
                              fontSize:
                              MediaQuery.of(context).size.width * 0.0313,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          extractNotificationMessage(record),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize:
                              MediaQuery.of(context).size.width * 0.0268),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GestureDetector(
                      onTap: () async {
                        var notificationId = record['id'];
                        await markReadNotification(notificationId);
                        Navigator.pop(context);
                        _showUnreadNotifications(context);
                      },
                      child: Icon(
                        Icons.check,
                        color: Colors.red.shade500,
                        size: 20.0,
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        forceMaterialTransparency: true,
        backgroundColor: Colors.white,
        title: const Text(
          'Modules',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        automaticallyImplyLeading: false,
        actions: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications,
                  color: Colors.black,
                ),
                onPressed: () {
                  Navigator.pushNamed(context, '/notifications_list');
                },
              ),
              if (notificationsCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width * 0.012,
                      vertical: MediaQuery.of(context).size.width * 0.004,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width * 0.032,
                      minHeight: MediaQuery.of(context).size.height * 0.016,
                    ),
                    child: Center(
                      child: Text(
                        '$notificationsCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: MediaQuery.of(context).size.width * 0.018,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(
              Icons.logout,
              color: Colors.black,
            ),
            onPressed: () async {
              await clearToken(context);
            },
          )
        ],
      ),
      body: _isPermissionLoading
          ? Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ListView(
            children: [
              const SizedBox(height: 50.0),
              const SizedBox(height: 50.0),
              Card(
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    color: Colors.white,
                  ),
                  title: Container(
                    width: double.infinity,
                    height: 20,
                    color: Colors.white,
                  ),
                  subtitle: Container(
                    width: double.infinity,
                    height: 16,
                    color: Colors.white,
                  ),
                  trailing: Container(
                    width: 24,
                    height: 24,
                    color: Colors.white,
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    color: Colors.white,
                  ),
                  title: Container(
                    width: double.infinity,
                    height: 20,
                    color: Colors.white,
                  ),
                  subtitle: Container(
                    width: double.infinity,
                    height: 16,
                    color: Colors.white,
                  ),
                  trailing: Container(
                    width: 24,
                    height: 24,
                    color: Colors.white,
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    color: Colors.white,
                  ),
                  title: Container(
                    width: double.infinity,
                    height: 20,
                    color: Colors.white,
                  ),
                  subtitle: Container(
                    width: double.infinity,
                    height: 16,
                    color: Colors.white,
                  ),
                  trailing: Container(
                    width: 24,
                    height: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView(
          children: [
            const SizedBox(height: 50.0),
            const SizedBox(height: 50.0),
            Card(
              child: ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Employees'),
                subtitle: Text(
                  'View and manage all your employees.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () {
                  Navigator.pushNamed(context, '/employees_list',
                      arguments: permissionCheck);
                },
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.checklist_rtl),
                title: const Text('Attendances'),
                subtitle: Text(
                  'Record and view employee information.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () {
                  if (permissionCheck) {
                    Navigator.pushNamed(context, '/attendance_overview',
                        arguments: permissionCheck);
                  } else {
                    Navigator.pushNamed(context, '/attendance_attendance',
                        arguments: permissionCheck);
                  }
                },
              ),
            ),
            Card(
              child: GestureDetector(
                onTap: () async {
                  await _openLeaveModule();
                },
                child: ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Leaves'),
                  subtitle: Text(
                    'Record and view Leave information',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  trailing: const Icon(Icons.keyboard_arrow_right),
                ),
              ),
            ),
          ],
        ),
      ),
      extendBody: true,
      bottomNavigationBar: (bottomBarPages.length <= maxCount)
          ? SafeArea(
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
          bottomBarWidth: MediaQuery.of(context).size.width * 1,
          durationInMilliSeconds: 500,
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
                Future.delayed(const Duration(milliseconds: 1000), () {
                  Navigator.pushNamed(context, '/home');
                });
                break;
              case 1:
                Future.delayed(const Duration(milliseconds: 1000), () {
                  Navigator.pushNamed(context, '/employee_checkin_checkout');
                });
                break;
              case 2:
                Future.delayed(const Duration(milliseconds: 1000), () {
                  Navigator.pushNamed(context, '/employees_form',
                      arguments: arguments);
                });
                break;
            }
          },
        ),
      )
          : null,
    );
  }

  void showSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red,
        content: const Text('Please check your internet connectivity',
            style: TextStyle(color: Colors.white)),
        action: SnackBarAction(
          backgroundColor: Colors.red,
          label: 'close',
          textColor: Colors.white,
          onPressed: () async {
            setState(() => isAlertSet = false);
            isDeviceConnected = await InternetConnectionChecker().hasConnection;
            if (!isDeviceConnected && !isAlertSet) {
              showSnackBar();
              setState(() => isAlertSet = true);
            }
          },
        ),
        duration: const Duration(hours: 1),
      ),
    );
  }
}

class Home extends StatelessWidget {
  const Home({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushNamed(context, '/home');
    });
    return Container(
      color: Colors.white,
      child: const Center(child: Text('Page 1')),
    );
  }
}

class Overview extends StatelessWidget {
  const Overview({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
        color: Colors.white, child: const Center(child: Text('Page 2')));
  }
}

class User extends StatelessWidget {
  const User({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushNamed(context, '/user');
    });
    return Container(
      color: Colors.white,
      child: const Center(child: Text('Page 1')),
    );
  }
}
