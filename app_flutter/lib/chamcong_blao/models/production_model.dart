import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum ProductionUnitType { time, kg, shift, qty }

extension ProductionUnitTypeExtension on ProductionUnitType {
  String get value {
    switch (this) {
      case ProductionUnitType.time:
        return 'time';
      case ProductionUnitType.kg:
        return 'kg';
      case ProductionUnitType.shift:
        return 'shift';
      case ProductionUnitType.qty:
        return 'qty';
    }
  }

  static ProductionUnitType fromString(String val) {
    switch (val) {
      case 'time':
        return ProductionUnitType.time;
      case 'kg':
        return ProductionUnitType.kg;
      case 'shift':
        return ProductionUnitType.shift;
      case 'qty':
        return ProductionUnitType.qty;
      default:
        return ProductionUnitType.qty;
    }
  }
}

class ProductionTask extends Equatable {
  final String id;
  final String name;
  final ProductionUnitType unit;
  final String unitLabel;
  final bool active;
  final int order;
  final DateTime? createdAt;

  const ProductionTask({
    required this.id,
    required this.name,
    required this.unit,
    required this.unitLabel,
    required this.active,
    required this.order,
    this.createdAt,
  });

  factory ProductionTask.fromJson(Map<String, dynamic> json, String id) {
    return ProductionTask(
      id: id,
      name: json['name'] ?? '',
      unit: ProductionUnitTypeExtension.fromString(json['unit'] ?? 'qty'),
      unitLabel: json['unitLabel'] ?? '',
      active: json['active'] ?? true,
      order: json['order'] ?? 0,
      createdAt: json['createdAt'] != null ? (json['createdAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'unit': unit.value,
      'unitLabel': unitLabel,
      'active': active,
      'order': order,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  @override
  List<Object?> get props => [id, name, unit, unitLabel, active, order, createdAt];
}

class ProductionTaskEntry extends Equatable {
  final String taskId;
  final String taskName;
  final ProductionUnitType unit;
  final String unitLabel;
  final double value;

  const ProductionTaskEntry({
    required this.taskId,
    required this.taskName,
    required this.unit,
    required this.unitLabel,
    required this.value,
  });

  factory ProductionTaskEntry.fromJson(Map<String, dynamic> json) {
    return ProductionTaskEntry(
      taskId: json['taskId'] ?? '',
      taskName: json['taskName'] ?? '',
      unit: ProductionUnitTypeExtension.fromString(json['unit'] ?? 'qty'),
      unitLabel: json['unitLabel'] ?? '',
      value: (json['value'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'taskName': taskName,
      'unit': unit.value,
      'unitLabel': unitLabel,
      'value': value,
    };
  }

  @override
  List<Object?> get props => [taskId, taskName, unit, unitLabel, value];
}

class ProductionReport extends Equatable {
  final String id;
  final String userId;
  final String memberName;
  final String date;
  final String shiftId;
  final String shiftName;
  final DateTime checkoutTime;
  final String note;
  final List<ProductionTaskEntry> tasks;
  final DateTime? createdAt;

  const ProductionReport({
    required this.id,
    required this.userId,
    required this.memberName,
    required this.date,
    required this.shiftId,
    required this.shiftName,
    required this.checkoutTime,
    required this.note,
    required this.tasks,
    this.createdAt,
  });

  factory ProductionReport.fromJson(Map<String, dynamic> json, String id) {
    return ProductionReport(
      id: id,
      userId: json['userId'] ?? '',
      memberName: json['memberName'] ?? '',
      date: json['date'] ?? '',
      shiftId: json['shiftId'] ?? '',
      shiftName: json['shiftName'] ?? '',
      checkoutTime: (json['checkoutTime'] as Timestamp).toDate(),
      note: json['note'] ?? '',
      tasks: (json['tasks'] as List<dynamic>?)
              ?.map((e) => ProductionTaskEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null ? (json['createdAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'memberName': memberName,
      'date': date,
      'shiftId': shiftId,
      'shiftName': shiftName,
      'checkoutTime': Timestamp.fromDate(checkoutTime),
      'note': note,
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        memberName,
        date,
        shiftId,
        shiftName,
        checkoutTime,
        note,
        tasks,
        createdAt,
      ];
}
