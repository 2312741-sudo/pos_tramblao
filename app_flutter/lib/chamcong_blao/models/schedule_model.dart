import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum ShiftType { morning, afternoon, evening, off }

extension ShiftTypeExtension on ShiftType {
  String get label {
    switch (this) {
      case ShiftType.morning:
        return 'Ca sáng';
      case ShiftType.afternoon:
        return 'Ca chiều';
      case ShiftType.evening:
        return 'Ca tối';
      case ShiftType.off:
        return 'Nghỉ';
    }
  }

  String get value {
    switch (this) {
      case ShiftType.morning:
        return 'morning';
      case ShiftType.afternoon:
        return 'afternoon';
      case ShiftType.evening:
        return 'evening';
      case ShiftType.off:
        return 'off';
    }
  }

  String get timeRange {
    switch (this) {
      case ShiftType.morning:
        return '06:00 - 14:00';
      case ShiftType.afternoon:
        return '14:00 - 22:00';
      case ShiftType.evening:
        return '22:00 - 06:00';
      case ShiftType.off:
        return '';
    }
  }

  static ShiftType fromString(String? value) {
    switch (value) {
      case 'morning':
        return ShiftType.morning;
      case 'afternoon':
        return ShiftType.afternoon;
      case 'evening':
        return ShiftType.evening;
      case 'off':
      default:
        return ShiftType.off;
    }
  }
}

class DaySchedule {
  final List<String> monday;
  final List<String> tuesday;
  final List<String> wednesday;
  final List<String> thursday;
  final List<String> friday;
  final List<String> saturday;
  final List<String> sunday;

  const DaySchedule({
    this.monday = const [],
    this.tuesday = const [],
    this.wednesday = const [],
    this.thursday = const [],
    this.friday = const [],
    this.saturday = const [],
    this.sunday = const [],
  });

  factory DaySchedule.allOff() => const DaySchedule();

  static List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.map((e) => e.toString()).toList();
    if (data is String) {
      if (data == 'off' || data.isEmpty) return [];
      return [data];
    }
    return [];
  }

  factory DaySchedule.fromJson(dynamic json) {
    if (json == null || json is! Map) return const DaySchedule();
    return DaySchedule(
      monday: _parseList(json['monday']),
      tuesday: _parseList(json['tuesday']),
      wednesday: _parseList(json['wednesday']),
      thursday: _parseList(json['thursday']),
      friday: _parseList(json['friday']),
      saturday: _parseList(json['saturday']),
      sunday: _parseList(json['sunday']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monday': monday,
      'tuesday': tuesday,
      'wednesday': wednesday,
      'thursday': thursday,
      'friday': friday,
      'saturday': saturday,
      'sunday': sunday,
    };
  }

  List<String> shiftForDay(int weekday) {
    switch (weekday) {
      case 1: return monday;
      case 2: return tuesday;
      case 3: return wednesday;
      case 4: return thursday;
      case 5: return friday;
      case 6: return saturday;
      case 7: return sunday;
      default: return [];
    }
  }

  DaySchedule copyWith({
    List<String>? monday,
    List<String>? tuesday,
    List<String>? wednesday,
    List<String>? thursday,
    List<String>? friday,
    List<String>? saturday,
    List<String>? sunday,
  }) {
    return DaySchedule(
      monday: monday ?? this.monday,
      tuesday: tuesday ?? this.tuesday,
      wednesday: wednesday ?? this.wednesday,
      thursday: thursday ?? this.thursday,
      friday: friday ?? this.friday,
      saturday: saturday ?? this.saturday,
      sunday: sunday ?? this.sunday,
    );
  }

  int get workingDays {
    final days = [monday, tuesday, wednesday, thursday, friday, saturday, sunday];
    return days.where((s) => s.isNotEmpty).length;
  }
}

class ScheduleModel extends Equatable {
  final String id;
  final String storeId;
  final String weekStart; // YYYY-MM-DD (Monday of the week)
  final Map<String, DaySchedule> shifts; // userId → DaySchedule

  const ScheduleModel({
    required this.id,
    required this.storeId,
    required this.weekStart,
    required this.shifts,
  });

  factory ScheduleModel.fromJson(Map<String, dynamic> json, String id) {
    final parsedShifts = <String, DaySchedule>{};

    // 1. Parse standard nested map json['shifts']
    final shiftsData = json['shifts'];
    if (shiftsData is Map) {
      for (final entry in shiftsData.entries) {
        final key = entry.key.toString();
        if (entry.value != null) {
          parsedShifts[key] = DaySchedule.fromJson(entry.value);
        }
      }
    }

    // 2. Also parse any flattened 'shifts.<userId>' keys at root level
    for (final entry in json.entries) {
      if (entry.key.startsWith('shifts.') && entry.key.length > 7) {
        final userId = entry.key.substring(7);
        if (entry.value != null && !parsedShifts.containsKey(userId)) {
          parsedShifts[userId] = DaySchedule.fromJson(entry.value);
        }
      }
    }

    return ScheduleModel(
      id: id,
      storeId: json['storeId'] as String? ?? '',
      weekStart: json['weekStart'] as String? ?? '',
      shifts: parsedShifts,
    );
  }

  factory ScheduleModel.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    if (rawData == null || rawData is! Map) {
      return ScheduleModel(
        id: doc.id,
        storeId: '',
        weekStart: doc.id,
        shifts: const {},
      );
    }
    final data = Map<String, dynamic>.from(rawData);
    return ScheduleModel.fromJson(data, doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'storeId': storeId,
      'weekStart': weekStart,
      'shifts': shifts.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  ScheduleModel copyWith({
    String? id,
    String? storeId,
    String? weekStart,
    Map<String, DaySchedule>? shifts,
  }) {
    return ScheduleModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      weekStart: weekStart ?? this.weekStart,
      shifts: shifts ?? Map.from(this.shifts),
    );
  }

  ScheduleModel withUserShift(String userId, DaySchedule schedule) {
    final updated = Map<String, DaySchedule>.from(shifts);
    updated[userId] = schedule;
    return copyWith(shifts: updated);
  }

  DaySchedule? getScheduleForUser(String userId) => shifts[userId];

  @override
  List<Object?> get props => [id, storeId, weekStart, shifts];

  @override
  String toString() =>
      'ScheduleModel(id: $id, storeId: $storeId, weekStart: $weekStart, members: ${shifts.length})';
}
