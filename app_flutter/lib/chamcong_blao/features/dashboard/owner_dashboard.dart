import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../app/router.dart';
import '../../core/constants/app_colors.dart';
import '../../models/member_model.dart';
import '../../models/attendance_model.dart';
import '../../features/store/providers/store_provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/providers/auth_notifier.dart';
import '../../features/attendance/providers/attendance_provider.dart';
import '../../core/widgets/store_drawer.dart';
import '../../core/widgets/notification_bell_icon.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../core/utils/attendance_utils.dart';
import '../../features/schedule/providers/schedule_provider.dart';
import '../../features/members/screens/members_list_screen.dart';
import '../../features/attendance/screens/attendance_table_screen.dart';
import '../../features/task_assignment/widgets/shift_tasks_card.dart';
import '../../features/blao_station/widgets/blao_station_card.dart';

import '../../core/services/app_update_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../cc_firebase.dart';

class OwnerDashboard extends ConsumerStatefulWidget {
  const OwnerDashboard({super.key});

  @override
  ConsumerState<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends ConsumerState<OwnerDashboard> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAppVersion(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Proactive role check on build: Never stay on OwnerDashboard if not an owner
    final currentMember = ref.watch(currentMemberProvider);
    if (currentMember != null) {
      if (currentMember.status == MemberStatus.pending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.pendingApproval);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      } else if (currentMember.status == MemberStatus.kicked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.welcome);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      } else if (currentMember.isManager) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.managerDashboard);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      } else if (currentMember.isEmployee) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.employeeDashboard);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      }
    }

    // Reactive role check: If user role changed to Manager or Employee, auto-navigate
    ref.listen<MemberModel?>(currentMemberProvider, (prev, next) {
      if (CcFirebase.auth.currentUser == null || !mounted) return;
      if (next == null) return;
      if (next.status == MemberStatus.pending) {
        context.go(AppRoutes.pendingApproval);
        return;
      }
      if (next.status == MemberStatus.kicked) {
        context.go(AppRoutes.welcome);
        return;
      }
      if (next.isManager) {
        context.go(AppRoutes.managerDashboard);
      } else if (next.isEmployee) {
        context.go(AppRoutes.employeeDashboard);
      }
    });

    return Scaffold(
      drawer: const StoreDrawer(),
      backgroundColor: AppColors.surface,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _OwnerHomeTab(),
          const MembersListScreen(),
          const AttendanceTableScreen(),
          _OwnerSettingsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.checkIn),
        backgroundColor: AppColors.ownerAccent,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(LucideIcons.fingerprint, size: 22),
        label: const Text(
          'Chấm công',
          style: TextStyle(
            fontFamily: 'BeVietnamPro',
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _OwnerNavItem(icon: LucideIcons.house, label: 'Tổng quan', index: 0, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
              _OwnerNavItem(icon: LucideIcons.users, label: 'Nhân viên', index: 1, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
              _OwnerNavItem(icon: LucideIcons.sheet, label: 'Bảng công', index: 2, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
              _OwnerNavItem(icon: LucideIcons.settings, label: 'Cài đặt', index: 3, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── HOME TAB ────────────────────────────────────────────────────────────────

class _OwnerHomeTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final userAsync = ref.watch(currentUserProvider);
    final storeAsync = ref.watch(currentStoreProvider);
    final user = userAsync.valueOrNull;
    final store = storeAsync.valueOrNull;

    if (store == null) {
      if (storeAsync.hasError || userAsync.hasError) {
        final err = storeAsync.error ?? userAsync.error;
        return Scaffold(
          backgroundColor: AppColors.surface,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.triangleAlert, size: 48, color: AppColors.danger),
                  const SizedBox(height: 16),
                  Text(
                    'Không thể tải dữ liệu: $err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontFamily: 'BeVietnamPro'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      ref.invalidate(currentUserProvider);
                      ref.invalidate(currentStoreProvider);
                      ref.invalidate(userStoresProvider);
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final membersAsync = ref.watch(storeMembersProvider);
    final pendingAsync = ref.watch(pendingMembersProvider);
    final attendancesAsync = ref.watch(allTodayAttendancesProvider);
    final activeAttendancesAsync = ref.watch(activeAttendancesProvider);
    final ownerAttendanceAsync = ref.watch(todayAttendanceProvider);

    final weekStart = ref.watch(currentWeekStartProvider);
    final scheduleAsync = ref.watch(weekScheduleProvider(weekStart));
    final schedule = scheduleAsync.valueOrNull;

    final activeCount = membersAsync.valueOrNull?.where((m) => m.isActive).length ?? 0;
    final pendingCount = pendingAsync.valueOrNull?.where((m) => m.isActive && m.status == MemberStatus.pending).length ?? (pendingAsync.valueOrNull?.length ?? 0);
    final unclassifiedManagers = membersAsync.valueOrNull?.where((m) => m.isActive && m.isLegacyManager).toList() ?? [];
    final workingNow = activeAttendancesAsync.valueOrNull?.length ?? 0;
    final doneToday = attendancesAsync.valueOrNull?.where((a) => a.checkOut != null).length ?? 0;
    final now = DateTime.now();
    final firstName = (user?.name ?? 'Chủ').split(' ').last;

    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.ownerAccent, AppColors.ownerAccentDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_getGreeting(now.hour)}, $firstName',
                            style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'BeVietnamPro'),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => Scaffold.of(context).openDrawer(),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    store.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'BeVietnamPro'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(LucideIcons.chevronDown, color: Colors.white, size: 24),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              border: Border.all(color: Colors.white54),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.award, color: AppColors.accent, size: 15),
                                SizedBox(width: 6),
                                Text('CHỦ CỬA HÀNG', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, fontFamily: 'BeVietnamPro')),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            DateFormat('EEEE, dd/MM/yyyy', 'vi').format(now),
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'BeVietnamPro'),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const NotificationBellIcon(
                          iconColor: Colors.white,
                          backgroundColor: Color(0x26FFFFFF),
                        ),
                        const SizedBox(width: 8),
                        // Store code badge - store is guaranteed non-null here
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              const Text('Mã cửa hàng', style: TextStyle(color: AppColors.ownerAccent, fontSize: 10, fontFamily: 'BeVietnamPro')),
                              Text(store.code, style: const TextStyle(color: AppColors.ownerAccent, fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'BeVietnamPro', letterSpacing: 2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Owner's Personal Check-in Status Card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ownerAttendanceAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (att) => _OwnerPersonalAttendanceCard(
                attendance: att,
                userId: userId,
              ),
            ),
          ),
        ),

        // Banner: Phân loại Quản lý cũ (Migration Banner)
        if (unclassifiedManagers.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF57F17).withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.triangleAlert, color: Color(0xFFE65100), size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cần phân loại Quản lý (${unclassifiedManagers.length})',
                          style: GoogleFonts.beVietnamPro(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: const Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Có ${unclassifiedManagers.length} tài khoản Quản lý cũ cần được phân loại lại thành Quản lý 1 hoặc Quản lý 2. Hiện tại họ đang tạm giữ toàn quyền.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12.5,
                      color: const Color(0xFF5D4037),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        context.push(AppRoutes.members);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65100),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        'Phân loại ngay',
                        style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Stats grid
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hôm nay', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro', color: AppColors.neutral)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _StatCard(value: workingNow.toString(), label: 'Đang làm', icon: LucideIcons.briefcase, color: AppColors.success)),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard(value: doneToday.toString(), label: 'Đã ra ca', icon: LucideIcons.circleCheck, color: AppColors.info)),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard(value: activeCount.toString(), label: 'Tổng NV', icon: LucideIcons.users, color: AppColors.primaryDark)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: pendingCount > 0 ? () => GoRouter.of(context).push(AppRoutes.pendingMembers) : null,
                        child: _StatCard(value: pendingCount.toString(), label: 'Chờ duyệt', icon: LucideIcons.circleEllipsis, color: AppColors.primary, highlight: pendingCount > 0),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Live list — NV đang làm
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        workingNow > 0 ? 'Đang làm việc ($workingNow)' : 'Đang làm việc',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro', color: AppColors.neutral),
                      ),
                    ),
                    TextButton(
                      onPressed: () => GoRouter.of(context).push(AppRoutes.activeStaff),
                      child: const Text('Xem tất cả', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontFamily: 'BeVietnamPro')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                activeAttendancesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (atts) {
                    final working = atts.take(8).toList();
                    if (working.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: const Center(child: Text('Chưa có ai chấm vào ca', style: TextStyle(color: Colors.grey, fontFamily: 'BeVietnamPro'))),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                      child: Column(
                        children: working.asMap().entries.map((entry) {
                          final att = entry.value;
                          final members = ref.watch(storeMembersProvider).valueOrNull ?? [];
                          final member = members.where((m) => m.userId == att.userId).firstOrNull;
                          final name = member?.name ?? att.userId;
                          final localCheckIn = att.checkIn.toLocal();
                          final checkInTime = '${localCheckIn.hour.toString().padLeft(2,'0')}:${localCheckIn.minute.toString().padLeft(2,'0')}';
                          final lateWarning = AttendanceUtils.calculateLateString(
                            checkIn: localCheckIn,
                            userId: att.userId,
                            store: store,
                            schedule: schedule,
                          );
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              leading: AvatarWidget(
                                avatarUrl: member?.avatarUrl,
                                name: name,
                                radius: 20,
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'BeVietnamPro', fontSize: 14)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Text('Vào ca: $checkInTime', style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'BeVietnamPro')),
                                    if (lateWarning != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3E0),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 0.8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(LucideIcons.triangleAlert, size: 11, color: Color(0xFFE65100)),
                                            const SizedBox(width: 3),
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
                                  ],
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Text('Đang làm', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro')),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // Công việc trong ca của Chủ
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ShiftTasksCard(
              storeId: store.id,
              userId: userId,
            ),
          ),
        ),

        // Trạm BLAO Station SOP & Timers Card
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: BlaoStationCard(),
          ),
        ),


        // Quick tools
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Công cụ quản lý', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro', color: AppColors.neutral)),
                const SizedBox(height: 12),
                _ToolCard(icon: LucideIcons.fingerprint, label: 'Chấm công của tôi', sub: 'Chấm vào/ra ca nhanh', color: AppColors.primary, onTap: () => GoRouter.of(context).push(AppRoutes.checkIn)),
                const SizedBox(height: 10),
                _ToolCard(icon: LucideIcons.calendarDays, label: 'Quản lý lịch làm', sub: 'Xem & chỉnh lịch toàn bộ NV', color: AppColors.info, onTap: () => GoRouter.of(context).push(AppRoutes.scheduleManager)),
                const SizedBox(height: 10),
                _ToolCard(icon: LucideIcons.banknote, label: 'Báo cáo lương', sub: 'Tổng hợp lương tháng', color: AppColors.success, onTap: () => GoRouter.of(context).push(AppRoutes.salaryOverview)),
                const SizedBox(height: 10),
                _ToolCard(icon: LucideIcons.wallet, label: 'Duyệt tạm ứng', sub: 'Xem yêu cầu ứng lương', color: AppColors.accentInk, onTap: () => GoRouter.of(context).push(AppRoutes.manageAdvances)),
                const SizedBox(height: 10),
                _ToolCard(icon: LucideIcons.qrCode, label: 'QR chấm công', sub: 'Chia sẻ mã QR cho NV', color: AppColors.primaryDark, onTap: () => GoRouter.of(context).push(AppRoutes.qrDisplay)),
                const SizedBox(height: 10),
                _ToolCard(icon: LucideIcons.clipboardList, label: 'Giao việc & Quản lý việc', sub: 'Phân công công việc & theo dõi báo cáo NV', color: AppColors.managerAccent, onTap: () => GoRouter.of(context).push(AppRoutes.taskManagement)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getGreeting(int hour) {
    if (hour < 12) return 'Chào buổi sáng';
    if (hour < 18) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }
}


// ─── SETTINGS TAB ─────────────────────────────────────────────────────────────

class _OwnerSettingsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final storeAsync = ref.watch(currentStoreProvider);
    final user = userAsync.valueOrNull;
    final store = storeAsync.valueOrNull;

    if (store == null) {
      if (storeAsync.hasError || userAsync.hasError) {
        final err = storeAsync.error ?? userAsync.error;
        return Scaffold(
          backgroundColor: AppColors.surface,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.triangleAlert, size: 48, color: AppColors.danger),
                  const SizedBox(height: 16),
                  Text(
                    'Không thể tải dữ liệu: $err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontFamily: 'BeVietnamPro'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      ref.invalidate(currentUserProvider);
                      ref.invalidate(currentStoreProvider);
                      ref.invalidate(userStoresProvider);
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Cài đặt', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro')),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.neutral,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Owner Profile Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)]),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.ownerTint,
                  backgroundImage: getAvatarImageProvider(user?.avatarUrl),
                  child: (getAvatarImageProvider(user?.avatarUrl) == null)
                      ? Text((user?.name.isNotEmpty == true) ? user!.name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.ownerAccent, fontSize: 24, fontWeight: FontWeight.w800, fontFamily: 'BeVietnamPro'))
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? 'Chủ quán', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'BeVietnamPro', color: AppColors.neutral)),
                      const SizedBox(height: 4),
                      Text(user?.email ?? '', style: const TextStyle(fontSize: 13, color: Colors.grey, fontFamily: 'BeVietnamPro')),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.ownerTint, borderRadius: BorderRadius.circular(6)),
                        child: const Text('Chủ cửa hàng', style: TextStyle(color: AppColors.ownerAccent, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _SettingsSection(title: 'Chấm công & Cá nhân', items: [
            _SettingsItem(
              icon: LucideIcons.fingerprint,
              label: 'Chấm công',
              sub: 'Chấm vào ca / ra ca (WiFi, GPS, QR)',
              color: AppColors.primary,
              onTap: () => GoRouter.of(context).push(AppRoutes.checkIn),
            ),
            _SettingsItem(
              icon: LucideIcons.history,
              label: 'Lịch sử chấm công của tôi',
              sub: 'Xem chi tiết ngày công và giờ vào/ra',
              color: AppColors.info,
              onTap: () => GoRouter.of(context).push(
                Uri(path: AppRoutes.attendanceHistory, queryParameters: {'userId': user?.id}).toString(),
              ),
            ),
            _SettingsItem(
              icon: LucideIcons.calendarDays,
              label: 'Lịch làm việc & Đăng ký ca',
              sub: 'Xem và đăng ký ca làm cá nhân',
              color: AppColors.success,
              onTap: () => GoRouter.of(context).push(AppRoutes.scheduleRegister),
            ),
            _SettingsItem(
              icon: LucideIcons.banknote,
              label: 'Bảng lương của tôi',
              sub: 'Xem lương và tạm ứng cá nhân',
              color: AppColors.accentInk,
              onTap: () => GoRouter.of(context).push(AppRoutes.salary),
            ),
          ]),
          const SizedBox(height: 12),

          _SettingsSection(title: 'Cửa hàng', items: [
            _SettingsItem(icon: LucideIcons.store, label: 'Cài đặt cửa hàng', sub: store.name, onTap: () => GoRouter.of(context).push(AppRoutes.storeSettings)),
            _SettingsItem(icon: LucideIcons.clock, label: 'Quản lý ca làm', onTap: () => GoRouter.of(context).push(AppRoutes.shiftSettings)),
            _SettingsItem(icon: LucideIcons.qrCode, label: 'Mã QR cửa hàng', onTap: () => GoRouter.of(context).push(AppRoutes.qrDisplay)),
          ]),
          const SizedBox(height: 12),
          _SettingsSection(title: 'Tài khoản', items: [
            _SettingsItem(icon: LucideIcons.user, label: 'Hồ sơ cá nhân', onTap: () => GoRouter.of(context).push(AppRoutes.profileSettings)),
            _SettingsItem(icon: LucideIcons.logOut, label: 'Đăng xuất', color: Colors.red, onTap: () async {
              final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                title: const Text('Đăng xuất?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đăng xuất', style: TextStyle(color: Colors.red))),
                ],
              ));
              if (confirm == true) {
                await ref.read(authNotifierProvider.notifier).signOut();
                if (context.mounted) {
                  context.go(AppRoutes.login);
                }
              }
            }),
          ]),
        ],
      ),
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final bool highlight;

  const _StatCard({required this.value, required this.label, required this.icon, required this.color, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? color.withOpacity(0.08) : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight ? color : AppColors.cardOutline, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, fontFamily: 'BeVietnamPro')),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'BeVietnamPro'), textAlign: TextAlign.center, maxLines: 2),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final Color color;
  final VoidCallback onTap;

  const _ToolCard({required this.icon, required this.label, this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardOutline, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro', fontSize: 14)),
                  if (sub != null) Text(sub!, style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'BeVietnamPro')),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsItem> items;

  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey, fontFamily: 'BeVietnamPro')),
        ),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
          child: Column(
            children: items.asMap().entries.map((e) {
              final item = e.value;
              final isLast = e.key == items.length - 1;
              return Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      onTap: item.onTap,
                      leading: Icon(item.icon, color: item.color ?? AppColors.neutral, size: 22),
                      title: Text(item.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'BeVietnamPro', color: item.color ?? AppColors.neutral)),
                      subtitle: item.sub != null ? Text(item.sub!, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'BeVietnamPro')) : null,
                      trailing: const Icon(LucideIcons.chevronRight, color: Colors.grey),
                    ),
                  ),
                  if (!isLast) const Divider(height: 1, indent: 56),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsItem {
  final IconData icon;
  final String label;
  final String? sub;
  final Color? color;
  final VoidCallback onTap;

  const _SettingsItem({required this.icon, required this.label, this.sub, this.color, required this.onTap});
}

class _OwnerNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int selected;
  final Function(int) onTap;

  const _OwnerNavItem({required this.icon, required this.label, required this.index, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = index == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.ownerTint : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? AppColors.ownerAccent : AppColors.textSecondary, size: 22),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? AppColors.ownerAccent : AppColors.textSecondary, fontFamily: 'BeVietnamPro')),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerPersonalAttendanceCard extends StatelessWidget {
  final AttendanceModel? attendance;
  final String userId;

  const _OwnerPersonalAttendanceCard({
    required this.attendance,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = attendance != null && attendance!.isActive;
    final isDone = attendance != null && !attendance!.isActive;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.success.withOpacity(0.12)
                      : isDone
                          ? AppColors.info.withOpacity(0.12)
                          : AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive
                      ? LucideIcons.timer
                      : isDone
                          ? LucideIcons.circleCheck
                          : LucideIcons.fingerprint,
                  color: isActive
                      ? AppColors.success
                      : isDone
                          ? AppColors.info
                          : AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive
                          ? 'Đang trong ca làm việc'
                          : isDone
                              ? 'Đã hoàn thành ca hôm nay'
                              : 'Chưa chấm công hôm nay',
                      style: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.neutral,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'Vào ca lúc ${DateFormat('HH:mm').format(attendance!.checkIn.toLocal())}'
                          : isDone && attendance?.checkOut != null
                              ? 'Tổng: ${(attendance!.totalHours ?? 0).toStringAsFixed(1)}h (${DateFormat('HH:mm').format(attendance!.checkIn.toLocal())} - ${DateFormat('HH:mm').format(attendance!.checkOut!.toLocal())})'
                              : 'Chạm để chấm vào ca làm việc',
                      style: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.checkIn),
                icon: Icon(
                  isActive ? LucideIcons.logOut : LucideIcons.fingerprint,
                  size: 16,
                ),
                label: Text(
                  isActive ? 'Ra ca' : 'Chấm công',
                  style: const TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive
                      ? AppColors.success
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PersonalQuickLink(
                icon: LucideIcons.history,
                label: 'Lịch sử công',
                onTap: () => context.push(
                  Uri(
                    path: AppRoutes.attendanceHistory,
                    queryParameters: {'userId': userId},
                  ).toString(),
                ),
              ),
              _PersonalQuickLink(
                icon: LucideIcons.calendarDays,
                label: 'Lịch cá nhân',
                onTap: () => context.push(AppRoutes.scheduleRegister),
              ),
              _PersonalQuickLink(
                icon: LucideIcons.banknote,
                label: 'Lương cá nhân',
                onTap: () => context.push(AppRoutes.salary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonalQuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PersonalQuickLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.info),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.info,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
