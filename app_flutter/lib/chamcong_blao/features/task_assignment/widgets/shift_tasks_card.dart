import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/task_assignment_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../../store/providers/store_provider.dart';
import '../providers/task_provider.dart';
import '../screens/task_report_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Thẻ hiển thị trên Dashboard ca làm việc:
/// - Lấy danh sách task của ngày được chọn áp dụng cho user hiện tại (todayUserTasksProvider)
/// - Hỗ trợ chuyển đổi ngày (hôm nay, hôm qua, ngày mai, hoặc chọn ngày bất kỳ) để nhân viên có thể xem và hoàn thành việc bất cứ lúc nào
/// - Hiển thị tiến độ: ví dụ "Công việc: 2/3 hoàn thành" kèm Progress Indicator
/// - Danh sách tóm tắt các việc trong ca, icon trạng thái (đã hoàn thành xanh lá, chưa hoàn thành cam)
/// - Bấm vào từng việc mở TaskReportScreen để xem/báo cáo ngay
class ShiftTasksCard extends ConsumerStatefulWidget {
  final String? storeId;
  final String? userId;
  final String? dateStr; // YYYY-MM-DD
  final VoidCallback? onTasksChanged;

  const ShiftTasksCard({
    super.key,
    this.storeId,
    this.userId,
    this.dateStr,
    this.onTasksChanged,
  });

  @override
  ConsumerState<ShiftTasksCard> createState() => _ShiftTasksCardState();
}

class _ShiftTasksCardState extends ConsumerState<ShiftTasksCard> {
  DateTime? _selectedDate;
  bool _userManuallyChangedDate = false;

  @override
  void initState() {
    super.initState();
    _initDate();
  }

  @override
  void didUpdateWidget(covariant ShiftTasksCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dateStr != oldWidget.dateStr && widget.dateStr != null) {
      _userManuallyChangedDate = false;
      _initDate();
    }
  }

  void _initDate() {
    if (widget.dateStr != null) {
      try {
        _selectedDate = DateTime.parse(widget.dateStr!);
      } catch (_) {
        final vnNow = DateTime.now().toUtc().add(const Duration(hours: 7));
        _selectedDate = DateTime(vnNow.year, vnNow.month, vnNow.day);
      }
    } else {
      final vnNow = DateTime.now().toUtc().add(const Duration(hours: 7));
      _selectedDate = DateTime(vnNow.year, vnNow.month, vnNow.day);
    }
  }

  void _previousDay() {
    _userManuallyChangedDate = true;
    setState(() {
      _selectedDate = (_selectedDate ?? DateTime.now()).subtract(const Duration(days: 1));
    });
  }

  void _nextDay() {
    _userManuallyChangedDate = true;
    setState(() {
      _selectedDate = (_selectedDate ?? DateTime.now()).add(const Duration(days: 1));
    });
  }

  void _goToCurrentShiftOrToday({DateTime? activeShiftDate}) {
    _userManuallyChangedDate = false;
    setState(() {
      if (activeShiftDate != null) {
        _selectedDate = activeShiftDate;
      } else {
        final vnNow = DateTime.now().toUtc().add(const Duration(hours: 7));
        _selectedDate = DateTime(vnNow.year, vnNow.month, vnNow.day);
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      locale: const Locale('vi', 'VN'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      _userManuallyChangedDate = true;
      setState(() => _selectedDate = picked);
    }
  }

  String _formatDateTitle(
    DateTime dt, {
    bool isSelectedActiveShift = false,
    bool isOvernightShift = false,
    required DateTime calendarToday,
  }) {
    final target = DateTime(dt.year, dt.month, dt.day);

    if (isSelectedActiveShift) {
      if (isOvernightShift) {
        return 'Ca hiện tại (${DateFormat('dd/MM').format(dt)})';
      }
      return 'Ca hiện tại (${DateFormat('dd/MM').format(dt)})';
    }

    if (target == calendarToday) {
      return 'Hôm nay (${DateFormat('dd/MM').format(dt)})';
    } else if (target == calendarToday.subtract(const Duration(days: 1))) {
      return 'Hôm qua (${DateFormat('dd/MM').format(dt)})';
    } else if (target == calendarToday.add(const Duration(days: 1))) {
      return 'Ngày mai (${DateFormat('dd/MM').format(dt)})';
    } else {
      return DateFormat('dd/MM/yyyy').format(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStoreId =
        widget.storeId ?? ref.watch(currentStoreIdProvider) ?? '';
    final effectiveUserId =
        widget.userId ?? ref.watch(currentUserIdProvider) ?? '';

    if (effectiveStoreId.isEmpty || effectiveUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    final vnNow = DateTime.now().toUtc().add(const Duration(hours: 7));
    final calendarToday = DateTime(vnNow.year, vnNow.month, vnNow.day);
    final todayStr =
        '${calendarToday.year}-${calendarToday.month.toString().padLeft(2, '0')}-${calendarToday.day.toString().padLeft(2, '0')}';

    // ── XÁC ĐỊNH CA LÀM VIỆC ĐANG HOẠT ĐỘNG (ACTIVE SHIFT) ──
    // Kiểm tra xem nhân viên có đang trong ca (chưa bấm Ra ca / checkOut == null) hay không
    final activeAttList = ref.watch(activeAttendancesProvider).valueOrNull ?? [];
    final activeAttOfUser = activeAttList.where((a) => a.userId == effectiveUserId && a.checkOut == null).firstOrNull;
    final myActiveAtt = ref.watch(todayAttendanceProvider).valueOrNull;
    final resolvedActiveAtt = activeAttOfUser ?? ((myActiveAtt != null && myActiveAtt.userId == effectiveUserId && myActiveAtt.checkOut == null) ? myActiveAtt : null);

    final isInShift = resolvedActiveAtt != null && resolvedActiveAtt.checkOut == null;
    DateTime? activeShiftDate;
    String? activeShiftDateStr;
    if (isInShift && resolvedActiveAtt.date.isNotEmpty) {
      try {
        activeShiftDate = DateTime.parse(resolvedActiveAtt.date);
        activeShiftDateStr = resolvedActiveAtt.date;
      } catch (_) {}
    }

    // Nếu không truyền dateStr cố định và người dùng chưa chủ động bấm nút đổi ngày:
    // Tự động neo công việc vào ngày của ca làm việc hiện tại (cho đến khi out ca)
    if (widget.dateStr != null) {
      try {
        _selectedDate = DateTime.parse(widget.dateStr!);
      } catch (_) {
        _selectedDate = calendarToday;
      }
    } else if (!_userManuallyChangedDate) {
      if (isInShift && activeShiftDate != null) {
        _selectedDate = activeShiftDate;
      } else {
        _selectedDate = calendarToday;
      }
    }
    _selectedDate ??= (isInShift && activeShiftDate != null) ? activeShiftDate : calendarToday;

    final effectiveDateStr =
        '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';

    final params = (
      storeId: effectiveStoreId,
      userId: effectiveUserId,
      dateStr: effectiveDateStr,
    );

    final target = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    final isToday = target == calendarToday;
    final isSelectedActiveShift = isInShift && activeShiftDate != null && target == activeShiftDate;
    final isOvernightShift = isInShift && activeShiftDateStr != null && activeShiftDateStr != todayStr;

    final dateTitle = _formatDateTitle(
      _selectedDate!,
      isSelectedActiveShift: isSelectedActiveShift,
      isOvernightShift: isOvernightShift,
      calendarToday: calendarToday,
    );

    final tasksAsync = ref.watch(todayUserTasksProvider(params));
    final unfinishedAsync = ref.watch(unfinishedUserTasksProvider(params));

    return tasksAsync.when(
      loading: () => _buildLoadingCard(),
      error: (_, __) => const SizedBox.shrink(),
      data: (tasks) {
        if (tasks.isEmpty) {
          return _buildEmptyCard(
            dateTitle: dateTitle,
            isToday: isToday,
            isSelectedActiveShift: isSelectedActiveShift,
            isInShift: isInShift,
            activeShiftDate: activeShiftDate,
          );
        }

        final isStatusLoading =
            unfinishedAsync.isLoading && !unfinishedAsync.hasValue;
        final unfinishedTasks =
            unfinishedAsync.valueOrNull ?? (isStatusLoading ? tasks : []);
        final unfinishedIds = unfinishedTasks.map((t) => t.id).toSet();

        final totalCount = tasks.length;
        final unfinishedCount = unfinishedTasks.length;
        final completedCount = isStatusLoading
            ? 0
            : (totalCount - unfinishedCount).clamp(0, totalCount);
        final progress =
            totalCount > 0 ? (completedCount / totalCount) : 0.0;
        final isAllDone = !isStatusLoading && (completedCount == totalCount);

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isAllDone
                  ? AppColors.success.withValues(alpha: 0.3)
                  : AppColors.cardOutline,
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Date Switcher
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isAllDone
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isAllDone
                          ? LucideIcons.circleCheckBig
                          : LucideIcons.clipboardCheck,
                      color: isAllDone ? AppColors.success : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Công việc được giao',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'BeVietnamPro',
                            color: AppColors.neutral,
                          ),
                        ),
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  dateTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'BeVietnamPro',
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const Icon(LucideIcons.chevronDown,
                                  size: 16, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Progress badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: isAllDone
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isAllDone
                            ? AppColors.success.withValues(alpha: 0.3)
                            : AppColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isStatusLoading) ...[
                          const SizedBox(
                            width: 9,
                            height: 9,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.warning,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          '$completedCount/$totalCount xong',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'BeVietnamPro',
                            color: isAllDone
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (isOvernightShift && isSelectedActiveShift) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: EdgeInsets.only(top: 2), child: Icon(LucideIcons.moon, size: 13, color: Color(0xFF2563EB))),
                      SizedBox(width: 5),
                      Expanded(child: Text(
                        'Ca làm việc qua đêm • Việc thuộc ca hiển thị cho đến khi ra ca',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E40AF),
                          fontFamily: 'BeVietnamPro',
                        ),
                      )),
                    ],
                  ),
                ),
              ] else if (isInShift && isSelectedActiveShift) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.fiber_manual_record_rounded, size: 10, color: Color(0xFF16A34A))),
                      SizedBox(width: 5),
                      Expanded(child: Text(
                        'Đang trong ca làm việc',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF166534),
                          fontFamily: 'BeVietnamPro',
                        ),
                      )),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Date navigation row (< Hôm nay >)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _previousDay,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border, width: 0.8),
                          ),
                          child: const Icon(LucideIcons.chevronLeft,
                              size: 18, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: _nextDay,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border, width: 0.8),
                          ),
                          child: const Icon(LucideIcons.chevronRight,
                              size: 18, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  if (isInShift && !isSelectedActiveShift)
                    Flexible(child: InkWell(
                      onTap: () => _goToCurrentShiftOrToday(activeShiftDate: activeShiftDate),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.zap, size: 12, color: AppColors.primary),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                'Về ca hiện tại (${activeShiftDate != null ? DateFormat('dd/MM').format(activeShiftDate) : ''})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                  fontFamily: 'BeVietnamPro',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ))
                  else if (!isInShift && !isToday)
                    InkWell(
                      onTap: () => _goToCurrentShiftOrToday(),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Về hôm nay',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            fontFamily: 'BeVietnamPro',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: AppColors.paperInk,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isAllDone ? AppColors.success : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Danh sách các việc
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tasks.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: AppColors.divider, height: 14),
                itemBuilder: (ctx, index) {
                  final AssignedTask task = tasks[index];
                  final isDone =
                      !isStatusLoading && !unfinishedIds.contains(task.id);

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final res = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskReportScreen(
                            task: task,
                            workDate: effectiveDateStr,
                          ),
                        ),
                      );
                      if (res == true || ctx.mounted) {
                        ref.invalidate(todayUserTasksProvider(params));
                        ref.invalidate(unfinishedUserTasksProvider(params));
                        widget.onTasksChanged?.call();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 2),
                      child: Row(
                        children: [
                          Icon(
                            isDone
                                ? LucideIcons.circleCheck
                                : LucideIcons.clipboardClock,
                            color: isDone
                                ? AppColors.success
                                : AppColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'BeVietnamPro',
                                    color: isDone
                                        ? AppColors.textSecondary
                                        : AppColors.neutral,
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (task.createdByName.isNotEmpty)
                                  Text(
                                    'Giao bởi: ${task.createdByName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                      fontFamily: 'BeVietnamPro',
                                    ),
                                  ),
                                if (task.repeatDaily || task.requirePhoto) ...[
                                  const SizedBox(height: 3),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (task.repeatDaily)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(LucideIcons.repeat,
                                                  size: 10,
                                                  color: AppColors.primary),
                                              SizedBox(width: 3),
                                              Text(
                                                'Lặp mỗi ngày',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary,
                                                  fontFamily: 'BeVietnamPro',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (task.requirePhoto)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF3E0),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(LucideIcons.camera,
                                                  size: 10,
                                                  color: Color(0xFFE65100)),
                                              SizedBox(width: 3),
                                              Text(
                                                'Cần ảnh',
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
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            LucideIcons.chevronRight,
                            size: 18,
                            color: AppColors.textDisabled,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyCard({
    required String dateTitle,
    required bool isToday,
    bool isSelectedActiveShift = false,
    bool isInShift = false,
    DateTime? activeShiftDate,
  }) {
    String emptyMessage;
    if (isSelectedActiveShift) {
      emptyMessage = 'Ca làm việc này bạn không có công việc được phân công';
    } else if (isToday) {
      emptyMessage = 'Hôm nay bạn không có công việc được phân công';
    } else {
      emptyMessage = 'Không có công việc được phân công vào ngày này';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardOutline, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.circleCheckBig,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Công việc được giao',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'BeVietnamPro',
                        color: AppColors.neutral,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              dateTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'BeVietnamPro',
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const Icon(LucideIcons.chevronDown,
                              size: 16, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: _previousDay,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: const Icon(LucideIcons.chevronLeft,
                          size: 18, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _nextDay,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: const Icon(LucideIcons.chevronRight,
                          size: 18, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  emptyMessage,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontFamily: 'BeVietnamPro',
                  ),
                ),
              ),
              if (isInShift && !isSelectedActiveShift)
                InkWell(
                  onTap: () => _goToCurrentShiftOrToday(activeShiftDate: activeShiftDate),
                  child: Text(
                    'Về ca hiện tại (${activeShiftDate != null ? DateFormat('dd/MM').format(activeShiftDate) : ''})',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontFamily: 'BeVietnamPro',
                    ),
                  ),
                )
              else if (!isInShift && !isToday)
                InkWell(
                  onTap: () => _goToCurrentShiftOrToday(),
                  child: const Text(
                    'Về hôm nay',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontFamily: 'BeVietnamPro',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      height: 90,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardOutline, width: 1.2),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
