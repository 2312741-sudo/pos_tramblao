import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum AdvanceStatus { pending, approved, rejected }

extension AdvanceStatusExtension on AdvanceStatus {
  static AdvanceStatus fromString(String? value) {
    switch (value) {
      case 'approved':
        return AdvanceStatus.approved;
      case 'rejected':
        return AdvanceStatus.rejected;
      default:
        return AdvanceStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case AdvanceStatus.pending:
        return 'Chờ duyệt';
      case AdvanceStatus.approved:
        return 'Đã duyệt';
      case AdvanceStatus.rejected:
        return 'Từ chối';
    }
  }
}

class AdvanceRequestModel extends Equatable {
  final String id;
  final String storeId;
  final String userId;
  final String month;
  final double amount;
  final AdvanceStatus status;
  final DateTime requestDate;
  final DateTime? approvedDate;
  final String? note;

  const AdvanceRequestModel({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.month,
    required this.amount,
    required this.status,
    required this.requestDate,
    this.approvedDate,
    this.note,
  });

  factory AdvanceRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) throw Exception('Advance data is null');

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return AdvanceRequestModel(
      id: doc.id,
      storeId: data['storeId'] ?? '',
      userId: data['userId'] ?? '',
      month: data['month'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      status: AdvanceStatusExtension.fromString(data['status'] as String?),
      requestDate: parseDate(data['requestDate']),
      approvedDate: data['approvedDate'] != null ? parseDate(data['approvedDate']) : null,
      note: data['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storeId': storeId,
      'userId': userId,
      'month': month,
      'amount': amount,
      'status': status.name,
      'requestDate': requestDate.toIso8601String(),
      'approvedDate': approvedDate?.toIso8601String(),
      'note': note,
    };
  }

  @override
  List<Object?> get props => [id, storeId, userId, month, amount, status, requestDate, approvedDate, note];
}
