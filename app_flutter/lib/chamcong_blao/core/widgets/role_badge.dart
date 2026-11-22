import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../../models/member_model.dart';

class RoleBadge extends StatelessWidget {
  final UserRole role;
  final bool compact;

  const RoleBadge({
    super.key,
    required this.role,
    this.compact = false,
  });

  Color get _backgroundColor {
    switch (role) {
      case UserRole.owner:
        return AppColors.ownerBadge;
      case UserRole.manager1:
        return AppColors.managerBadge;
      case UserRole.manager2:
        return AppColors.managerBadge;
      case UserRole.legacyManager:
        return const Color(0xFFE65100);
      case UserRole.employee:
        return AppColors.employeeBadge;
    }
  }

  String get _label {
    switch (role) {
      case UserRole.owner:
        return 'Chủ';
      case UserRole.manager1:
        return 'Quản lý 1';
      case UserRole.manager2:
        return 'Quản lý 2';
      case UserRole.legacyManager:
        return 'Quản lý (Cũ)';
      case UserRole.employee:
        return 'NV';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: AppColors.white,
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
