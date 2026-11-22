import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/member_model.dart';

/// Keeps the schedule header, controls and cards in the same role palette.
class SchedulePalette {
  const SchedulePalette({
    required this.accent,
    required this.surface,
    required this.outline,
    this.onAccent = Colors.white,
  });

  final Color accent;
  final Color surface;
  final Color outline;
  final Color onAccent;

  static SchedulePalette forRole(UserRole? role) {
    if (role?.isOwner == true) {
      return const SchedulePalette(
        accent: AppColors.ownerAccent,
        surface: Color(0xFFF7F7F5),
        outline: Color(0xFFD7D7D2),
        onAccent: Colors.white,
      );
    }
    if (role?.isManager == true) {
      return const SchedulePalette(
        accent: AppColors.managerAccent,
        surface: Color(0xFFF7FAFE),
        outline: Color(0xFFD4E3F2),
        onAccent: Colors.white,
      );
    }
    return const SchedulePalette(
      accent: AppColors.primary,
      surface: AppColors.surface,
      outline: AppColors.border,
      onAccent: Color(0xFF143A2F),
    );
  }
}
