import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'member_model.dart';

class UserSalaryRecord {
  final String userId;
  final String name;
  final double totalHours;
  final double standardHours;
  final double baseSalary; // in VND (thousands)
  final double calculatedSalary; // in VND (thousands)
  final EmployeeType employeeType;

  const UserSalaryRecord({
    required this.userId,
    required this.name,
    required this.totalHours,
    required this.standardHours,
    required this.baseSalary,
    required this.calculatedSalary,
    required this.employeeType,
  });

  factory UserSalaryRecord.fromJson(Map<String, dynamic> json, String userId) {
    return UserSalaryRecord(
      userId: userId,
      name: json['name'] as String? ?? '',
      totalHours: (json['totalHours'] as num?)?.toDouble() ?? 0.0,
      standardHours: (json['standardHours'] as num?)?.toDouble() ?? 0.0,
      baseSalary: (json['baseSalary'] as num?)?.toDouble() ?? 0.0,
      calculatedSalary: (json['calculatedSalary'] as num?)?.toDouble() ?? 0.0,
      employeeType:
          EmployeeTypeExtension.fromString(json['employeeType'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'totalHours': totalHours,
      'standardHours': standardHours,
      'baseSalary': baseSalary,
      'calculatedSalary': calculatedSalary,
      'employeeType': employeeType.value,
    };
  }

  UserSalaryRecord copyWith({
    String? userId,
    String? name,
    double? totalHours,
    double? standardHours,
    double? baseSalary,
    double? calculatedSalary,
    EmployeeType? employeeType,
  }) {
    return UserSalaryRecord(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      totalHours: totalHours ?? this.totalHours,
      standardHours: standardHours ?? this.standardHours,
      baseSalary: baseSalary ?? this.baseSalary,
      calculatedSalary: calculatedSalary ?? this.calculatedSalary,
      employeeType: employeeType ?? this.employeeType,
    );
  }

  double get attendanceRate {
    if (standardHours <= 0) return 0;
    return (totalHours / standardHours).clamp(0.0, double.infinity);
  }

  bool get isFulltime => employeeType == EmployeeType.fulltime;
  bool get isParttime => employeeType == EmployeeType.parttime;

  @override
  String toString() =>
      'UserSalaryRecord(userId: $userId, name: $name, totalHours: $totalHours, '
      'calculatedSalary: $calculatedSalary)';
}

class SalaryRecordModel extends Equatable {
  final String id;
  final String storeId;
  final String month; // YYYY-MM
  final Map<String, UserSalaryRecord> records; // userId → UserSalaryRecord
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SalaryRecordModel({
    required this.id,
    required this.storeId,
    required this.month,
    required this.records,
    this.createdAt,
    this.updatedAt,
  });

  factory SalaryRecordModel.fromJson(Map<String, dynamic> json, String id) {
    final recordsData = json['records'] as Map<String, dynamic>? ?? {};
    final parsedRecords = <String, UserSalaryRecord>{};
    for (final entry in recordsData.entries) {
      if (entry.value is Map<String, dynamic>) {
        parsedRecords[entry.key] = UserSalaryRecord.fromJson(
          entry.value as Map<String, dynamic>,
          entry.key,
        );
      }
    }

    DateTime? parseOptionalTs(dynamic value) {
      if (value is Timestamp) return value.toDate().toUtc();
      if (value is String) return DateTime.tryParse(value)?.toUtc();
      return null;
    }

    return SalaryRecordModel(
      id: id,
      storeId: json['storeId'] as String? ?? '',
      month: json['month'] as String? ?? '',
      records: parsedRecords,
      createdAt: parseOptionalTs(json['createdAt']),
      updatedAt: parseOptionalTs(json['updatedAt']),
    );
  }

  factory SalaryRecordModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SalaryRecordModel.fromJson(data, doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'storeId': storeId,
      'month': month,
      'records': records.map((k, v) => MapEntry(k, v.toJson())),
      'createdAt':
          createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  SalaryRecordModel copyWith({
    String? id,
    String? storeId,
    String? month,
    Map<String, UserSalaryRecord>? records,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SalaryRecordModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      month: month ?? this.month,
      records: records ?? Map.from(this.records),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double get totalSalaryPayout {
    return records.values
        .fold(0.0, (sum, r) => sum + r.calculatedSalary);
  }

  int get totalMembersCount => records.length;

  List<UserSalaryRecord> get sortedByName {
    final list = records.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  List<Object?> get props => [id, storeId, month, records, createdAt, updatedAt];

  @override
  String toString() =>
      'SalaryRecordModel(id: $id, storeId: $storeId, month: $month, members: ${records.length})';
}
