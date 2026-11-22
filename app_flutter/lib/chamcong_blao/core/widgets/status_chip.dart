import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum AttendanceStatus { working, notStarted, finished, pending, absent }

class StatusChip extends StatelessWidget {
  final AttendanceStatus status;
  final bool compact;

  const StatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  factory StatusChip.fromString(String? status, {bool compact = false}) {
    final s = _parseStatus(status);
    return StatusChip(status: s, compact: compact);
  }

  static AttendanceStatus _parseStatus(String? value) {
    switch (value) {
      case 'working':
        return AttendanceStatus.working;
      case 'notStarted':
        return AttendanceStatus.notStarted;
      case 'finished':
        return AttendanceStatus.finished;
      case 'pending':
        return AttendanceStatus.pending;
      case 'absent':
        return AttendanceStatus.absent;
      default:
        return AttendanceStatus.notStarted;
    }
  }

  Color get _backgroundColor {
    switch (status) {
      case AttendanceStatus.working:
        return AppColors.success;
      case AttendanceStatus.notStarted:
        return AppColors.primary;
      case AttendanceStatus.finished:
        return AppColors.checkOut;
      case AttendanceStatus.pending:
        return AppColors.accent;
      case AttendanceStatus.absent:
        return AppColors.textDisabled;
    }
  }

  Color get _textColor {
    switch (status) {
      case AttendanceStatus.pending:
        return AppColors.neutral;
      default:
        return AppColors.white;
    }
  }

  String get _label {
    switch (status) {
      case AttendanceStatus.working:
        return 'Đang làm việc';
      case AttendanceStatus.notStarted:
        return 'Chưa vào ca';
      case AttendanceStatus.finished:
        return 'Đã kết thúc';
      case AttendanceStatus.pending:
        return 'Chờ duyệt';
      case AttendanceStatus.absent:
        return 'Vắng mặt';
    }
  }

  IconData get _icon {
    switch (status) {
      case AttendanceStatus.working:
        return LucideIcons.briefcase;
      case AttendanceStatus.notStarted:
        return LucideIcons.clock;
      case AttendanceStatus.finished:
        return LucideIcons.circleCheck;
      case AttendanceStatus.pending:
        return LucideIcons.hourglass;
      case AttendanceStatus.absent:
        return LucideIcons.circleX;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icon,
            size: compact ? 10 : 12,
            color: _textColor,
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            style: TextStyle(
              color: _textColor,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
