import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final DateTime? birthday;
  final String? currentStoreId;
  final List<String> storeIds;
  final bool notifyShiftInOut;
  final DateTime createdAt;

  bool get hasStore => currentStoreId != null && currentStoreId!.isNotEmpty;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.birthday,
    this.currentStoreId,
    this.storeIds = const [],
    this.notifyShiftInOut = true,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, [String? docId]) {
    DateTime? parsedBirthday;
    if (json['birthday'] != null) {
      try {
        if (json['birthday'] is Timestamp) {
          parsedBirthday = (json['birthday'] as Timestamp).toDate().toUtc();
        } else {
          parsedBirthday = DateTime.tryParse(json['birthday'].toString());
        }
      } catch (_) {}
    }

    DateTime parsedCreatedAt;
    try {
      if (json['createdAt'] is Timestamp) {
        parsedCreatedAt = (json['createdAt'] as Timestamp).toDate().toUtc();
      } else if (json['createdAt'] != null) {
        parsedCreatedAt = DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now().toUtc();
      } else {
        parsedCreatedAt = DateTime.now().toUtc();
      }
    } catch (_) {
      parsedCreatedAt = DateTime.now().toUtc();
    }

    return UserModel(
      id: docId ?? json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      avatarUrl: json['avatarUrl'],
      birthday: parsedBirthday,
      currentStoreId: json['currentStoreId'],
      storeIds: List<String>.from(json['storeIds'] ?? []),
      notifyShiftInOut: json['notifyShiftInOut'] as bool? ?? true,
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'avatarUrl': avatarUrl,
      if (birthday != null) 'birthday': birthday!.toIso8601String(),
      'currentStoreId': currentStoreId,
      'storeIds': storeIds,
      'notifyShiftInOut': notifyShiftInOut,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserModel.fromFirestore(dynamic doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel.fromJson(data, doc.id);
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
    DateTime? birthday,
    String? currentStoreId,
    List<String>? storeIds,
    bool? notifyShiftInOut,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      birthday: birthday ?? this.birthday,
      currentStoreId: currentStoreId ?? this.currentStoreId,
      storeIds: storeIds ?? this.storeIds,
      notifyShiftInOut: notifyShiftInOut ?? this.notifyShiftInOut,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        phone,
        avatarUrl,
        birthday,
        currentStoreId,
        storeIds,
        notifyShiftInOut,
        createdAt,
      ];
}
