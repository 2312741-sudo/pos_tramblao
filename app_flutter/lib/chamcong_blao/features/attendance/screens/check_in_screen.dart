import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../../../core/utils/production_checklist_utils.dart';
import '../../../models/attendance_model.dart';
import '../../../models/store_model.dart';
import '../../../models/production_model.dart';
import '../../../models/schedule_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../store/providers/store_provider.dart';
import '../../store/screens/shift_settings_screen.dart';
import '../repositories/attendance_repository.dart';
import '../../production/providers/production_provider.dart';
import '../../schedule/providers/schedule_provider.dart';
import '../../task_assignment/providers/task_provider.dart';
import '../../task_assignment/screens/task_report_screen.dart';
import '../../../models/task_assignment_model.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// File-local provider (private) to avoid name collision with the global
// todayAttendanceProvider in attendance_provider.dart (which has a different signature).
// Uses watchActiveAttendance to handle cross-midnight shifts correctly.
final _localTodayAttendanceProvider =
    StreamProvider.family<AttendanceModel?, String>((ref, userId) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value(null);
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.watchActiveAttendance(storeId, userId);
});

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late Timer _timer;
  DateTime _currentTime = DateTime.now();
  CheckInMethod _selectedMethod = CheckInMethod.wifi;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 1.0, end: 1.05).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _validateMethod(StoreModel store, bool isCheckedIn) async {
    final actionText = isCheckedIn ? 'chấm ra' : 'chấm công';
    if (_selectedMethod == CheckInMethod.wifi) {
      final validWifis = store.wifis.where((w) => w.hasValidBssid).toList();
      if (validWifis.isEmpty) {
        throw Exception('Cửa hàng chưa cấu hình WiFi chấm công.');
      }
      final isWifiCorrect = await LocationUtils.isOnStoreWifi(validWifis);
      if (!isWifiCorrect) {
        throw Exception(
            'Bạn chưa kết nối đúng mạng WiFi của cửa hàng (hoặc ứng dụng không đọc được thông tin WiFi). Vui lòng kết nối WiFi tại nơi làm việc để $actionText.');
      }
    } else if (_selectedMethod == CheckInMethod.gps) {
      if (!store.hasLocation) {
        throw Exception('Cửa hàng chưa cấu hình Vị trí.');
      }
      if (store.locations.isNotEmpty) {
        final result = await LocationUtils.checkLocationsRange(store.locations);
        if (!result.inRange) {
          if (result.nearestLocation != null && result.minDistance != null) {
            final nearest = result.nearestLocation!;
            final distStr = result.minDistance! >= 1000
                ? '${(result.minDistance! / 1000).toStringAsFixed(1)}km'
                : '${result.minDistance!.round()}m';
            throw Exception(
                'Bạn không ở trong phạm vi cửa hàng. Vị trí gần nhất: "${nearest.name}" (cách $distStr, bán kính ${nearest.radiusMeters}m). Vui lòng đến cửa hàng để $actionText.');
          }
          throw Exception(
              'Bạn không ở trong phạm vi các vị trí của cửa hàng. Vui lòng đến cửa hàng để $actionText.');
        }
      } else {
        final canProceed = await LocationUtils.isInStoreRange(
            store.latitude!, store.longitude!, store.radiusMeters.toDouble());
        if (!canProceed) {
          throw Exception(
              'Bạn không ở trong phạm vi cửa hàng. Vui lòng đến cửa hàng để $actionText.');
        }
      }
    }
  }

  Future<void> _handleCheckIn(
    StoreModel store,
    String userId,
    bool isCheckedIn, {
    AttendanceModel? currentAttendance,
  }) async {
    if (isCheckedIn) {
      // ── CỔNG RÀNG BUỘC RA CA (CHECK-OUT GATEKEEPER) ──
      final repo = ref.read(attendanceRepositoryProvider);
      final activeAtt = currentAttendance ??
          await repo.getActiveAttendance(store.id, userId);
      final checkInTime = activeAtt?.checkIn ?? DateTime.now();
      final checkInVN = checkInTime.toUtc().add(const Duration(hours: 7));
      final workdayDateStr =
          '${checkInVN.year}-${checkInVN.month.toString().padLeft(2, '0')}-${checkInVN.day.toString().padLeft(2, '0')}';

      setState(() => _isLoading = true);
      List<AssignedTask> unfinishedTasks = [];
      try {
        unfinishedTasks = await ref
            .read(taskRepositoryProvider)
            .getUnfinishedTasksForUserOnDate(
              store.id,
              userId,
              workdayDateStr,
            );
      } catch (_) {}
      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;

      bool isConfirmed = false;
      if (unfinishedTasks.isNotEmpty) {
        if (!mounted) return;
        final canProceed = await _showUnfinishedTasksModal(
          context,
          store,
          userId,
          workdayDateStr,
          unfinishedTasks,
          attendance: activeAtt,
        );
        if (canProceed != true || !mounted) {
          // Người dùng chọn ở lại tiếp tục làm việc hoặc đóng modal
          return;
        }
        // Đã bấm xác nhận ra ca (hoàn thành sau) ngay trên modal nhắc việc
        isConfirmed = true;
      }

      if (!isConfirmed) {
        final confirmed = await _showCheckOutConfirmation(
          context,
          activeAtt,
          store.id,
          userId,
        );
        if (confirmed != true || !mounted) return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(attendanceRepositoryProvider);

      // 1. Validate WiFi or GPS based on the selected method
      await _validateMethod(store, isCheckedIn);

      if (isCheckedIn) {
        // ── CHECKOUT LOGIC (anchored strictly on Check-in Workday) ──
        final activeAtt = currentAttendance ??
            await repo.getActiveAttendance(store.id, userId);
        if (activeAtt == null) {
          throw Exception('Không tìm thấy ca làm việc nào đang hoạt động');
        }
        final checkInTime = activeAtt.checkIn;

        // 1. Resolve member's department
        final membersList = ref.read(storeMembersProvider).valueOrNull ?? [];
        final currentMember =
            membersList.where((m) => m.userId == userId).firstOrNull;
        final memberDepartmentId = currentMember?.department;

        // 2. Fetch weekly schedule strictly for the check-in workday week
        final checkInVN = checkInTime.toUtc().add(const Duration(hours: 7));
        final mondayOfCheckIn =
            checkInVN.subtract(Duration(days: checkInVN.weekday - 1));
        final weekStartStr =
            '${mondayOfCheckIn.year}-${mondayOfCheckIn.month.toString().padLeft(2, '0')}-${mondayOfCheckIn.day.toString().padLeft(2, '0')}';

        ScheduleModel? schedule;
        try {
          final scheduleRepo = ref.read(scheduleRepositoryProvider);
          schedule = await scheduleRepo.getWeekSchedule(store.id, weekStartStr);
        } catch (_) {}

        // 3. Check if a report was already submitted for this exact workday
        final workdayDateStr =
            '${checkInVN.year}-${checkInVN.month.toString().padLeft(2, '0')}-${checkInVN.day.toString().padLeft(2, '0')}';
        final productionRepo = ref.read(productionRepositoryProvider);
        final hasAlreadyReported = await productionRepo.hasReportToday(
            store.id, userId, workdayDateStr);

        // 4. Evaluate checklist requirement strictly anchored on checkInTime
        final eval = ProductionChecklistUtils.evaluateChecklistRequirement(
          checkInTime: checkInTime,
          now: DateTime.now(),
          userId: userId,
          store: store,
          memberDepartmentId: memberDepartmentId,
          schedule: schedule,
          hasAlreadyReportedForWorkday: hasAlreadyReported,
        );

        if (eval.isRequired) {
          final tasks = await productionRepo.getActiveTasks(store.id);

          if (!mounted) return;
          setState(() => _isLoading = false);
          final result = await _showProductionChecklist(
            context,
            tasks,
            eval.resolvedShift,
            store,
            userId,
            eval.workdayDate,
          );
          if (result != true) {
            // User cancelled/closed checklist modal -> halt checkout
            return;
          }
          if (!mounted) return;
          setState(() => _isLoading = true);
        }

        await repo.checkOut(store.id, userId,
            isProductionShift: eval.hasProductionShiftOnWorkday);
        _showSuccess('Chấm ra thành công!');
        return;
      }

      await repo.checkIn(store.id, userId, _selectedMethod);
      _showSuccess('Chấm công thành công!');
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool?> _showCheckOutConfirmation(
    BuildContext context,
    AttendanceModel? attendance,
    String storeId,
    String userId,
  ) async {
    AttendanceModel? att = attendance;
    if (att == null) {
      try {
        final repo = ref.read(attendanceRepositoryProvider);
        att = await repo.getActiveAttendance(storeId, userId);
      } catch (_) {}
    }

    String? inTimeStr;
    String? durationStr;

    if (att != null) {
      final inTimeLocal = att.checkIn.toLocal();
      inTimeStr = DateFormat('HH:mm - dd/MM/yyyy').format(inTimeLocal);
      final diff = DateTime.now().difference(att.checkIn);
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      durationStr = h > 0 ? '$h giờ $m phút' : '$m phút';
    }

    if (!context.mounted) return false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.logOut,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Xác nhận ra ca',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'BeVietnamPro',
                  color: AppColors.neutral,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bạn có chắc chắn muốn kết thúc ca làm việc lúc này không?',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
                fontFamily: 'BeVietnamPro',
              ),
            ),
            if (inTimeStr != null || durationStr != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    if (inTimeStr != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Giờ vào:',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontFamily: 'BeVietnamPro',
                            ),
                          ),
                          Text(
                            inTimeStr,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              fontFamily: 'BeVietnamPro',
                            ),
                          ),
                        ],
                      ),
                    if (inTimeStr != null && durationStr != null)
                      const SizedBox(height: 8),
                    if (durationStr != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Thời gian làm:',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontFamily: 'BeVietnamPro',
                            ),
                          ),
                          Text(
                            durationStr,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                              fontFamily: 'BeVietnamPro',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Hủy',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                fontFamily: 'BeVietnamPro',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text(
              'Xác nhận ra ca',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'BeVietnamPro',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showProductionChecklist(
    BuildContext context,
    List<ProductionTask> tasks,
    ShiftDefinition shift,
    StoreModel store,
    String userId,
    String workdayDate,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _ProductionChecklistDialog(
          tasks: tasks,
          shift: shift,
          storeId: store.id,
          userId: userId,
          workdayDate: workdayDate,
          onSubmitted: () => Navigator.pop(ctx, true),
        );
      },
    );
  }

  Future<bool?> _showUnfinishedTasksModal(
    BuildContext context,
    StoreModel store,
    String userId,
    String workdayDateStr,
    List<AssignedTask> unfinishedTasks, {
    AttendanceModel? attendance,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _UnfinishedTasksModal(
          store: store,
          userId: userId,
          workdayDateStr: workdayDateStr,
          initialUnfinishedTasks: unfinishedTasks,
          attendance: attendance,
        );
      },
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    final storeAsync = ref.watch(currentStoreProvider);
    if (userId == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return storeAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, s) => Scaffold(body: Center(child: Text('Lỗi: $e'))),
      data: (store) {
        if (store == null)
          return const Scaffold(
              body: Center(child: Text('Không tìm thấy cửa hàng')));
        final attAsync = ref.watch(_localTodayAttendanceProvider(userId));

        return attAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, s) =>
              Scaffold(body: Center(child: Text('Lỗi điểm danh: $e'))),
          data: (attendance) {
            final isCheckedIn = attendance?.isActive ?? false;

            return Scaffold(
              backgroundColor: AppColors.surface,
              appBar: AppBar(
                title: const Text('Chấm Công',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.info)),
                centerTitle: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                    icon: const Icon(LucideIcons.chevronLeft,
                        color: AppColors.info),
                    onPressed: () => context.pop()),
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Branded shift clock
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.info, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      AppColors.primary.withOpacity(0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8))
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                  DateFormat('EEEE, dd/MM/yyyy', 'vi')
                                      .format(_currentTime),
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 8),
                              Text(DateFormat('HH:mm:ss').format(_currentTime),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 48,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2)),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.store,
                                        color: Colors.white.withOpacity(0.9),
                                        size: 18),
                                    const SizedBox(width: 8),
                                    Flexible(child: Text(store.name,
                                        style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.9),
                                            fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        if (isCheckedIn) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.cardSurface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.cardOutline, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4))
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.1),
                                      shape: BoxShape.circle),
                                  child: const Icon(LucideIcons.logIn,
                                      color: AppColors.success, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Giờ vào ca',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text(
                                        DateFormat('HH:mm').format(
                                            attendance!.checkIn.toLocal()),
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black87)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isCheckedIn
                                ? 'Phương thức ra ca'
                                : 'Phương thức chấm công',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildMethodCard(CheckInMethod.wifi, LucideIcons.wifi,
                                'WiFi', store.hasWifi),
                            const SizedBox(width: 16),
                            _buildMethodCard(CheckInMethod.gps,
                                LucideIcons.mapPin, 'Vị trí', store.hasLocation),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Check Button
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: isCheckedIn ? 1.0 : _pulseAnimation.value,
                              child: GestureDetector(
                                onTap: _isLoading
                                    ? null
                                    : () => _handleCheckIn(
                                          store,
                                          userId,
                                          isCheckedIn,
                                          currentAttendance: attendance,
                                        ),
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: isCheckedIn
                                          ? [
                                              AppColors.textSecondary,
                                              AppColors.info
                                            ]
                                          : [
                                              AppColors.tealAccent,
                                              AppColors.success
                                            ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (isCheckedIn
                                                ? AppColors.info
                                                : AppColors.success)
                                            .withOpacity(0.4),
                                        blurRadius: 30,
                                        spreadRadius: 10,
                                      )
                                    ],
                                  ),
                                  child: Center(
                                    child: _isLoading
                                        ? const CircularProgressIndicator(
                                            color: Colors.white)
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                  isCheckedIn
                                                      ? LucideIcons.logOut
                                                      : Icons
                                                          .fingerprint_rounded,
                                                  color: Colors.white,
                                                  size: 64),
                                              const SizedBox(height: 12),
                                              Text(
                                                  isCheckedIn
                                                      ? 'RA CA'
                                                      : 'VÀO CA',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 24,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 2)),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Text(
                            isCheckedIn
                                ? 'Bạn đang trong ca làm việc'
                                : 'Nhấn để bắt đầu ca làm việc',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMethodCard(
      CheckInMethod method, IconData icon, String label, bool isAvailable) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap:
            isAvailable ? () => setState(() => _selectedMethod = method) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.info : AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color:
                    isSelected ? AppColors.info : AppColors.border,
                width: 2),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: AppColors.info.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : [],
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isAvailable
                      ? (isSelected ? Colors.white : Colors.grey.shade600)
                      : Colors.grey.shade300,
                  size: 32),
              const SizedBox(height: 12),
              Text(label,
                  style: TextStyle(
                      color: isAvailable
                          ? (isSelected ? Colors.white : Colors.black87)
                          : Colors.grey.shade400,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Production Checklist BottomSheet ─────────────────────────────────────────

class _ProductionChecklistDialog extends ConsumerStatefulWidget {
  final List<ProductionTask> tasks;
  final ShiftDefinition shift;
  final String storeId;
  final String userId;
  final String workdayDate;
  final VoidCallback onSubmitted;

  const _ProductionChecklistDialog({
    required this.tasks,
    required this.shift,
    required this.storeId,
    required this.userId,
    required this.workdayDate,
    required this.onSubmitted,
  });

  @override
  ConsumerState<_ProductionChecklistDialog> createState() =>
      _ProductionChecklistDialogState();
}

class _ProductionChecklistDialogState
    extends ConsumerState<_ProductionChecklistDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _selected = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    for (final t in widget.tasks) {
      _controllers[t.id] = TextEditingController();
      _selected[t.id] = false;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final selectedTasks =
        widget.tasks.where((t) => _selected[t.id] == true).toList();
    if (selectedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vui lòng chọn ít nhất 1 công việc đã hoàn thành')));
      return;
    }

    final entries = <ProductionTaskEntry>[];
    for (final t in selectedTasks) {
      final hasUnit = t.unitLabel.trim().isNotEmpty;
      double val = 1.0;
      if (hasUnit) {
        final valStr = (_controllers[t.id]?.text ?? '0').replaceAll(',', '.');
        val = double.tryParse(valStr) ?? 0.0;
        if (val <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Vui lòng nhập số lượng hợp lệ cho ${t.name}')));
          return;
        }
      }
      entries.add(ProductionTaskEntry(
        taskId: t.id,
        taskName: t.name,
        unit: t.unit,
        unitLabel: t.unitLabel,
        value: val,
      ));
    }

    setState(() => _isSubmitting = true);
    try {
      final members = ref.read(storeMembersProvider).valueOrNull ?? [];
      final member =
          members.where((m) => m.userId == widget.userId).firstOrNull;
      final memberName = member?.name ?? 'Nhân viên';

      final report = ProductionReport(
        id: '',
        userId: widget.userId,
        memberName: memberName,
        date: widget.workdayDate,
        shiftId: widget.shift.id,
        shiftName: widget.shift.name,
        checkoutTime: DateTime.now(),
        note: '',
        tasks: entries,
      );

      await ref
          .read(productionRepositoryProvider)
          .submitReport(widget.storeId, report);
      if (mounted) {
        widget.onSubmitted(); // Tell parent to continue checkout
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 24,
          left: 24,
          right: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Báo cáo sản xuất',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.keyboardOff),
                      tooltip: 'Ẩn bàn phím',
                      onPressed: () => FocusScope.of(context).unfocus(),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const Text(
                'Vui lòng đánh dấu các công việc đã làm trong ca và nhập số lượng để hệ thống ghi nhận.',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: ListView.builder(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                shrinkWrap: true,
                itemCount: widget.tasks.length,
                itemBuilder: (ctx, i) {
                  final t = widget.tasks[i];
                  final isSelected = _selected[t.id] ?? false;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.05)
                          : Colors.white,
                      border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CheckboxListTile(
                      value: isSelected,
                      activeColor: AppColors.primary,
                      title: Text(t.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: isSelected
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: t.unitLabel.trim().isNotEmpty
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _controllers[t.id],
                                            keyboardType: const TextInputType
                                                .numberWithOptions(decimal: true),
                                            textInputAction:
                                                TextInputAction.done,
                                            onSubmitted: (_) =>
                                                FocusScope.of(context).unfocus(),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                  RegExp(r'[\d.,]')),
                                            ],
                                            decoration: InputDecoration(
                                              isDense: true,
                                              hintText:
                                                  'Nhập số lượng (${t.unitLabel})...',
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 12),
                                      Flexible(child: Text(t.unitLabel,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                    ],
                                  )
                                : const Row(
                                    children: [
                                      Icon(LucideIcons.circleCheck,
                                          color: AppColors.success, size: 16),
                                      SizedBox(width: 6),
                                      Text('Đã hoàn thành',
                                          style: TextStyle(
                                              color: AppColors.success,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                          )
                        : null,
                    onChanged: (val) {
                      setState(() => _selected[t.id] = val ?? false);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('HOÀN TẤT & RA CA',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}
}

// ── Unfinished Tasks Modal (Check-out Gatekeeper) ────────────────────────────

class _UnfinishedTasksModal extends ConsumerStatefulWidget {
  final StoreModel store;
  final String userId;
  final String workdayDateStr;
  final List<AssignedTask> initialUnfinishedTasks;
  final AttendanceModel? attendance;

  const _UnfinishedTasksModal({
    required this.store,
    required this.userId,
    required this.workdayDateStr,
    required this.initialUnfinishedTasks,
    this.attendance,
  });

  @override
  ConsumerState<_UnfinishedTasksModal> createState() =>
      _UnfinishedTasksModalState();
}

class _UnfinishedTasksModalState extends ConsumerState<_UnfinishedTasksModal> {
  late List<AssignedTask> _tasks;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _tasks = List.from(widget.initialUnfinishedTasks);
  }

  Future<void> _checkTasksAgain() async {
    setState(() => _isChecking = true);
    try {
      final updated = await ref
          .read(taskRepositoryProvider)
          .getUnfinishedTasksForUserOnDate(
            widget.store.id,
            widget.userId,
            widget.workdayDateStr,
          );
      if (mounted) {
        setState(() {
          _tasks = updated;
          _isChecking = false;
        });
        if (_tasks.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Tuyệt vời! Bạn đã hoàn thành tất cả công việc được giao.'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? inTimeStr;
    String? durationStr;
    if (widget.attendance != null) {
      final inTimeLocal = widget.attendance!.checkIn.toLocal();
      inTimeStr = DateFormat('HH:mm').format(inTimeLocal);
      final diff = DateTime.now().difference(widget.attendance!.checkIn);
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      durationStr = h > 0 ? '$h giờ $m phút' : '$m phút';
    }

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header thông báo công việc
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFB74D).withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.clipboardList,
                    color: Color(0xFFE65100),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bạn còn ${_tasks.length} công việc chưa hoàn thành',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'BeVietnamPro',
                          color: AppColors.neutral,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Bạn có thể báo cáo ngay bây giờ hoặc tiếp tục ra ca và hoàn thành sau bất kỳ lúc nào.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          fontFamily: 'BeVietnamPro',
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (durationStr != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.clock,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Thời gian làm: $durationStr',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                            fontFamily: 'BeVietnamPro',
                          ),
                        ),
                      ],
                    ),
                    if (inTimeStr != null)
                      Text(
                        'Vào ca: $inTimeStr',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFamily: 'BeVietnamPro',
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 14),

            // Danh sách task chưa hoàn thành
            if (_isChecking)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, index) {
                    final task = _tasks[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskReportScreen(
                              task: task,
                              workDate: widget.workdayDateStr,
                            ),
                          ),
                        );
                        if (mounted) {
                          await _checkTasksAgain();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                LucideIcons.clipboardClock,
                                color: AppColors.warning,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    task.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'BeVietnamPro',
                                      color: AppColors.neutral,
                                    ),
                                  ),
                                  if (task.createdByName.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Người giao: ${task.createdByName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        fontFamily: 'BeVietnamPro',
                                      ),
                                    ),
                                  ],
                                  if (task.requirePhoto) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3E0),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: const Color(0xFFFFB74D),
                                            width: 0.6),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(LucideIcons.camera,
                                              size: 10,
                                              color: Color(0xFFE65100)),
                                          SizedBox(width: 3),
                                          Text(
                                            'Cần ảnh chụp',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFE65100),
                                              fontFamily: 'BeVietnamPro',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () async {
                                await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TaskReportScreen(
                                      task: task,
                                      workDate: widget.workdayDateStr,
                                    ),
                                  ),
                                );
                                if (mounted) {
                                  await _checkTasksAgain();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 9),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Báo cáo',
                                style: TextStyle(
                                  fontSize: 13,
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
            const SizedBox(height: 18),

            // Nút hành động: Ra ca ngay (hoàn thành sau) & Ở lại làm việc
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(LucideIcons.logOut, size: 18),
                label: const Text(
                  'Xác nhận ra ca (Hoàn thành sau)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'BeVietnamPro',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Ở lại tiếp tục làm việc',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'BeVietnamPro',
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

