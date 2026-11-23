import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../../../models/attendance_model.dart';
import '../../../models/store_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../store/providers/store_provider.dart';
import '../repositories/attendance_repository.dart';
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
      final repo = ref.read(attendanceRepositoryProvider);
      final activeAtt = currentAttendance ??
          await repo.getActiveAttendance(store.id, userId);
      if (!mounted) return;
      final confirmed = await _showCheckOutConfirmation(
        context,
        activeAtt,
        store.id,
        userId,
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(attendanceRepositoryProvider);

      // 1. Validate WiFi or GPS based on the selected method
      await _validateMethod(store, isCheckedIn);

      if (isCheckedIn) {
        await repo.checkOut(store.id, userId);
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

