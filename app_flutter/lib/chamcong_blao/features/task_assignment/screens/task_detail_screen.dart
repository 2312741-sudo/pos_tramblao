import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/department_utils.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../models/member_model.dart';
import '../../../models/task_assignment_model.dart';
import '../../schedule/providers/schedule_provider.dart';
import '../../store/providers/store_provider.dart';
import '../providers/task_provider.dart';
import 'create_task_dialog.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Màn hình Chi tiết Công việc & Báo cáo hoàn thành.
/// Cho phép Chủ và Quản lý theo dõi ai đã nộp báo cáo (văn bản + ảnh chụp)
/// và ai chưa hoàn thành công việc.
class TaskDetailScreen extends ConsumerStatefulWidget {
  final AssignedTask? task;
  final String? taskId;
  final String? storeId;

  const TaskDetailScreen({
    super.key,
    this.task,
    this.taskId,
    this.storeId,
  });

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  // Lọc theo ngày làm việc (nếu task có nhiều ngày)
  String? _selectedWorkDate;

  // Lọc theo trạng thái nộp báo cáo: 'all', 'completed', 'pending'
  String _submissionFilter = 'all';

  @override
  void initState() {
    super.initState();
    final initialTask = widget.task;
    if (initialTask != null && initialTask.executionDates.isNotEmpty) {
      // Mặc định chọn ngày hôm nay nếu có trong danh sách
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (initialTask.executionDates.contains(todayStr)) {
        _selectedWorkDate = todayStr;
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('HH:mm - dd/MM/yyyy').format(dt);
  }

  String _formatDateShort(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final check = DateTime(dt.year, dt.month, dt.day);

      if (check == today) {
        return 'Hôm nay (${DateFormat('dd/MM').format(dt)})';
      }
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  void _showImagePreviewDialog(
    BuildContext context,
    String imageUrl,
    int initialIndex,
    List<String> allUrls,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) {
        int currentIndex = initialIndex;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentUrl = allUrls[currentIndex];

            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                title: Text(
                  'Ảnh minh chứng (${currentIndex + 1}/${allUrls.length})',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              body: Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Hero(
                    tag: 'task_photo_$currentUrl',
                    child: CachedNetworkImage(
                      imageUrl: currentUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      errorWidget: (context, url, error) => Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.imageOff,
                              size: 48, color: Colors.white54),
                          const SizedBox(height: 8),
                          Text(
                            'Không tải được hình ảnh',
                            style: GoogleFonts.beVietnamPro(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              bottomNavigationBar: allUrls.length > 1
                  ? Container(
                      height: 70,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.chevronLeft,
                                color: Colors.white),
                            onPressed: currentIndex > 0
                                ? () => setDialogState(
                                    () => currentIndex--)
                                : null,
                          ),
                          const SizedBox(width: 20),
                          Flexible(child: Text(
                            '${currentIndex + 1} / ${allUrls.length}',
                            style: GoogleFonts.beVietnamPro(
                                color: Colors.white, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                          const SizedBox(width: 20),
                          IconButton(
                            icon: const Icon(LucideIcons.chevronRight,
                                color: Colors.white),
                            onPressed: currentIndex < allUrls.length - 1
                                ? () => setDialogState(
                                    () => currentIndex++)
                                : null,
                          ),
                        ],
                      ),
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  Future<void> _updateTaskStatus(AssignedTask currentTask, TaskStatus newStatus) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          newStatus == TaskStatus.completed
              ? 'Xác nhận hoàn thành'
              : 'Xác nhận hủy công việc',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: Text(
          newStatus == TaskStatus.completed
              ? 'Đánh dấu công việc này là đã hoàn thành?'
              : 'Bạn có chắc chắn muốn hủy công việc này không?',
          style: GoogleFonts.beVietnamPro(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Đóng',
              style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == TaskStatus.completed
                  ? AppColors.success
                  : AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(
              newStatus == TaskStatus.completed ? 'Đồng ý' : 'Hủy việc',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final repo = ref.read(taskRepositoryProvider);
        await repo.updateTask(currentTask.copyWith(status: newStatus));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newStatus == TaskStatus.completed
                    ? 'Đã đánh dấu hoàn thành công việc!'
                    : 'Đã hủy công việc!',
                style: GoogleFonts.beVietnamPro(),
              ),
              backgroundColor: newStatus == TaskStatus.completed
                  ? AppColors.success
                  : AppColors.textPrimary,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: $e', style: GoogleFonts.beVietnamPro()),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteTask(AssignedTask currentTask) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Xóa công việc vĩnh viễn',
          style: GoogleFonts.beVietnamPro(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          'Hành động này sẽ xóa hoàn toàn công việc "${currentTask.title}" và không thể hoàn tác.',
          style: GoogleFonts.beVietnamPro(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Đóng', style: GoogleFonts.beVietnamPro()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text('Xóa việc',
                style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final repo = ref.read(taskRepositoryProvider);
        await repo.deleteTask(currentTask.storeId, currentTask.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xóa công việc thành công!',
                  style: GoogleFonts.beVietnamPro()),
              backgroundColor: AppColors.textPrimary,
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: $e', style: GoogleFonts.beVietnamPro()),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeId = widget.task?.storeId ??
        widget.storeId ??
        ref.watch(currentStoreIdProvider) ??
        '';
    final taskId = widget.task?.id ?? widget.taskId ?? '';

    // Watch live task from Firestore
    final liveTaskAsync = ref.watch(
      singleTaskProvider((storeId: storeId, taskId: taskId)),
    );

    final currentTask = liveTaskAsync.valueOrNull ?? widget.task;

    if (currentTask == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Chi tiết công việc',
            style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold),
          ),
        ),
        body: liveTaskAsync.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : const Center(
                child: EmptyState(
                  icon: LucideIcons.searchX,
                  message: 'Không tìm thấy công việc này',
                  subtitle: 'Công việc có thể đã bị xóa khỏi hệ thống',
                ),
              ),
      );
    }

    // Stream all submissions for this task
    final submissionsAsync = ref.watch(
      allTaskSubmissionsProvider((storeId: currentTask.storeId, taskId: currentTask.id)),
    );

    // Watch active members
    final activeMembers = ref.watch(activeMembersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Chi tiết công việc',
          style: GoogleFonts.beVietnamPro(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        elevation: 0,
        backgroundColor: AppColors.cardSurface,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'edit') {
                CreateTaskDialog.show(context, taskToEdit: currentTask);
              } else if (val == 'complete') {
                _updateTaskStatus(currentTask, TaskStatus.completed);
              } else if (val == 'cancel') {
                _updateTaskStatus(currentTask, TaskStatus.cancelled);
              } else if (val == 'delete') {
                _deleteTask(currentTask);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    const Icon(LucideIcons.pencil,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text('Chỉnh sửa công việc',
                        style: GoogleFonts.beVietnamPro(fontSize: 13.5)),
                  ],
                ),
              ),
              if (currentTask.status == TaskStatus.active) ...[
                PopupMenuItem(
                  value: 'complete',
                  child: Row(
                    children: [
                      const Icon(LucideIcons.circleCheck,
                          color: AppColors.success, size: 20),
                      const SizedBox(width: 8),
                      Text('Đánh dấu hoàn thành',
                          style: GoogleFonts.beVietnamPro(fontSize: 13.5)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [
                      const Icon(LucideIcons.circleX,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text('Hủy công việc',
                          style: GoogleFonts.beVietnamPro(fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(LucideIcons.trash2,
                        color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Text('Xóa công việc',
                        style: GoogleFonts.beVietnamPro(
                            fontSize: 13.5, color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: submissionsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, stack) => Center(
          child: EmptyState(
            icon: LucideIcons.circleAlert,
            message: 'Lỗi tải báo cáo: $err',
          ),
        ),
        data: (allSubmissions) {
          return _buildBody(currentTask, allSubmissions, activeMembers);
        },
      ),
    );
  }

  Widget _buildBody(
    AssignedTask task,
    List<TaskSubmission> allSubmissions,
    List<MemberModel> activeMembers,
  ) {
    // Lọc submission theo ngày được chọn (nếu có chọn)
    final filteredSubmissions = _selectedWorkDate != null
        ? allSubmissions.where((s) => s.workDate == _selectedWorkDate).toList()
        : allSubmissions;

    // Danh sách các thành viên được giao việc
    final targetMembers = _getTargetMembers(task, activeMembers);

    // Tính toán tiến độ
    final completedUserIds = <String>{};
    for (final sub in filteredSubmissions) {
      if (sub.isCompleted) {
        completedUserIds.add(sub.userId);
      }
    }

    final totalTargetCount = targetMembers.length;
    final completedCount = targetMembers
        .where((m) => completedUserIds.contains(m.userId))
        .length;
    final pendingCount = totalTargetCount - completedCount;
    final progressPercent = totalTargetCount > 0
        ? (completedCount / totalTargetCount).clamp(0.0, 1.0)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thẻ thông tin công việc
          _buildTaskInfoCard(task),
          const SizedBox(height: 16),

          // Bộ lọc ngày thực hiện (nếu task có nhiều ngày)
          if (task.executionDates.isNotEmpty) ...[
            _buildDateFilterBar(task),
            const SizedBox(height: 16),
          ],

          // Thẻ tổng hợp tiến độ hoàn thành
          _buildProgressCard(
            totalCount: totalTargetCount,
            completedCount: completedCount,
            pendingCount: pendingCount,
            percent: progressPercent,
          ),
          const SizedBox(height: 20),

          // Tiêu đề & bộ lọc trạng thái nộp báo cáo
          _buildSubmissionsFilterHeader(
            totalCount: totalTargetCount,
            completedCount: completedCount,
            pendingCount: pendingCount,
          ),
          const SizedBox(height: 12),

          // Danh sách nhân viên và báo cáo minh chứng
          _buildSubmissionsList(
            targetMembers: targetMembers,
            submissions: filteredSubmissions,
            completedUserIds: completedUserIds,
          ),
        ],
      ),
    );
  }

  /// Thẻ tổng quan thông tin công việc
  Widget _buildTaskInfoCard(AssignedTask task) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges row (Wrap: nhiều nhãn tự xuống dòng thay vì tràn)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 6,
            children: [
              _buildStatusBadge(task.status),
              const SizedBox(width: 8),
              if (task.repeatDaily) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.repeat,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Lặp mỗi ngày',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (task.repeatDaysOfWeek.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.calendarSync,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(child: Text(
                        'Lặp thứ ${task.repeatDaysOfWeek.map((d) => d == 7 ? 'CN' : 'T${d + 1}').join(', ')} hàng tuần',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (task.requirePhoto)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.camera,
                        size: 13,
                        color: Color(0xFFD97706),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Bắt buộc ảnh minh chứng',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Tiêu đề
          Text(
            task.title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),

          // Mô tả
          if (task.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                task.description,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),

          // Thông tin người giao
          Row(
            children: [
              const Icon(LucideIcons.userRound,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Người giao: ',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Flexible(
                child: Text(
                  task.createdByName.isNotEmpty ? task.createdByName : 'Quản lý',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              RoleBadge(role: task.createdByRole, compact: true),
            ],
          ),
          const SizedBox(height: 6),

          // Thời gian tạo
          Row(
            children: [
              const Icon(LucideIcons.clock,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Tạo lúc: ${_formatDateTime(task.createdAt)}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Phạm vi giao việc
          Row(
            children: [
              Icon(
                task.isAllStore
                    ? LucideIcons.store
                    : (task.isDepartment
                        ? LucideIcons.building
                        : LucideIcons.users),
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Đối tượng: ',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: Text(
                  task.isAllStore
                      ? 'Toàn bộ cửa hàng'
                      : (task.isDepartment
                          ? 'Bộ phận ${task.targetDepartmentNames.isNotEmpty ? task.targetDepartmentNames.join(', ') : (task.targetDepartmentName ?? 'Bộ phận')} (${task.assignedNames.isNotEmpty ? task.assignedNames.length : task.assignedUserIds.length} người)'
                          : (task.assignedNames.isNotEmpty
                              ? task.assignedNames.join(', ')
                              : '${task.assignedUserIds.length} người')),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Thanh chọn lọc theo ngày thực hiện
  Widget _buildDateFilterBar(AssignedTask task) {
    final dates = task.executionDates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.calendar,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Lọc báo cáo theo ngày làm việc:',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                selected: _selectedWorkDate == null,
                label: Text(
                  'Tất cả các ngày (${dates.length})',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: _selectedWorkDate == null
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: _selectedWorkDate == null
                        ? Colors.white
                        : AppColors.textPrimary,
                  ),
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.cardSurface,
                showCheckmark: false,
                side: BorderSide(
                  color: _selectedWorkDate == null
                      ? AppColors.primary
                      : AppColors.border,
                ),
                onSelected: (_) {
                  setState(() {
                    _selectedWorkDate = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              for (final d in dates) ...[
                FilterChip(
                  selected: _selectedWorkDate == d,
                  label: Text(
                    _formatDateShort(d),
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: _selectedWorkDate == d
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _selectedWorkDate == d
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                  ),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.cardSurface,
                  showCheckmark: false,
                  side: BorderSide(
                    color: _selectedWorkDate == d
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedWorkDate = d;
                    });
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Thẻ tổng quan tiến độ
  Widget _buildProgressCard({
    required int totalCount,
    required int completedCount,
    required int pendingCount,
    required double percent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tiến độ nộp báo cáo',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${(percent * 100).toInt()}%',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: percent >= 1.0 ? AppColors.success : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                percent >= 1.0 ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.circleCheck,
                          size: 16, color: AppColors.success),
                      const SizedBox(width: 6),
                      Flexible(child: Text(
                        'Đã hoàn thành: ',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                      Text(
                        '$completedCount',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.clock,
                          size: 16, color: Colors.orange),
                      const SizedBox(width: 6),
                      Flexible(child: Text(
                        'Chưa nộp: ',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                      Text(
                        '$pendingCount',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tiêu đề section và bộ lọc Đã nộp / Chưa nộp
  Widget _buildSubmissionsFilterHeader({
    required int totalCount,
    required int completedCount,
    required int pendingCount,
  }) {
    // Wrap: màn hẹp thì bộ lọc tự xuống dòng dưới tiêu đề
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text(
          'Danh sách nhân sự ($totalCount)',
          style: GoogleFonts.beVietnamPro(
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        // Filter tabs
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'all',
              label: Text('Tất cả ($totalCount)',
                  style: GoogleFonts.beVietnamPro(fontSize: 11)),
            ),
            ButtonSegment(
              value: 'completed',
              label: Text('Đã xong ($completedCount)',
                  style: GoogleFonts.beVietnamPro(fontSize: 11)),
            ),
            ButtonSegment(
              value: 'pending',
              label: Text('Chưa nộp ($pendingCount)',
                  style: GoogleFonts.beVietnamPro(fontSize: 11)),
            ),
          ],
          selected: {_submissionFilter},
          onSelectionChanged: (set) {
            setState(() {
              _submissionFilter = set.first;
            });
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
        ),
      ],
    );
  }

  /// Danh sách chi tiết từng nhân viên
  Widget _buildSubmissionsList({
    required List<MemberModel> targetMembers,
    required List<TaskSubmission> submissions,
    required Set<String> completedUserIds,
  }) {
    // Map userId -> Submission
    final submissionMap = <String, TaskSubmission>{};
    for (final s in submissions) {
      submissionMap[s.userId] = s;
    }

    final filteredList = targetMembers.where((member) {
      final isCompleted = completedUserIds.contains(member.userId);
      if (_submissionFilter == 'completed') return isCompleted;
      if (_submissionFilter == 'pending') return !isCompleted;
      return true;
    }).toList();

    if (filteredList.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        child: Text(
          'Không có thành viên nào trong danh mục này',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: AppColors.textDisabled,
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final member = filteredList[index];
        final submission = submissionMap[member.userId];
        final isDone = submission != null && submission.isCompleted;

        return _buildMemberSubmissionCard(
          member: member,
          submission: submission,
          isDone: isDone,
        );
      },
    );
  }

  Widget _buildMemberSubmissionCard({
    required MemberModel member,
    required TaskSubmission? submission,
    required bool isDone,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.border.withValues(alpha: 0.8),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info: Avatar + Name + Role + Status badge
          Row(
            children: [
              AvatarWidget(
                name: member.name,
                avatarUrl: member.avatarUrl,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        RoleBadge(role: member.role, compact: true),
                      ],
                    ),
                    if (isDone && submission?.completedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Nộp lúc: ${_formatDateTime(submission!.completedAt!)}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Status Badge
              if (isDone)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.circleCheck,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        'Đã nộp',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.clock,
                          size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        'Chưa nộp',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Nội dung báo cáo văn bản
          if (isDone && (submission?.reportText.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.fileText,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Nội dung báo cáo:',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    submission!.reportText,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Thumbnail ảnh chụp minh chứng
          if (isDone && (submission?.photoUrls.isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            Text(
              'Ảnh chụp minh chứng (${submission!.photoUrls.length} ảnh):',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 85,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: submission.photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, pIndex) {
                  final photoUrl = submission.photoUrls[pIndex];

                  return GestureDetector(
                    onTap: () => _showImagePreviewDialog(
                      context,
                      photoUrl,
                      pIndex,
                      submission.photoUrls,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 85,
                        height: 85,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.border.withValues(alpha: 0.8),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Hero(
                          tag: 'task_photo_$photoUrl',
                          child: CachedNetworkImage(
                            imageUrl: photoUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.surface,
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
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.surface,
                              child: const Icon(
                                LucideIcons.imageOff,
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // Ghi chú khi chưa hoàn thành
          if (!isDone) ...[
            const SizedBox(height: 6),
            Text(
              'Nhân sự chưa gửi báo cáo hoàn thành cho công việc này.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textDisabled,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Lấy danh sách thành viên được áp dụng giao việc
  List<MemberModel> _getTargetMembers(
    AssignedTask task,
    List<MemberModel> activeMembers,
  ) {
    if (task.isAllStore) {
      return activeMembers;
    }

    if (task.isDepartment) {
      final workDate = _selectedWorkDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
      final weekStart = DepartmentUtils.getMondayOfWeek(workDate);
      final schedule = ref.watch(weekScheduleProvider(weekStart)).valueOrNull;
      final store = ref.watch(currentStoreProvider).valueOrNull;

      final deptMemberIds = DepartmentUtils.getUserIdsInDepartmentOnDate(
        dateStr: workDate,
        targetDeptId: task.targetDepartmentId,
        targetDeptName: task.targetDepartmentName,
        targetDeptIds: task.targetDepartmentIds,
        targetDeptNames: task.targetDepartmentNames,
        allMembers: activeMembers,
        schedule: schedule,
        storeDepartments: store?.departments,
      );

      final combinedIds = <String>{
        ...deptMemberIds,
        ...task.assignedUserIds,
      };

      final deptMembers = activeMembers.where((m) => combinedIds.contains(m.userId)).toList();
      if (deptMembers.isNotEmpty) return deptMembers;
    }

    // Nếu chỉ định cá nhân hoặc fallback
    final result = <MemberModel>[];
    for (int i = 0; i < task.assignedUserIds.length; i++) {
      final uid = task.assignedUserIds[i];
      final member = activeMembers.cast<MemberModel?>().firstWhere(
            (m) => m?.userId == uid,
            orElse: () => null,
          );

      if (member != null) {
        result.add(member);
      } else {
        // Fallback placeholder nếu member đã bị kick hoặc không có trong cache
        final fallbackName = i < task.assignedNames.length
            ? task.assignedNames[i]
            : 'Nhân viên';
        result.add(
          MemberModel(
            userId: uid,
            name: fallbackName,
            role: UserRole.employee,
            status: MemberStatus.active,
            employeeType: EmployeeType.fulltime,
            joinedAt: DateTime.now(),
          ),
        );
      }
    }
    return result;
  }

  Widget _buildStatusBadge(TaskStatus status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case TaskStatus.active:
        bg = AppColors.success.withValues(alpha: 0.12);
        fg = AppColors.success;
        label = 'Đang thực hiện';
        icon = LucideIcons.circlePlay;
        break;
      case TaskStatus.completed:
        bg = AppColors.managerAccent.withValues(alpha: 0.12);
        fg = AppColors.managerAccent;
        label = 'Đã hoàn thành';
        icon = LucideIcons.circleCheck;
        break;
      case TaskStatus.cancelled:
        bg = Colors.red.withValues(alpha: 0.12);
        fg = Colors.red;
        label = 'Đã hủy';
        icon = LucideIcons.circleX;
        break;
      case TaskStatus.archived:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey;
        label = 'Lưu trữ';
        icon = LucideIcons.archive;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(child: Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )),
        ],
      ),
    );
  }
}
