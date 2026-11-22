import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum CheckInMethod { wifi, gps, manual, qr }

extension CheckInMethodExtension on CheckInMethod {
  String get label {
    switch (this) {
      case CheckInMethod.wifi:
        return 'WiFi';
      case CheckInMethod.gps:
        return 'GPS';
      case CheckInMethod.manual:
        return 'Thủ công';
      case CheckInMethod.qr:
        return 'Mã QR';
    }
  }

  String get value {
    switch (this) {
      case CheckInMethod.wifi:
        return 'wifi';
      case CheckInMethod.gps:
        return 'gps';
      case CheckInMethod.manual:
        return 'manual';
      case CheckInMethod.qr:
        return 'qr';
    }
  }

  static CheckInMethod fromString(String? value) {
    switch (value) {
      case 'gps':
        return CheckInMethod.gps;
      case 'manual':
        return CheckInMethod.manual;
      case 'qr':
        return CheckInMethod.qr;
      case 'wifi':
      default:
        return CheckInMethod.wifi;
    }
  }
}

class AttendanceModel extends Equatable {
  final String id;
  final String userId;
  final String storeId;
  final String date; // YYYY-MM-DD
  final DateTime checkIn; // stored as UTC
  final DateTime? checkOut; // stored as UTC
  final CheckInMethod checkInMethod;
  final double totalHours; // calculated on checkOut
  final bool isEdited;
  final String? editedBy;
  final String? editNote;
  final bool isOffline; // synced from offline storage

  const AttendanceModel({
    required this.id,
    required this.userId,
    required this.storeId,
    required this.date,
    required this.checkIn,
    this.checkOut,
    this.checkInMethod = CheckInMethod.wifi,
    this.totalHours = 0.0,
    this.isEdited = false,
    this.editedBy,
    this.editNote,
    this.isOffline = false,
  });

  // Getters
  bool get isActive => checkOut == null;

  String get formattedDuration {
    if (totalHours <= 0) {
      if (checkOut == null) {
        final now = DateTime.now().toUtc();
        final diff = now.difference(checkIn);
        final h = diff.inHours;
        final m = diff.inMinutes % 60;
        return '${h}h ${m.toString().padLeft(2, '0')}m';
      }
      return '0h 00m';
    }
    final h = totalHours.floor();
    final m = ((totalHours - h) * 60).round();
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  factory AttendanceModel.fromJson(Map<String, dynamic> json, String id) {
    DateTime parseDateTime(dynamic value) {
      if (value is Timestamp) return value.toDate().toUtc();
      if (value is String) {
        return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
      }
      return DateTime.now().toUtc();
    }

    return AttendanceModel(
      id: id,
      userId: json['userId'] as String? ?? '',
      storeId: json['storeId'] as String? ?? '',
      date: json['date'] as String? ?? '',
      checkIn: parseDateTime(json['checkIn']),
      checkOut: json['checkOut'] != null
          ? parseDateTime(json['checkOut'])
          : null,
      checkInMethod:
          CheckInMethodExtension.fromString(json['checkInMethod'] as String?),
      totalHours: (json['totalHours'] as num?)?.toDouble() ?? 0.0,
      isEdited: json['isEdited'] as bool? ?? false,
      editedBy: json['editedBy'] as String?,
      editNote: json['editNote'] as String?,
      isOffline: json['isOffline'] as bool? ?? false,
    );
  }

  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AttendanceModel.fromJson(data, doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'storeId': storeId,
      'date': date,
      'checkIn': Timestamp.fromDate(checkIn),
      'checkOut': checkOut != null ? Timestamp.fromDate(checkOut!) : null,
      'checkInMethod': checkInMethod.value,
      'totalHours': totalHours,
      'isEdited': isEdited,
      'editedBy': editedBy,
      'editNote': editNote,
      'isOffline': isOffline,
    };
  }

  AttendanceModel copyWith({
    String? id,
    String? userId,
    String? storeId,
    String? date,
    DateTime? checkIn,
    DateTime? checkOut,
    CheckInMethod? checkInMethod,
    double? totalHours,
    bool? isEdited,
    String? editedBy,
    String? editNote,
    bool? isOffline,
    bool clearCheckOut = false,
    bool clearEditedBy = false,
    bool clearEditNote = false,
  }) {
    return AttendanceModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      storeId: storeId ?? this.storeId,
      date: date ?? this.date,
      checkIn: checkIn ?? this.checkIn,
      checkOut: clearCheckOut ? null : (checkOut ?? this.checkOut),
      checkInMethod: checkInMethod ?? this.checkInMethod,
      totalHours: totalHours ?? this.totalHours,
      isEdited: isEdited ?? this.isEdited,
      editedBy: clearEditedBy ? null : (editedBy ?? this.editedBy),
      editNote: clearEditNote ? null : (editNote ?? this.editNote),
      isOffline: isOffline ?? this.isOffline,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        storeId,
        date,
        checkIn,
        checkOut,
        checkInMethod,
        totalHours,
        isEdited,
        editedBy,
        editNote,
        isOffline,
      ];

  @override
  String toString() =>
      'AttendanceModel(id: $id, userId: $userId, date: $date, isActive: $isActive)';
}
