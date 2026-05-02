import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../core/attendance_auto_close_policy.dart';
import 'institute_status_service.dart';
import 'notification_handler.dart';

/// Service for managing institute open/close notifications
class InstituteNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static final InstituteStatusService _statusService = InstituteStatusService();

  /// Initialize notification service
  static Future<void> initialize() async {
    // Initialize timezone data
    tz.initializeTimeZones();
    
    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions
    await _requestPermissions();

    // Initialize workmanager for background tasks
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );

    if (kDebugMode) debugPrint('✅ Institute notification service initialized');
  }

  /// Request notification permissions
  static Future<void> _requestPermissions() async {
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }

    final iosPlugin = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) debugPrint('📱 Notification tapped: ${response.payload}');
    // Handle notification tap
    NotificationHandler.handleNotificationTap(response.payload);
  }

  /// Schedule all notifications for an institute
  static Future<void> scheduleNotifications(String instituteId) async {
    try {
      // Cancel existing notifications for this institute
      await cancelNotifications(instituteId);

      // Get institute timing
      final timing = await _statusService.getInstituteTiming(instituteId);
      if (timing == null) {
        if (kDebugMode) debugPrint('⚠️ No timing found for institute: $instituteId');
        return;
      }

      final openHour = timing['openTime']?['hour'] ?? 8;
      final openMinute = timing['openTime']?['minute'] ?? 0;
      final closeHour = timing['closeTime']?['hour'] ?? 22;
      final closeMinute = timing['closeTime']?['minute'] ?? 0;

      // Schedule open notifications (1 hour, 30 min, 5 min before)
      await _scheduleOpenNotifications(instituteId, openHour, openMinute);

      // Schedule close notification
      await _scheduleCloseNotification(instituteId, closeHour, closeMinute);

      // Schedule auto-close check (30 minutes after close time)
      await _scheduleAutoCloseCheck(instituteId, closeHour, closeMinute);

      if (kDebugMode) debugPrint('✅ Scheduled notifications for institute: $instituteId');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error scheduling notifications: $e');
    }
  }

  /// Schedule open notifications (1 hour, 30 min, 5 min before)
  static Future<void> _scheduleOpenNotifications(String instituteId, int openHour, int openMinute) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, openHour, openMinute);

    // 1 hour before
    final oneHourBefore = today.subtract(const Duration(hours: 1));
    if (oneHourBefore.isAfter(now)) {
      await _scheduleNotification(
        id: _getNotificationId(instituteId, 'open_1h'),
        title: 'Institute Opening Soon',
        body: 'Institute opens in 1 hour. Tap to mark as open.',
        scheduledDate: oneHourBefore,
        payload: 'open_1h|$instituteId',
      );
    }

    // 30 minutes before
    final thirtyMinBefore = today.subtract(const Duration(minutes: 30));
    if (thirtyMinBefore.isAfter(now)) {
      await _scheduleNotification(
        id: _getNotificationId(instituteId, 'open_30m'),
        title: 'Institute Opening Soon',
        body: 'Institute opens in 30 minutes. Tap to mark as open.',
        scheduledDate: thirtyMinBefore,
        payload: 'open_30m|$instituteId',
      );
    }

    // 5 minutes before
    final fiveMinBefore = today.subtract(const Duration(minutes: 5));
    if (fiveMinBefore.isAfter(now)) {
      await _scheduleNotification(
        id: _getNotificationId(instituteId, 'open_5m'),
        title: 'Institute Opening Soon',
        body: 'Institute opens in 5 minutes. Tap to mark as open.',
        scheduledDate: fiveMinBefore,
        payload: 'open_5m|$instituteId',
      );
    }
  }

  /// Schedule close notification
  static Future<void> _scheduleCloseNotification(String instituteId, int closeHour, int closeMinute) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, closeHour, closeMinute);

    if (today.isAfter(now)) {
      await _scheduleNotification(
        id: _getNotificationId(instituteId, 'close'),
        title: 'Institute Closing Time',
        body: 'It\'s closing time. Tap to mark institute as closed.',
        scheduledDate: today,
        payload: 'close|$instituteId',
      );
    }
  }

  /// Schedule auto-close check (30 minutes after close time)
  static Future<void> _scheduleAutoCloseCheck(String instituteId, int closeHour, int closeMinute) async {
    final now = DateTime.now();
    final closeTime = DateTime(now.year, now.month, now.day, closeHour, closeMinute);
    final autoCloseTime = closeTime.add(const Duration(minutes: 30));

    if (autoCloseTime.isAfter(now)) {
      // Use workmanager for background task
      await Workmanager().registerOneOffTask(
        'auto_close_$instituteId',
        'autoCloseInstitute',
        inputData: {
          'instituteId': instituteId,
          'scheduledTime': autoCloseTime.millisecondsSinceEpoch,
        },
        initialDelay: Duration(
          milliseconds: autoCloseTime.millisecondsSinceEpoch - now.millisecondsSinceEpoch,
        ),
      );

      // Also send a notification reminder
      await _scheduleNotification(
        id: _getNotificationId(instituteId, 'auto_close'),
        title: 'Institute Not Closed',
        body: 'Institute was not marked as closed. Auto-closing in 30 minutes.',
        scheduledDate: closeTime,
        payload: 'auto_close_warning|$instituteId',
      );
    }
  }

  /// Schedule a single notification
  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'institute_status_channel',
        'Institute Status',
        channelDescription: 'Notifications for institute open/close status',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: _convertToTZDateTime(scheduledDate),
        notificationDetails: details,
        // Inexact avoids SCHEDULE_EXACT_ALARM (blocked by default Android 12+ / Play policies).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );

      if (kDebugMode) {
        debugPrint('📅 Scheduled notification: $title at ${scheduledDate.toString()}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error scheduling notification: $e');
    }
  }

  /// Convert wall-clock [dateTime] to [tz.TZDateTime] for zoned scheduling.
  ///
  /// Uses [tz.UTC] and [DateTime.millisecondsSinceEpoch] so we never touch
  /// [tz.local] (unset unless [tz.setLocalLocation] was called → LateInitializationError).
  static tz.TZDateTime _convertToTZDateTime(DateTime dateTime) {
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.UTC,
      dateTime.millisecondsSinceEpoch,
    );
  }

  /// Get unique notification ID
  static int _getNotificationId(String instituteId, String type) {
    // Generate unique ID from instituteId and type
    final hash = instituteId.hashCode + type.hashCode;
    return hash.abs() % 2147483647; // Max int32
  }

  /// Cancel all notifications for an institute
  static Future<void> cancelNotifications(String instituteId) async {
    try {
      final types = ['open_1h', 'open_30m', 'open_5m', 'close', 'auto_close'];
      for (var type in types) {
        final id = _getNotificationId(instituteId, type);
        await _notifications.cancel(id: id);
      }

      // Cancel workmanager tasks
      await Workmanager().cancelByUniqueName('auto_close_$instituteId');

      if (kDebugMode) debugPrint('✅ Cancelled notifications for institute: $instituteId');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error cancelling notifications: $e');
    }
  }

  /// Two hours after entry: remind staff to mark exit before the auto-close window.
  static const Duration attendanceExitReminderDelay = Duration(hours: 2);

  static int attendanceExitReminderNotificationId({
    required String instituteId,
    required String rollKey,
    required String dateKey,
    required String subjectTag,
  }) {
    final raw = 'att_exit_rem|$instituteId|$rollKey|$dateKey|$subjectTag';
    return raw.hashCode.abs() % 2147483647;
  }

  /// Schedule a one-shot reminder to complete exit photo for [rollKey] on [dateKey] (yyyy-MM-dd).
  static Future<void> scheduleAttendanceExitReminder({
    required String instituteId,
    required String rollKey,
    required String dateKey,
    required String subjectTag,
    required DateTime entryAtUtc,
  }) async {
    if (kIsWeb) return;
    try {
      final fireUtc = entryAtUtc.toUtc().add(attendanceExitReminderDelay);
      final nowUtc = DateTime.now().toUtc();
      if (!fireUtc.isAfter(nowUtc)) return;

      final deadlineUtc = entryAtUtc.toUtc().add(kAttendanceExitDeadlineDuration);
      if (!fireUtc.isBefore(deadlineUtc.subtract(const Duration(minutes: 1)))) {
        return;
      }

      final id = attendanceExitReminderNotificationId(
        instituteId: instituteId,
        rollKey: rollKey,
        dateKey: dateKey,
        subjectTag: subjectTag,
      );
      await _notifications.cancel(id: id);

      final fireLocal = fireUtc.toLocal();
      final subjHint = subjectTag == 'all' ? '' : ' — $subjectTag';
      await _scheduleAttendanceExitReminderNotification(
        id: id,
        title: 'Complete attendance',
        body:
            'Roll $rollKey$subjHint: mark exit soon (within ${kAttendanceExitDeadlineHours}h of entry).',
        scheduledDate: fireLocal,
        payload: 'pending_exit|$instituteId|$rollKey|$dateKey|$subjectTag',
      );

      if (kDebugMode) {
        debugPrint(
          '📅 Scheduled exit reminder for roll $rollKey at ${fireLocal.toIso8601String()}',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ scheduleAttendanceExitReminder: $e');
    }
  }

  static Future<void> cancelAttendanceExitReminder({
    required String instituteId,
    required String rollKey,
    required String dateKey,
    required String subjectTag,
  }) async {
    if (kIsWeb) return;
    try {
      final id = attendanceExitReminderNotificationId(
        instituteId: instituteId,
        rollKey: rollKey,
        dateKey: dateKey,
        subjectTag: subjectTag,
      );
      await _notifications.cancel(id: id);
      if (kDebugMode) debugPrint('✅ Cancelled exit reminder id=$id roll=$rollKey');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ cancelAttendanceExitReminder: $e');
    }
  }

  static Future<void> _scheduleAttendanceExitReminderNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'attendance_pending_exit_channel',
      'Attendance reminders',
      channelDescription: 'Reminders to complete exit attendance after entry',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _convertToTZDateTime(scheduledDate),
      notificationDetails: details,
      // Inexact avoids SCHEDULE_EXACT_ALARM (exact_alarms_not_permitted without special permission).
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  /// Send immediate notification (for testing or manual triggers)
  static Future<void> sendImmediateNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'institute_status_channel',
      'Institute Status',
      channelDescription: 'Notifications for institute open/close status',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}

/// Background task callback for workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (kDebugMode) debugPrint('🔄 Background task: $task');

    if (task == 'autoCloseInstitute') {
      final instituteId = inputData?['instituteId'] as String?;
      if (instituteId != null) {
        final statusService = InstituteStatusService();
        final result = await statusService.autoClose(instituteId);
        
        if (result['success'] == true) {
          // Send notification that institute was auto-closed
          await InstituteNotificationService.sendImmediateNotification(
            title: 'Institute Auto-Closed',
            body: 'Institute was automatically closed for today.',
            payload: 'auto_closed|$instituteId',
          );
        }
      }
    }

    return Future.value(true);
  });
}
