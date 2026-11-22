import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/attendance_utils.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../models/attendance_model.dart';
import '../../schedule/providers/schedule_provider.dart';
import '../../store/providers/store_provider.dart';
import '../providers/attendance_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ActiveStaffScreen extends ConsumerStatefulWidget {
  const ActiveStaffScreen({super.key});

  @override
  ConsumerState<ActiveStaffScreen> createState() => _ActiveStaffScreenState();
}

class _ActiveStaffScreenState extends ConsumerState<ActiveStaffScreen> {
  late Timer _timer;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Periodic refresh every 30 seconds to keep the worked duration counter fresh
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatDuration(DateTime checkIn) {
    final now = DateTime.now().toUtc();
    final diff = now.difference(checkIn.toUtc());
    if (diff.isNegative) return '0h 00m';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final activeAttendancesAsync = ref.watch(activeAttendancesProvider);
    final membersAsync = ref.watch(storeMembersProvider);
    final storeAsync = ref.watch(currentStoreProvider);
    final weekStart = ref.watch(currentWeekStartProvider);
    final scheduleAsync = ref.watch(weekScheduleProvider(weekStart));

    final store = storeAsync.valueOrNull;
    final schedule = scheduleAsync.valueOrNull;
    final members = membersAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: activeAttendancesAsync.when(
          data: (atts) => Text(
            'Nhân viên đang làm (${atts.length})',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFamily: 'BeVietnamPro',
              fontSize: 17,
              color: Colors.white,
            ),
          ),
          loading: () => const Text(
            'Nhân viên đang làm',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontFamily: 'BeVietnamPro',
              fontSize: 17,
              color: Colors.white,
            ),
          ),
          error: (_, __) => const Text(
            'Nhân viên đang làm',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontFamily: 'BeVietnamPro',
              fontSize: 17,
              color: Colors.white,
            ),
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: activeAttendancesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primary,
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Lỗi tải danh sách: $e',
              style: const TextStyle(color: Colors.red, fontFamily: 'BeVietnamPro'),
            ),
          ),
        ),
        data: (atts) {
          if (atts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.userX,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Hiện không có ai trong ca',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'BeVietnamPro',
                        color: AppColors.neutral,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Chưa có nhân viên nào chấm công vào ca làm việc hiện tại.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontFamily: 'BeVietnamPro',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Filter by search query if any
          final filteredAtts = atts.where((att) {
            if (_searchQuery.trim().isEmpty) return true;
            final member = members.where((m) => m.userId == att.userId).firstOrNull;
            final name = (member?.name ?? att.userId).toLowerCase();
            return name.contains(_searchQuery.trim().toLowerCase());
          }).toList();

          return Column(
            children: [
              // Search header if there are multiple staff
              if (atts.length > 5)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm nhân viên theo tên...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontFamily: 'BeVietnamPro',
                        fontSize: 13.5,
                      ),
                      prefixIcon: Icon(LucideIcons.search, color: Colors.grey.shade500, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),

              // Staff count overview badge
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: Text(
                      'Đang làm việc: ${filteredAtts.length} / ${atts.length} nhân viên',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'BeVietnamPro',
                        color: Color(0xFF555555),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                  ],
                ),
              ),

              // List of active employees
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: filteredAtts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final att = filteredAtts[index];
                    final member = members.where((m) => m.userId == att.userId).firstOrNull;
                    final name = member?.name ?? att.userId;
                    final localCheckIn = att.checkIn.toLocal();
                    final checkInTime = DateFormat('HH:mm').format(localCheckIn);
                    final workedDuration = _formatDuration(att.checkIn);

                    // Late calculation
                    final lateWarning = AttendanceUtils.calculateLateString(
                      checkIn: localCheckIn,
                      userId: att.userId,
                      store: store,
                      schedule: schedule,
                    );

                    // Department resolution
                    final deptId = member?.department;
                    final dept = (deptId != null && store != null)
                        ? store.departments.where((d) => d.id == deptId).firstOrNull
                        : null;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade100),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar with active green dot
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                AvatarWidget(
                                  avatarUrl: member?.avatarUrl,
                                  name: name,
                                  radius: 24,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 13,
                                    height: 13,
                                    decoration: BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),

                            // Employee info & time details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'BeVietnamPro',
                                            fontSize: 14.5,
                                            color: AppColors.neutral,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (dept != null)
                                        Container(
                                          margin: const EdgeInsets.only(left: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            dept.name,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                              fontFamily: 'BeVietnamPro',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),

                                  // Row of check-in time and duration worked
                                  Row(
                                    children: [
                                      Icon(LucideIcons.logIn, size: 14, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Vào lúc: $checkInTime',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'BeVietnamPro',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(LucideIcons.timer, size: 14, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Flexible(child: Text(
                                        'Đã làm: $workedDuration',
                                        style: const TextStyle(
                                          color: AppColors.success,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'BeVietnamPro',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )),
                                    ],
                                  ),

                                  // CheckIn Method & Late badge
                                  if (lateWarning != null || att.checkInMethod != CheckInMethod.wifi) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (lateWarning != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFF3E0),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFFFB74D).withValues(alpha: 0.6),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  LucideIcons.triangleAlert,
                                                  size: 12,
                                                  color: Color(0xFFE65100),
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(child: Text(
                                                  lateWarning,
                                                  style: const TextStyle(
                                                    color: Color(0xFFE65100),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    fontFamily: 'BeVietnamPro',
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                )),
                                              ],
                                            ),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                att.checkInMethod == CheckInMethod.gps
                                                    ? LucideIcons.mapPin
                                                    : LucideIcons.wifi,
                                                size: 12,
                                                color: Colors.grey.shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(child: Text(
                                                att.checkInMethod.label,
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                  fontFamily: 'BeVietnamPro',
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              )),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Đang làm',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'BeVietnamPro',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
