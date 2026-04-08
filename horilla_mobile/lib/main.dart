import 'dart:async';
import 'dart:convert';
import 'dart:io';
// import 'package:flutter_face_api_beta/flutter_face_api.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_views/attendance_attendance.dart';
import 'attendance_views/attendance_punching_history.dart';
import 'attendance_views/attendance_overview.dart';
import 'attendance_views/attendance_request.dart';
import 'attendance_views/hour_account.dart';
import 'attendance_views/my_attendance_view.dart';
import 'checkin_checkout/checkin_checkout_views/checkin_checkout_form.dart';
import 'employee_views/employee_form.dart';
import 'employee_views/employee_list.dart';
import 'horilla_leave/all_assigned_leave.dart';
import 'horilla_leave/leave_allocation_request.dart';
import 'horilla_leave/leave_overview.dart';
import 'horilla_leave/leave_request.dart';
import 'horilla_leave/leave_types.dart';
import 'horilla_leave/my_leave_request.dart';
import 'horilla_leave/selected_leave_type.dart';
import 'horilla_main/login.dart';
import 'horilla_main/home.dart';
import 'horilla_main/notification_router.dart';
import 'horilla_main/notifications_list.dart';
import 'package:http/http.dart' as http;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// var faceSdk = FaceSDK.instance;
int currentPage = 1;
bool isFirstFetch = true;
Set<int> seenNotificationIds = {};
List<Map<String, dynamic>> notifications = [];
int notificationsCount = 0;
bool isLoading = true;
Timer? _notificationTimer;
late Map<String, dynamic> arguments = {};
List<Map<String, dynamic>> fetchedNotifications = [];
Map<String, dynamic> newNotificationList = {};
bool isAuthenticated = false;

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse notificationResponse) async {}

void _startNotificationTimer() {
  _notificationTimer?.cancel();
  _notificationTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
    if (isAuthenticated) {
      fetchNotifications();
      unreadNotificationsCount();
    } else {
      timer.cancel();
      _notificationTimer = null;
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await faceSdk.initialize();

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/horilla_logo');

  final DarwinInitializationSettings initializationSettingsIOS =
  DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) async {
      final context = navigatorKey.currentContext;
      if (context == null || !isAuthenticated) return;
      final record = notificationRecordFromSerializedPayload(details.payload);
      final recordId = int.tryParse((record?['id'] ?? '').toString());
      if (recordId != null) {
        await markNotificationRead(recordId);
      }
      if (record != null) {
        await openNotificationFromRecord(context, record);
      } else {
        Navigator.pushNamed(context, '/notifications_list');
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  final prefs = await SharedPreferences.getInstance();
  isAuthenticated = prefs.getString('token') != null;

  if (isAuthenticated) {
    _startNotificationTimer();
    prefetchData();
  }

  runApp(LoginApp());
  clearSharedPrefs();
}

void clearSharedPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('clockCheckedIn');
  await prefs.remove('checkout');
  await prefs.remove('checkin');
}

Future<void> _onSelectNotification(BuildContext context, {Map<String, dynamic>? record}) async {
  if (record != null) {
    if (record['id'] != null) {
      await markNotificationRead(record['id'] as int);
    }
    await openNotificationFromRecord(context, record);
    return;
  }
  Navigator.pushNamed(context, '/notifications_list');
}

void _showNotification() async {
  if (!isAuthenticated) return;
  FlutterRingtonePlayer().playNotification();
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
  AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      channelDescription: 'your_channel_description',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false,
      silent: true
  );

  const NotificationDetails platformChannelSpecifics =
  NotificationDetails(android: androidPlatformChannelSpecifics);
  final record = Map<String, dynamic>.from(newNotificationList);
  final body = extractNotificationMessage(record);

  final notificationId = int.tryParse((record['id'] ?? '').toString()) ?? 0;

  await flutterLocalNotificationsPlugin.show(
    notificationId,
    record['verb'],
    body,
    platformChannelSpecifics,
    payload: jsonEncode(record),
  );
}

Future<void> prefetchData() async {
  if (!isAuthenticated) return;

  final prefs = await SharedPreferences.getInstance();
  var token = prefs.getString("token");
  var typed_serverUrl = prefs.getString("typed_url");
  var employeeId = prefs.getInt("employee_id");

  if (token == null || typed_serverUrl == null || employeeId == null) return;

  var uri = Uri.parse('$typed_serverUrl/api/employee/employees/$employeeId');

  try {
    final response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    }).timeout(const Duration(seconds: 5));

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
        'employee_profile': responseData['employee_profile'],
        'job_position_name': responseData['job_position_name']
      };
    }
  } on TimeoutException catch (e) {
    debugPrint('prefetchData timeout: $e');
  } on SocketException catch (e) {
    debugPrint('prefetchData socket error: $e');
  } catch (e) {
    debugPrint('prefetchData error: $e');
  }

}

Future<void> markAllReadNotification() async {
  if (!isAuthenticated) return;

  final prefs = await SharedPreferences.getInstance();
  var token = prefs.getString("token");
  var typed_serverUrl = prefs.getString("typed_url");

  if (token == null || typed_serverUrl == null) return;

  var uri = Uri.parse('$typed_serverUrl/api/notifications/notifications/bulk-read/');
  var response = await http.post(uri, headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer $token",
  });

  if (response.statusCode == 200) {
    notifications.clear();
    unreadNotificationsCount();
    fetchNotifications();
  }
}

Future<void> markNotificationRead(int notificationId) async {
  if (!isAuthenticated) return;
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  final typedServerUrl = prefs.getString('typed_url');
  if (token == null || typedServerUrl == null) return;

  final uri = Uri.parse('$typedServerUrl/api/notifications/notifications/$notificationId/');
  final response = await http.post(uri, headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  });

  if (response.statusCode == 200) {
    notifications = notifications.where((item) => item['id'] != notificationId).toList();
    await unreadNotificationsCount();
  }
}

Future<void> fetchNotifications() async {
  if (!isAuthenticated) {
    print('Notification fetch stopped - unauthenticated');
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  var token = prefs.getString("token");
  var typed_serverUrl = prefs.getString("typed_url");

  if (token == null || typed_serverUrl == null) {
    print('Missing required data for notifications');
    return;
  }


  try {
    print('Fetching notifications...');
    var uri = Uri.parse(
        '$typed_serverUrl/api/notifications/notifications/list/unread?page=${currentPage == 0 ? 1 : currentPage}');

    var response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    }).timeout(Duration(seconds: 3));

    if (response.statusCode == 200) {
      List<Map<String, dynamic>> fetchedNotifications =
      List<Map<String, dynamic>>.from(
        jsonDecode(response.body)['results']
            .where((notification) => notification['deleted'] == false)
            .toList(),
      );

      if (fetchedNotifications.isNotEmpty) {
        final unseen = fetchedNotifications.where((notification) => !seenNotificationIds.contains(notification['id'] as int)).toList();
        newNotificationList = unseen.isNotEmpty ? unseen.first : fetchedNotifications.first;
        final List<int> newNotificationIds = fetchedNotifications
            .map((notification) => notification['id'] as int)
            .toList();

        final bool hasNewNotifications = unseen.isNotEmpty;

        if (!isFirstFetch && hasNewNotifications) {
          _playNotificationSound();
        }

        seenNotificationIds.addAll(newNotificationIds);
        notifications = fetchedNotifications;
        notificationsCount = jsonDecode(response.body)['count'];
        isFirstFetch = false;
        isLoading = false;
      } else {
        print("No notifications available.");
      }
    } else {
      print('Notification fetch failed with status: ${response.statusCode}');
    }
  } on SocketException catch (e) {
    print('Connection error fetching notifications: $e');
  } on TimeoutException catch (e) {
    print('Timeout fetching notifications: $e');
  } on Exception catch (e) {
    print('Error fetching notifications: $e');
  }
}

Future<void> unreadNotificationsCount() async {
  if (!isAuthenticated) return;

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString("token");
  final typed_serverUrl = prefs.getString("typed_url");

  if (token == null || typed_serverUrl == null) return;

  final uri = Uri.parse('$typed_serverUrl/api/notifications/notifications/list/unread');

  try {
    final response = await http.get(uri, headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    }).timeout(const Duration(seconds: 3));

    if (response.statusCode == 200) {
      notificationsCount = jsonDecode(response.body)['count'];
      isLoading = false;
      return;
    }

    print('Unread notifications count failed with status: ${response.statusCode}');
  } on SocketException catch (e) {
    print('Connection error fetching unread notifications count: $e');
  } on TimeoutException catch (e) {
    print('Timeout fetching unread notifications count: $e');
  } catch (e) {
    print('Error fetching unread notifications count: $e');
  }
}

void _playNotificationSound() {
  if (!isAuthenticated) return;
  _showNotification();
}

class LoginApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login Page',
      navigatorKey: navigatorKey,
      home: FutureBuilderPage(),
      routes: {
        '/login': (context) => LoginPage(),
        '/home': (context) => HomePage(),
        '/employees_list': (context) => EmployeeListPage(),
        '/employees_form': (context) => EmployeeFormPage(),
        '/attendance_overview': (context) => AttendanceOverview(),
        '/attendance_attendance': (context) => AttendanceAttendance(),
        '/attendance_punching_history': (context) => AttendancePunchingHistoryPage(),
        '/attendance_request': (context) => AttendanceRequest(),
        '/my_attendance_view': (context) => MyAttendanceViews(),
        '/employee_hour_account': (context) => HourAccountFormPage(),
        '/employee_checkin_checkout': (context) => CheckInCheckOutFormPage(),
        '/leave_overview': (context) => LeaveOverview(),
        '/leave_types': (context) => LeaveTypes(),
        '/my_leave_request': (context) => MyLeaveRequest(),
        '/leave_request': (context) => LeaveRequest(),
        '/leave_allocation_request': (context) => LeaveAllocationRequest(),
        '/all_assigned_leave': (context) => AllAssignedLeave(),
        '/selected_leave_type': (context) => SelectedLeaveType(),
        '/notifications_list': (context) => NotificationsList(),
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'Assets/horilla-logo.png',
              width: 150,
              height: 150,
            ),
          ],
        ),
      ),
    );
  }
}

class FutureBuilderPage extends StatefulWidget {
  const FutureBuilderPage({super.key});

  @override
  State<FutureBuilderPage> createState() => _FutureBuilderPageState();
}

class _FutureBuilderPageState extends State<FutureBuilderPage> {
  late Future<bool> _futurePath;

  bool _hasUsableValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  bool _hasUsableServerUrl(String? value) {
    if (!_hasUsableValue(value)) {
      return false;
    }
    final uri = Uri.tryParse(value!.trim());
    if (uri == null) {
      return false;
    }
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _futurePath = _initialize();
  }

  Future<bool> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final typedUrl = prefs.getString("typed_url");
    return _hasUsableValue(token) && _hasUsableServerUrl(typedUrl);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Future.delayed(const Duration(seconds: 2), () => _futurePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SplashScreen();
        }

        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasData && snapshot.data == true) {
            return const HomePage();
          } else {
            return LoginPage();
          }
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
