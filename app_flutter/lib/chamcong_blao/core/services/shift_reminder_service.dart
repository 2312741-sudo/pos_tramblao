import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../../models/schedule_model.dart';
import '../../features/store/screens/shift_settings_screen.dart';

class ShiftReminderItem {
  final int notifId;
  final String title;
  final String body;
  final DateTime shiftStart;
  final DateTime reminderTime;
  final String payload;

  const ShiftReminderItem({
    required this.notifId,
    required this.title,
    required this.body,
    required this.shiftStart,
    required this.reminderTime,
    required this.payload,
  });
}

class ShiftReminderService {
  static final ShiftReminderService _instance = ShiftReminderService._internal();
  factory ShiftReminderService() => _instance;
  ShiftReminderService._internal();

  FlutterLocalNotificationsPlugin? _notificationsPlugin;
  bool _initialized = false;

  /// Khởi tạo TimeZone và Notifications Plugin
  Future<void> initialize({FlutterLocalNotificationsPlugin? plugin}) async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      } catch (_) {
        // Fallback local location
      }

      _notificationsPlugin = plugin ?? FlutterLocalNotificationsPlugin();
      _initialized = true;
    } catch (e) {
      debugPrint('ShiftReminderService initialize error: $e');
    }
  }

  /// Tính toán danh sách các ca làm cần nhắc nhở (hàm thuần logic, 100% testable)
  List<ShiftReminderItem> calculateUpcomingReminders({
    required String storeId,
    required String storeName,
    required DaySchedule schedule,
    required String weekStart,
    List<ShiftDefinition>? customShifts,
    int minutesBefore = 15,
    DateTime? fromTime,
  }) {
    DateTime weekStartDate;
    try {
      weekStartDate = DateTime.parse(weekStart);
    } catch (e) {
      debugPrint('ShiftReminderService invalid weekStart: $weekStart');
      return [];
    }

    final daySchedules = [
      schedule.monday,
      schedule.tuesday,
      schedule.wednesday,
      schedule.thursday,
      schedule.friday,
      schedule.saturday,
      schedule.sunday,
    ];

    final now = fromTime ?? DateTime.now();
    final items = <ShiftReminderItem>[];

    for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
      final dayDate = weekStartDate.add(Duration(days: dayIndex));
      final shiftList = daySchedules[dayIndex];

      for (final rawShift in shiftList) {
        if (rawShift.isEmpty || rawShift == 'off') continue;
        final shiftId = rawShift.split('|')[0].trim();
        if (shiftId.isEmpty || shiftId == 'off') continue;

        // Xác định giờ bắt đầu ca làm
        int startHour = 6;
        int startMinute = 0;
        String shiftDisplayName = 'Ca làm';

        ShiftDefinition? matchedCustom;
        if (customShifts != null && customShifts.isNotEmpty) {
          try {
            matchedCustom = customShifts.firstWhere((s) => s.id == shiftId);
          } catch (_) {
            matchedCustom = null;
          }
        }

        if (matchedCustom != null) {
          startHour = matchedCustom.startHour;
          startMinute = matchedCustom.startMinute;
          shiftDisplayName = matchedCustom.name;
        } else {
          switch (shiftId) {
            case 'morning':
              startHour = 6;
              startMinute = 0;
              shiftDisplayName = 'Ca sáng';
              break;
            case 'afternoon':
              startHour = 14;
              startMinute = 0;
              shiftDisplayName = 'Ca chiều';
              break;
            case 'evening':
              startHour = 22;
              startMinute = 0;
              shiftDisplayName = 'Ca tối';
              break;
            default:
              startHour = 8;
              startMinute = 0;
              shiftDisplayName = 'Ca làm';
          }
        }

        final shiftStart = DateTime(
          dayDate.year,
          dayDate.month,
          dayDate.day,
          startHour,
          startMinute,
        );

        final reminderTime = shiftStart.subtract(Duration(minutes: minutesBefore));

        // Chỉ đặt lịch cho các ca có giờ nhắc trong tương lai
        if (reminderTime.isAfter(now)) {
          final notifId = ((dayDate.year % 100) * 1000000) +
              (dayDate.month * 10000) +
              (dayDate.day * 100) +
              (startHour % 100);

          final timeStr =
              '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';

          final payload = jsonEncode({
            'routePath': '/check-in',
            'storeId': storeId,
            'type': 'shift_reminder',
          });

          items.add(ShiftReminderItem(
            notifId: notifId,
            title: 'Nhắc nhở ca làm việc',
            body: 'Bạn có $shiftDisplayName tại $storeName bắt đầu lúc $timeStr (còn $minutesBefore phút). Chuẩn bị sẵn sàng nhé!',
            shiftStart: shiftStart,
            reminderTime: reminderTime,
            payload: payload,
          ));
        }
      }
    }

    return items;
  }

  /// Lên lịch nhắc nhở các ca làm việc trong tuần của người dùng.
  /// Nhắc trước ca làm [minutesBefore] phút (mặc định 15 phút).
  Future<int> scheduleWeekShifts({
    required String storeId,
    required String storeName,
    required DaySchedule schedule,
    required String weekStart,
    List<ShiftDefinition>? customShifts,
    int minutesBefore = 15,
  }) async {
    await initialize();

    final reminders = calculateUpcomingReminders(
      storeId: storeId,
      storeName: storeName,
      schedule: schedule,
      weekStart: weekStart,
      customShifts: customShifts,
      minutesBefore: minutesBefore,
    );

    if (reminders.isEmpty || _notificationsPlugin == null) {
      return reminders.length;
    }

    int scheduledCount = 0;
    for (final item in reminders) {
      try {
        final tzReminderTime = tz.TZDateTime.from(item.reminderTime, tz.local);

        await _notificationsPlugin!.zonedSchedule(
          item.notifId,
          item.title,
          item.body,
          tzReminderTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'shift_reminders',
              'Nhắc nhở ca làm',
              channelDescription: 'Thông báo nhắc nhở trước khi vào ca làm việc',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
              presentBanner: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: item.payload,
        );
        scheduledCount++;
      } catch (err) {
        debugPrint('ShiftReminderService zonedSchedule error: $err');
      }
    }

    return scheduledCount;
  }

  /// Hủy tất cả thông báo ca làm
  Future<void> cancelAllShiftReminders() async {
    await initialize();
    try {
      await _notificationsPlugin?.cancelAll();
    } catch (_) {}
  }
}
