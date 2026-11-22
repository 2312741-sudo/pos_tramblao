import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/router.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/constants/app_colors.dart';
import '../../models/member_model.dart';
import '../../models/store_model.dart';
import '../../features/store/providers/store_provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/providers/auth_notifier.dart';
import '../../core/widgets/store_drawer.dart';
import '../../core/widgets/notification_bell_icon.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../core/utils/attendance_utils.dart';
import '../../features/attendance/providers/attendance_provider.dart';
import '../../features/schedule/providers/schedule_provider.dart';
import '../../features/schedule/screens/employee_schedule_tab.dart';
import '../task_assignment/widgets/shift_tasks_card.dart';
import '../blao_station/widgets/blao_station_card.dart';

import '../../core/services/app_update_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../cc_firebase.dart';

class ManagerDashboard extends ConsumerStatefulWidget {
  const ManagerDashboard({super.key});

  @override
  ConsumerState<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends ConsumerState<ManagerDashboard> {
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
    ref.watch(shiftReminderSchedulerProvider);
    final uid = ref.watch(currentUserProvider).value?.id;

    // Proactive role check on build: Never stay on ManagerDashboard if Owner or Employee
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
      } else if (currentMember.isOwner) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.ownerDashboard);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      } else if (currentMember.isEmployee) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.employeeDashboard);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      }
    }

    // Reactive role check: If user role changed to Owner or Employee, auto-navigate
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
      if (next.isOwner) {
        context.go(AppRoutes.ownerDashboard);
      } else if (next.isEmployee) {
        context.go(AppRoutes.employeeDashboard);
      }
    });

    // Kick out if removed
    ref.listen(storeMembersProvider, (prev, next) {
      if (CcFirebase.auth.currentUser == null) return;
      if (uid == null) return;
      final prevList = prev?.valueOrNull;
      final nextList = next.valueOrNull;
      if (prevList != null && prevList.any((m) => m.userId == uid)) {
        if (nextList != null && !nextList.any((m) => m.userId == uid)) {
          ref.invalidate(userStoresProvider);
          ref.invalidate(currentUserProvider);
          context.go(AppRoutes.splash);
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: const StoreDrawer(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _ManagerHomeTab(uid: uid ?? ''),
          const EmployeeScheduleTab(),
          _ManagerProfileTab(uid: uid ?? ''),
        ],
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
              _MgrNavItem(icon: LucideIcons.house, label: 'Tổng quan', index: 0, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
              _MgrNavItem(icon: LucideIcons.calendarDays, label: 'Lịch làm', index: 1, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
              _MgrNavItem(icon: LucideIcons.user, label: 'Hồ sơ', index: 2, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── HOME TAB ────────────────────────────────────────────────────────────────

class _ManagerHomeTab extends ConsumerWidget {
  final String uid;
  const _ManagerHomeTab({required this.uid});

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

    final currentMember = ref.watch(currentMemberProvider);
    final role = currentMember?.role;
    final canApproveMembers = AppPermissions.canApproveMembers(role);
    final canManageSchedule = AppPermissions.canManageSchedule(role);
    final canViewAllAttendance = AppPermissions.canViewAllAttendance(role);

    final membersAsync = ref.watch(storeMembersProvider);
    final pendingAsync = ref.watch(pendingMembersProvider);
    final attendancesAsync = ref.watch(allTodayAttendancesProvider);
    final activeAttendancesAsync = ref.watch(activeAttendancesProvider);
    final weekStart = ref.watch(currentWeekStartProvider);
    final scheduleAsync = ref.watch(weekScheduleProvider(weekStart));
    final schedule = scheduleAsync.valueOrNull;
    final now = DateTime.now();

    final activeCount = membersAsync.valueOrNull?.where((m) => m.isActive).length ?? 0;
    final pendingCount = pendingAsync.valueOrNull?.length ?? 0;
    final workingNow = activeAttendancesAsync.valueOrNull?.length ?? 0;
    final doneToday = attendancesAsync.valueOrNull?.where((a) => a.checkOut != null).length ?? 0;
    final firstName = (user?.name ?? 'Quản lý').split(' ').last;
    final roleTitle = role?.label ?? 'Quản lý';

    return CustomScrollView(
      slivers: [
        // Manager identity uses a bright blue distinct from the owner's black.
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.managerAccent, AppColors.managerAccentDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_getGreeting(now.hour)}, $firstName', style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'BeVietnamPro')),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(LucideIcons.userCog, color: Colors.white, size: 22),
                                  const SizedBox(width: 6),
                                  Flexible(child: Text(roleTitle, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'BeVietnamPro'))),
                                ],
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
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(DateFormat('EEEE, dd/MM/yyyy', 'vi').format(now), style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'BeVietnamPro')),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          border: Border.all(color: Colors.white54),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.store, color: Colors.white, size: 17),
                            const SizedBox(width: 8),
                            Expanded(child: Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro'))),
                            const Icon(LucideIcons.chevronDown, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Chấm công nhanh cho manager
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: GestureDetector(
              onTap: () => context.push(AppRoutes.checkIn),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.managerAccent, AppColors.managerAccentDark]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppColors.managerAccent.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.fingerprint, color: Colors.white, size: 36),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chấm công của tôi', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'BeVietnamPro')),
                          Text('Nhấn để vào/ra ca', style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'BeVietnamPro')),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Trạm BLAO Station SOP & Timers Card
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: BlaoStationCard(),
          ),
        ),

        // Stats Row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(child: _MgrStatCard(value: workingNow.toString(), label: 'Đang làm', icon: LucideIcons.briefcase, color: AppColors.success)),
                const SizedBox(width: 10),
                Expanded(child: _MgrStatCard(value: doneToday.toString(), label: 'Đã ra ca', icon: LucideIcons.circleCheck, color: AppColors.managerAccent)),
                const SizedBox(width: 10),
                Expanded(child: _MgrStatCard(value: activeCount.toString(), label: 'Tổng NV', icon: LucideIcons.users, color: AppColors.managerAccent)),
                if (canApproveMembers) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MgrStatCard(
                      value: pendingCount.toString(),
                      label: 'Chờ duyệt',
                      icon: LucideIcons.circleEllipsis,
                      color: AppColors.primary,
                      highlight: pendingCount > 0,
                      onTap: () => context.push(AppRoutes.pendingMembers),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Ca làm hôm nay của Quản lý
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _TodayScheduleCard(uid: uid),
          ),
        ),

        // Công việc trong ca của Quản lý
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ShiftTasksCard(
              storeId: store.id,
              userId: uid,
            ),
          ),
        ),


        // NV đang làm
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
                        workingNow > 0 ? 'Nhân viên đang làm ($workingNow)' : 'Nhân viên đang làm',
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
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.managerAccent)),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (atts) {
                    final working = atts.take(8).toList();
                    if (working.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: const Center(child: Text('Chưa có ai vào ca', style: TextStyle(color: Colors.grey, fontFamily: 'BeVietnamPro'))),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                      child: Column(
                        children: working.map((att) {
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
                                    Text('Vào: $checkInTime', style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'BeVietnamPro')),
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

        // Tools
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Công cụ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro', color: AppColors.neutral)),
                const SizedBox(height: 12),
                if (canApproveMembers) ...[
                  _MgrToolCard(
                    icon: LucideIcons.userPlus,
                    label: 'Duyệt thành viên mới',
                    sub: pendingCount > 0 ? '$pendingCount yêu cầu chờ duyệt' : 'Duyệt nhân viên mới xin vào',
                    color: AppColors.managerAccent,
                    onTap: () => context.push(AppRoutes.pendingMembers),
                  ),
                  const SizedBox(height: 10),
                ],
                _MgrToolCard(
                  icon: LucideIcons.shieldUser,
                  label: canManageSchedule ? 'Quản lý lịch làm' : 'Xem lịch làm việc',
                  sub: canManageSchedule ? 'Xếp và duyệt lịch làm việc của nhân viên' : 'Xem lịch toàn bộ NV & tick phụ cấp',
                  color: AppColors.managerAccent,
                  onTap: () => context.push(AppRoutes.scheduleManager),
                ),
                if (canViewAllAttendance) ...[
                  const SizedBox(height: 10),
                  _MgrToolCard(
                    icon: LucideIcons.sheet,
                    label: 'Bảng chấm công',
                    sub: 'Xem bảng công hôm nay',
                    color: AppColors.success,
                    onTap: () => context.push(AppRoutes.attendanceTable),
                  ),
                ],
                const SizedBox(height: 10),
                _MgrToolCard(
                  icon: LucideIcons.clipboardList,
                  label: 'Giao việc & Quản lý việc',
                  sub: 'Phân công công việc & theo dõi báo cáo NV',
                  color: AppColors.info,
                  onTap: () => context.push(AppRoutes.taskManagement),
                ),
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

// ─── PROFILE TAB ─────────────────────────────────────────────────────────────

class _ManagerProfileTab extends ConsumerWidget {
  final String uid;
  const _ManagerProfileTab({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final member = ref.watch(currentMemberProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.managerTint,
                  backgroundImage: getAvatarImageProvider(user?.avatarUrl),
                  child: (getAvatarImageProvider(user?.avatarUrl) == null)
                      ? Text(
                          user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'QL',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.managerAccent, fontFamily: 'BeVietnamPro'),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? 'Quản lý', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro')),
                      const SizedBox(height: 4),
                      Text(user?.email ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'BeVietnamPro')),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.managerTint,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          member?.role.label ?? 'Quản lý',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.managerAccent, fontFamily: 'BeVietnamPro'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ProfileMenuItem(icon: LucideIcons.user, label: 'Chỉnh sửa hồ sơ cá nhân', onTap: () => context.push(AppRoutes.profileSettings)),
          const SizedBox(height: 10),
          _ProfileMenuItem(icon: LucideIcons.banknote, label: 'Lương & Tiền công của tôi', onTap: () => context.push(AppRoutes.salary)),
          const SizedBox(height: 10),
          _ProfileMenuItem(icon: LucideIcons.history, label: 'Lịch sử chấm công của tôi', onTap: () => context.push(AppRoutes.attendanceHistory)),
          const SizedBox(height: 10),
          _ProfileMenuItem(icon: LucideIcons.store, label: 'Đổi cửa hàng', onTap: () => Scaffold.of(context).openDrawer()),
          const SizedBox(height: 10),
          _ProfileMenuItem(icon: LucideIcons.logOut, label: 'Đăng xuất', color: AppColors.primary, onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Đăng xuất?', style: TextStyle(fontFamily: 'BeVietnamPro')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đăng xuất', style: TextStyle(color: Colors.red))),
                ],
              ),
            );
            if (confirm == true) {
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) {
                context.go(AppRoutes.login);
              }
            }
          }),
        ],
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ProfileMenuItem({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
        child: Row(
          children: [
            Icon(icon, color: color ?? AppColors.neutral, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'BeVietnamPro', color: color ?? AppColors.neutral))),
            Icon(LucideIcons.chevronRight, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────

class _MgrStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final bool highlight;
  final VoidCallback? onTap;

  const _MgrStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: highlight ? color.withOpacity(0.08) : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlight ? color : AppColors.cardOutline, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'BeVietnamPro',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'BeVietnamPro'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MgrToolCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final Color color;
  final VoidCallback onTap;

  const _MgrToolCard({required this.icon, required this.label, this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.cardSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardOutline, width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro', fontSize: 14)),
              if (sub != null) Text(sub!, style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'BeVietnamPro')),
            ])),
            Icon(LucideIcons.chevronRight, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class _MgrNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int selected;
  final Function(int) onTap;

  const _MgrNavItem({required this.icon, required this.label, required this.index, required this.selected, required this.onTap});

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
          decoration: BoxDecoration(color: isSelected ? AppColors.managerTint : Colors.transparent, borderRadius: BorderRadius.circular(14)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? AppColors.managerAccent : AppColors.textSecondary, size: 22),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? AppColors.managerAccent : AppColors.textSecondary, fontFamily: 'BeVietnamPro')),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayScheduleCard extends ConsumerWidget {
  final String uid;
  const _TodayScheduleCard({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(currentWeekScheduleProvider);
    final store = ref.watch(currentStoreProvider).value;
    final member = ref.watch(currentMemberProvider);

    if (store == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.calendarClock, color: AppColors.accentInk, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Ca làm hôm nay của bạn', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro', color: AppColors.neutral)),
            ],
          ),
          const SizedBox(height: 12),
          scheduleAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, __) => const Text('Không tải được lịch', style: TextStyle(color: Colors.grey)),
            data: (schedule) {
              if (schedule == null) return const Text('Không có lịch tuần này', style: TextStyle(color: Colors.grey, fontFamily: 'BeVietnamPro'));
              final daySchedule = schedule.shifts[uid];
              List<String> shiftIds = [];
              if (daySchedule != null) {
                switch (DateTime.now().weekday) {
                  case 1: shiftIds = daySchedule.monday; break;
                  case 2: shiftIds = daySchedule.tuesday; break;
                  case 3: shiftIds = daySchedule.wednesday; break;
                  case 4: shiftIds = daySchedule.thursday; break;
                  case 5: shiftIds = daySchedule.friday; break;
                  case 6: shiftIds = daySchedule.saturday; break;
                  case 7: shiftIds = daySchedule.sunday; break;
                }
              }
              final shifts = store.customShifts
                  .where((s) => shiftIds.any((id) => id.split('|').first == s.id))
                  .toList();
              final hasDelivery = shiftIds.contains('delivery');
              final hasGiaoHang = shiftIds.contains('giaohang');

              if (shifts.isEmpty && !hasDelivery && !hasGiaoHang) {
                return const Text('Hôm nay không có ca làm', style: TextStyle(color: Colors.grey, fontFamily: 'BeVietnamPro'));
              }

              return Column(
                children: [
                  ...shifts.map((shift) {
                    final dept = _getShiftDepartment(shift.id, shiftIds, store, member);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.clock, size: 16, color: AppColors.accentInk),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${shift.name}  ${_pad(shift.startHour)}:${_pad(shift.startMinute)} – ${_pad(shift.endHour)}:${_pad(shift.endMinute)}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.neutral, fontFamily: 'BeVietnamPro'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (dept != null && dept.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.managerAccent.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.managerAccent.withOpacity(0.25)),
                                    ),
                                    child: Text(
                                      dept,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.managerAccent,
                                        fontFamily: 'BeVietnamPro',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (hasDelivery || hasGiaoHang)
                    Row(
                      children: [
                        if (hasDelivery)
                          Container(
                            margin: const EdgeInsets.only(right: 8, bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.success.withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.truck, size: 14, color: AppColors.success),
                                SizedBox(width: 4),
                                Text('Chở hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success, fontFamily: 'BeVietnamPro')),
                              ],
                            ),
                          ),
                        if (hasGiaoHang)
                          Container(
                            margin: const EdgeInsets.only(right: 8, bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.managerAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.managerAccent.withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.bike, size: 14, color: AppColors.managerAccent),
                                SizedBox(width: 4),
                                Text('Giao hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.managerAccent, fontFamily: 'BeVietnamPro')),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String? _getShiftDepartment(String shiftId, List<String> shiftIds, StoreModel store, MemberModel? member) {
    final matchingEntry = shiftIds.firstWhere((id) => id.split('|').first == shiftId, orElse: () => '');
    if (matchingEntry.contains('|')) {
      final deptId = matchingEntry.split('|')[1];
      final deptDef = store.departments.where((d) => d.id == deptId || d.shortName == deptId).firstOrNull;
      if (deptDef != null) return deptDef.name;
      return deptId;
    }
    if (member?.department != null && member!.department!.isNotEmpty) {
      final deptDef = store.departments.where((d) => d.id == member.department || d.shortName == member.department || d.name == member.department).firstOrNull;
      return deptDef?.name ?? member.department;
    }
    return null;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
