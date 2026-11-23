import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/router.dart';
import '../../models/member_model.dart';
import '../../models/store_model.dart';
import '../../features/store/providers/store_provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/attendance/providers/attendance_provider.dart';
import '../../features/schedule/providers/schedule_provider.dart';
import '../../models/attendance_model.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/store_drawer.dart';
import '../../core/widgets/notification_bell_icon.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../features/schedule/screens/employee_schedule_tab.dart';
import '../../core/widgets/pos_exit_button.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../cc_firebase.dart';

class EmployeeDashboard extends ConsumerStatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  ConsumerState<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends ConsumerState<EmployeeDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late Timer _clockTimer;
  DateTime _now = DateTime.now();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(shiftReminderSchedulerProvider);
    final uid = ref.watch(currentUserProvider).value?.id;

    // Proactive role check on build: Never stay on EmployeeDashboard if Owner or Manager
    final currentMember = ref.watch(currentMemberProvider);
    if (currentMember != null) {
      if (currentMember.status == MemberStatus.pending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.pendingApproval);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      } else if (currentMember.status == MemberStatus.kicked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.splash);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      } else if (currentMember.isOwner) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.ownerDashboard);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      } else if (currentMember.isManager) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.managerDashboard);
        });
        return const Scaffold(backgroundColor: AppColors.surface, body: Center(child: CircularProgressIndicator()));
      }
    }

    // Reactive role check: If user is actually Owner or Manager, auto-navigate to right dashboard
    ref.listen<MemberModel?>(currentMemberProvider, (prev, next) {
      if (CcFirebase.auth.currentUser == null || !mounted) return;
      if (next == null) return;
      if (next.status == MemberStatus.pending) {
        context.go(AppRoutes.pendingApproval);
        return;
      }
      if (next.status == MemberStatus.kicked) {
        context.go(AppRoutes.splash);
        return;
      }
      if (next.isOwner) {
        context.go(AppRoutes.ownerDashboard);
      } else if (next.isManager) {
        context.go(AppRoutes.managerDashboard);
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

    final storeAsync = ref.watch(currentStoreProvider);
    final store = storeAsync.valueOrNull;

    if (uid == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    if (store == null) {
      if (storeAsync.hasError) {
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
                    'Không thể tải dữ liệu: ${storeAsync.error}',
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
      drawer: const StoreDrawer(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _HomeTab(now: _now, pulseAnimation: _pulseAnimation, uid: uid ?? ''),
          const EmployeeScheduleTab(),
          _ProfileTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.cardOutline, width: 1.5)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _NavItem(icon: LucideIcons.house, label: 'Tổng quan', index: 0, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
              _NavItem(icon: LucideIcons.calendarDays, label: 'Lịch làm', index: 1, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
              _NavItem(icon: LucideIcons.user, label: 'Hồ sơ', index: 2, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── HOME TAB ───────────────────────────────────────────────────────────────

class _HomeTab extends ConsumerWidget {
  final DateTime now;
  final Animation<double> pulseAnimation;
  final String uid;

  const _HomeTab({required this.now, required this.pulseAnimation, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final store = ref.watch(currentStoreProvider).value;
    final attendanceAsync = ref.watch(myTodayAttendanceProvider);
    final memberAsync = ref.watch(storeMembersProvider);
    final member = memberAsync.valueOrNull?.where((m) => m.userId == uid).firstOrNull;

    if (store == null) return const SizedBox();

    final greeting = _getGreeting(now.hour);
    final firstName = (user?.name ?? 'Bạn').split(' ').last;

    return CustomScrollView(
      slivers: [
        // Header gradient
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const PosExitPillButton(),
                        const Spacer(),
                        const NotificationBellIcon(
                          iconColor: Colors.white,
                          backgroundColor: Color(0x26FFFFFF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$greeting,',
                                style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'BeVietnamPro'),
                              ),
                              Text(
                                firstName,
                                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, fontFamily: 'BeVietnamPro'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.store, color: Colors.white, size: 14),
                                const SizedBox(width: 6),
                                Flexible(child: Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'BeVietnamPro'))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Clock
                    Text(
                      DateFormat('HH:mm').format(now),
                      style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w800, fontFamily: 'BeVietnamPro', height: 1),
                    ),
                    Text(
                      DateFormat('EEEE, dd/MM/yyyy', 'vi').format(now),
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'BeVietnamPro'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Status card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: attendanceAsync.when(
              loading: () => _ShimmerCard(),
              error: (e, _) => const SizedBox.shrink(),
              data: (att) => _StatusCard(attendance: att, pulseAnimation: pulseAnimation, now: now),
            ),
          ),
        ),

        // Department badge
        if (member?.department != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.building2, size: 14, color: AppColors.info),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              member!.department!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.info, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'BeVietnamPro'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Quick actions
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Thao tác nhanh', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.neutral, fontFamily: 'BeVietnamPro')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _QuickAction(icon: LucideIcons.fingerprint, label: 'Chấm công', color: AppColors.primary, onTap: () => context.push(AppRoutes.checkIn))),
                    const SizedBox(width: 12),
                    Expanded(child: _QuickAction(icon: LucideIcons.history, label: 'Lịch sử', color: AppColors.info, onTap: () => context.push(Uri(path: AppRoutes.attendanceHistory, queryParameters: {'userId': uid}).toString()))),
                    const SizedBox(width: 12),
                    Expanded(child: _QuickAction(icon: LucideIcons.banknote, label: 'Lương', color: AppColors.success, onTap: () => context.push(AppRoutes.salary))),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Today's schedule
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: _TodayScheduleCard(uid: uid),
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

class _StatusCard extends StatelessWidget {
  final AttendanceModel? attendance;
  final Animation<double> pulseAnimation;
  final DateTime now;

  const _StatusCard({required this.attendance, required this.pulseAnimation, required this.now});

  @override
  Widget build(BuildContext context) {
    final isActive = attendance != null && attendance!.isActive;
    final isDone = attendance != null && !attendance!.isActive;

    Duration? duration;
    if (isActive) {
      duration = now.difference(attendance!.checkIn);
    } else if (isDone && attendance!.checkOut != null) {
      duration = attendance!.checkOut!.difference(attendance!.checkIn);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardOutline, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          // Status indicator
          ScaleTransition(
            scale: isActive ? pulseAnimation : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.success.withOpacity(0.1)
                    : isDone
                        ? AppColors.info.withOpacity(0.1)
                        : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isActive ? LucideIcons.timer : isDone ? LucideIcons.circleCheck : LucideIcons.circle,
                color: isActive ? AppColors.success : isDone ? AppColors.info : Colors.grey,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Đang trong ca' : isDone ? 'Đã hoàn thành ca' : 'Chưa chấm công',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'BeVietnamPro',
                    color: isActive ? AppColors.success : isDone ? AppColors.info : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                if (duration != null)
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(fontSize: 13, color: Colors.grey, fontFamily: 'BeVietnamPro'),
                  )
                else
                  const Text(
                    'Nhấn "Chấm công" để bắt đầu ca',
                    style: TextStyle(fontSize: 13, color: Colors.grey, fontFamily: 'BeVietnamPro'),
                  ),
              ],
            ),
          ),
          if (!isDone)
            ElevatedButton(
              onPressed: () => GoRouter.of(context).push(AppRoutes.checkIn),
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? AppColors.primary : AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                elevation: 0,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isActive ? 'Ra ca' : 'Vào ca', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro')),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h giờ $m phút $s giây';
    if (m > 0) return '$m phút $s giây';
    return '$s giây';
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color, fontFamily: 'BeVietnamPro')),
          ],
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
              const Text('Ca làm hôm nay', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro', color: AppColors.neutral)),
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
                                      color: AppColors.info.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.info.withOpacity(0.25)),
                                    ),
                                    child: Text(
                                      dept,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.info,
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
                              color: AppColors.info.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.info.withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.bike, size: 14, color: AppColors.info),
                                SizedBox(width: 4),
                                Text('Giao hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.info, fontFamily: 'BeVietnamPro')),
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

class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    );
  }
}



// ─── PROFILE TAB ─────────────────────────────────────────────────────────────

class _ProfileTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final uid = ref.watch(currentUserProvider).value?.id ?? '';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        leadingWidth: PosExitAppBarLeading.leadingWidthFor(context),
        leading: PosExitAppBarLeading.maybeFor(context, color: AppColors.neutral),
        title: const Text('Hồ sơ cá nhân', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro')),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.neutral,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push(AppRoutes.profileSettings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar + info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primary,
                  backgroundImage: getAvatarImageProvider(user?.avatarUrl),
                  child: getAvatarImageProvider(user?.avatarUrl) == null
                      ? Text((user?.name ?? 'U')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'BeVietnamPro')),
                      const SizedBox(height: 4),
                      Text(user?.email ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'BeVietnamPro')),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Nhân viên', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.info, fontFamily: 'BeVietnamPro')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Menu items
          _ProfileMenuItem(icon: LucideIcons.user, label: 'Chỉnh sửa hồ sơ cá nhân', color: AppColors.primary, onTap: () => context.push(AppRoutes.profileSettings)),
          _ProfileMenuItem(icon: LucideIcons.dollarSign, label: 'Xem lương tháng này', color: AppColors.success, onTap: () => context.push(AppRoutes.salary)),
          _ProfileMenuItem(icon: LucideIcons.history, label: 'Lịch sử chấm công', color: AppColors.info, onTap: () => context.push(Uri(path: AppRoutes.attendanceHistory, queryParameters: {'userId': uid}).toString())),
          _ProfileMenuItem(icon: LucideIcons.wallet, label: 'Tạm ứng lương', color: AppColors.accentInk, onTap: () => context.push(AppRoutes.salary)),
          _ProfileMenuItem(icon: LucideIcons.arrowLeft, label: 'Đóng Chấm công (Về POS)', color: AppColors.primary, onTap: () => CcFirebase.exitModule(context)),
        ],
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ProfileMenuItem({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'BeVietnamPro', fontSize: 14)),
          trailing: const Icon(LucideIcons.chevronRight, color: Colors.grey),
        ),
      ),
    );
  }
}

// ─── NAV ITEM ────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int selected;
  final Function(int) onTap;

  const _NavItem({required this.icon, required this.label, required this.index, required this.selected, required this.onTap});

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
            color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? AppColors.primary : Colors.grey, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.primary : Colors.grey,
                  fontFamily: 'BeVietnamPro',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
