import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../models/task_assignment_model.dart';
import '../../store/providers/store_provider.dart';
import '../providers/task_provider.dart';
import 'create_task_dialog.dart';
import 'task_detail_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Màn hình Quản lý & Giao việc (Dành cho Chủ cửa hàng, Quản lý 1, Quản lý 2).
/// Hiển thị danh sách các công việc đã giao, lọc theo ngày thực hiện,
/// cho phép hủy / xóa việc và mở màn hình chi tiết báo cáo.
class TaskManagementScreen extends ConsumerStatefulWidget {
  const TaskManagementScreen({super.key});

  @override
  ConsumerState<TaskManagementScreen> createState() =>
      _TaskManagementScreenState();
}

class _TaskManagementScreenState extends ConsumerState<TaskManagementScreen> {
  // Lọc theo ngày (mặc định hôm nay, null nghĩa là xem tất cả)
  String? _selectedDate;

  // Lọc theo trạng thái task: null = Tất cả
  TaskStatus? _selectedStatus;

  // Tìm kiếm từ khóa
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    // Mặc định lọc theo ngày hôm nay
    _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDateIso(DateTime dt) {
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  String _formatDateShortDisplay(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final check = DateTime(dt.year, dt.month, dt.day);

      final diffDays = check.difference(today).inDays;
      if (diffDays == 0) {
        return 'Hôm nay (${DateFormat('dd/MM').format(dt)})';
      } else if (diffDays == 1) {
        return 'Ngày mai (${DateFormat('dd/MM').format(dt)})';
      } else if (diffDays == 2) {
        return 'Ngày kia (${DateFormat('dd/MM').format(dt)})';
      } else {
        final weekdayName = _weekdayName(dt.weekday);
        return '$weekdayName (${DateFormat('dd/MM').format(dt)})';
      }
    } catch (_) {
      return isoDate;
    }
  }

  String _weekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Thứ 2';
      case DateTime.tuesday:
        return 'Thứ 3';
      case DateTime.wednesday:
        return 'Thứ 4';
      case DateTime.thursday:
        return 'Thứ 5';
      case DateTime.friday:
        return 'Thứ 6';
      case DateTime.saturday:
        return 'Thứ 7';
      case DateTime.sunday:
        return 'CN';
      default:
        return '';
    }
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
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

    if (picked != null) {
      setState(() {
        _selectedDate = _formatDateIso(picked);
      });
    }
  }

  Future<void> _openCreateTaskDialog() async {
    final result = await CreateTaskDialog.show(context);
    if (result == true && mounted) {
      // Refresh hoặc thông báo nếu cần
    }
  }

  Future<void> _updateStatus(AssignedTask task, TaskStatus newStatus) async {
    final isCancel = newStatus == TaskStatus.cancelled;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isCancel ? 'Hủy công việc' : 'Hoàn thành công việc',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: Text(
          isCancel
              ? 'Bạn có chắc chắn muốn hủy công việc "${task.title}" không?'
              : 'Đánh dấu công việc "${task.title}" đã hoàn thành?',
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
              backgroundColor: isCancel ? AppColors.danger : AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(
              isCancel ? 'Hủy việc' : 'Đồng ý',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final repo = ref.read(taskRepositoryProvider);
        await repo.updateTask(task.copyWith(status: newStatus));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isCancel
                    ? 'Đã hủy công việc thành công!'
                    : 'Đã hoàn thành công việc!',
                style: GoogleFonts.beVietnamPro(),
              ),
              backgroundColor:
                  isCancel ? AppColors.textPrimary : AppColors.success,
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

  Future<void> _deleteTask(AssignedTask task) async {
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
          'Hành động này sẽ xóa hoàn toàn công việc "${task.title}" và toàn bộ báo cáo liên quan.',
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
        await repo.deleteTask(task.storeId, task.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xóa công việc thành công!',
                  style: GoogleFonts.beVietnamPro()),
              backgroundColor: AppColors.textPrimary,
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

  @override
  Widget build(BuildContext context) {
    final storeId = ref.watch(currentStoreIdProvider) ?? '';
    final tasksAsync = ref.watch(storeTasksProvider(storeId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tiêu đề, mô tả...',
                  hintStyle: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    color: AppColors.textDisabled,
                  ),
                  border: InputBorder.none,
                ),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14.5,
                  color: AppColors.textPrimary,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim().toLowerCase();
                  });
                },
              )
            : Text(
                'Quản lý công việc',
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
          IconButton(
            icon: Icon(_isSearching ? LucideIcons.x : LucideIcons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.listPlus, color: AppColors.primary),
            tooltip: 'Giao việc mới',
            onPressed: _openCreateTaskDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateTaskDialog,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(LucideIcons.listPlus, size: 20),
        label: Text(
          'Giao việc mới',
          style: GoogleFonts.beVietnamPro(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter section: Ngày & Trạng thái
          Container(
            color: AppColors.cardSurface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Thanh chọn ngày lọc
                _buildDateFilterRow(),
                const SizedBox(height: 10),

                // 2. Bộ lọc trạng thái
                _buildStatusFilterRow(),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Danh sách công việc
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (err, stack) => Center(
                child: EmptyState(
                  icon: LucideIcons.circleAlert,
                  message: 'Lỗi tải danh sách công việc',
                  subtitle: err.toString(),
                ),
              ),
              data: (allTasks) {
                // Áp dụng bộ lọc ngày, trạng thái, tìm kiếm
                final filteredTasks = allTasks.where((task) {
                  // Lọc theo ngày
                  if (_selectedDate != null &&
                      !task.executionDates.contains(_selectedDate)) {
                    return false;
                  }
                  // Lọc theo trạng thái
                  if (_selectedStatus != null &&
                      task.status != _selectedStatus) {
                    return false;
                  }
                  // Lọc theo từ khóa tìm kiếm
                  if (_searchQuery.isNotEmpty) {
                    final titleMatch =
                        task.title.toLowerCase().contains(_searchQuery);
                    final descMatch =
                        task.description.toLowerCase().contains(_searchQuery);
                    final creatorMatch =
                        task.createdByName.toLowerCase().contains(_searchQuery);
                    if (!titleMatch && !descMatch && !creatorMatch) {
                      return false;
                    }
                  }
                  return true;
                }).toList();

                if (filteredTasks.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      child: EmptyState(
                        icon: LucideIcons.clipboardList,
                        message: _selectedDate != null
                            ? 'Không có công việc nào trong ngày này'
                            : 'Chưa có công việc nào được giao',
                        subtitle:
                            'Bấm nút "Giao việc mới" để phân công công việc cho nhân sự.',
                        actionLabel: 'Giao việc ngay',
                        onAction: _openCreateTaskDialog,
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    ref.invalidate(storeTasksProvider(storeId));
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
                    itemCount: filteredTasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];
                      return _buildTaskCard(task);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Thanh chọn ngày lọc linh hoạt
  Widget _buildDateFilterRow() {
    final now = DateTime.now();
    final today = _formatDateIso(now);
    final tomorrow = _formatDateIso(now.add(const Duration(days: 1)));
    final dayAfterTomorrow = _formatDateIso(now.add(const Duration(days: 2)));

    final quickDays = [
      {'label': 'Hôm nay', 'iso': today},
      {'label': 'Ngày mai', 'iso': tomorrow},
      {'label': 'Ngày kia', 'iso': dayAfterTomorrow},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Nút "Tất cả các ngày"
          FilterChip(
            selected: _selectedDate == null,
            label: Text(
              'Tất cả',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: _selectedDate == null
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: _selectedDate == null
                    ? Colors.white
                    : AppColors.textPrimary,
              ),
            ),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            showCheckmark: false,
            side: BorderSide(
              color: _selectedDate == null
                  ? AppColors.primary
                  : AppColors.border,
            ),
            onSelected: (_) {
              setState(() {
                _selectedDate = null;
              });
            },
          ),
          const SizedBox(width: 6),

          // Các nút ngày nhanh
          for (final item in quickDays) ...[
            FilterChip(
              selected: _selectedDate == item['iso'],
              label: Text(
                _formatDateShortDisplay(item['iso']!),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: _selectedDate == item['iso']
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: _selectedDate == item['iso']
                      ? Colors.white
                      : AppColors.textPrimary,
                ),
              ),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surface,
              showCheckmark: false,
              side: BorderSide(
                color: _selectedDate == item['iso']
                    ? AppColors.primary
                    : AppColors.border,
              ),
              onSelected: (_) {
                setState(() {
                  _selectedDate = item['iso'];
                });
              },
            ),
            const SizedBox(width: 6),
          ],

          // Nếu có ngày tùy chọn ngoài danh sách nhanh
          if (_selectedDate != null &&
              !quickDays.any((element) => element['iso'] == _selectedDate)) ...[
            FilterChip(
              selected: true,
              label: Text(
                _formatDateShortDisplay(_selectedDate!),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              selectedColor: AppColors.primary,
              showCheckmark: false,
              side: const BorderSide(color: AppColors.primary),
              onSelected: (_) {},
            ),
            const SizedBox(width: 6),
          ],

          // Nút chọn ngày khác qua DatePicker
          ActionChip(
            avatar: const Icon(
              LucideIcons.calendarDays,
              size: 15,
              color: AppColors.primary,
            ),
            label: Text(
              'Chọn ngày...',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            backgroundColor: AppColors.primary.withValues(alpha: 0.08),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
            onPressed: _pickCustomDate,
          ),
        ],
      ),
    );
  }

  /// Bộ lọc trạng thái: Tất cả, Đang làm, Hoàn thành, Đã hủy
  Widget _buildStatusFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStatusFilterChip(
            label: 'Tất cả trạng thái',
            status: null,
            isSelected: _selectedStatus == null,
          ),
          const SizedBox(width: 6),
          _buildStatusFilterChip(
            label: 'Đang làm',
            status: TaskStatus.active,
            isSelected: _selectedStatus == TaskStatus.active,
          ),
          const SizedBox(width: 6),
          _buildStatusFilterChip(
            label: 'Đã hoàn thành',
            status: TaskStatus.completed,
            isSelected: _selectedStatus == TaskStatus.completed,
          ),
          const SizedBox(width: 6),
          _buildStatusFilterChip(
            label: 'Đã hủy',
            status: TaskStatus.cancelled,
            isSelected: _selectedStatus == TaskStatus.cancelled,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip({
    required String label,
    required TaskStatus? status,
    required bool isSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary.withValues(alpha: 0.12),
      backgroundColor: AppColors.surface,
      side: BorderSide(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.4)
            : AppColors.border.withValues(alpha: 0.6),
      ),
      onSelected: (_) {
        setState(() {
          _selectedStatus = status;
        });
      },
    );
  }

  /// Thẻ công việc chi tiết
  Widget _buildTaskCard(AssignedTask task) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TaskDetailScreen(task: task),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Status badge + Repeat daily + Photo requirement + Menu actions
                Row(
                  children: [
                    // Nhãn tự xuống dòng khi nhiều, menu luôn ở bên phải
                    Expanded(
                      child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 6,
                    children: [
                    _buildStatusBadge(task.status),
                    const SizedBox(width: 8),
                    if (task.repeatDaily) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
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
                      const SizedBox(width: 6),
                    ] else if (task.repeatDaysOfWeek.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
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
                              'Thứ ${task.repeatDaysOfWeek.map((d) => d == 7 ? 'CN' : 'T${d + 1}').join(', ')}',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            )),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (task.requirePhoto)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
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
                              'Cần ảnh chụp',
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
                    ),
                    // Menu actions
                    PopupMenuButton<String>(
                      icon: const Icon(
                        LucideIcons.ellipsisVertical,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (val) {
                        if (val == 'detail') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TaskDetailScreen(task: task),
                            ),
                          );
                        } else if (val == 'edit') {
                          CreateTaskDialog.show(context, taskToEdit: task);
                        } else if (val == 'complete') {
                          _updateStatus(task, TaskStatus.completed);
                        } else if (val == 'cancel') {
                          _updateStatus(task, TaskStatus.cancelled);
                        } else if (val == 'delete') {
                          _deleteTask(task);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'detail',
                          child: Row(
                            children: [
                              const Icon(LucideIcons.eye,
                                  size: 18, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Text('Xem chi tiết',
                                  style: GoogleFonts.beVietnamPro(
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(LucideIcons.pencil,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text('Chỉnh sửa công việc',
                                  style: GoogleFonts.beVietnamPro(
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                        if (task.status == TaskStatus.active) ...[
                          PopupMenuItem(
                            value: 'complete',
                            child: Row(
                              children: [
                                const Icon(LucideIcons.circleCheck,
                                    size: 18, color: AppColors.success),
                                const SizedBox(width: 8),
                                Text('Đánh dấu hoàn thành',
                                    style: GoogleFonts.beVietnamPro(
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'cancel',
                            child: Row(
                              children: [
                                const Icon(LucideIcons.circleX,
                                    size: 18, color: Colors.orange),
                                const SizedBox(width: 8),
                                Text('Hủy việc',
                                    style: GoogleFonts.beVietnamPro(
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(LucideIcons.trash2,
                                  size: 18, color: AppColors.danger),
                              const SizedBox(width: 8),
                              Text('Xóa vĩnh viễn',
                                  style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      color: AppColors.danger)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Tiêu đề
                Text(
                  task.title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),

                // Mô tả tóm tắt (nếu có)
                if (task.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.divider),
                const SizedBox(height: 10),

                // Metadata Rows
                // 1. Người giao việc
                Row(
                  children: [
                    const Icon(LucideIcons.mapPin,
                        size: 15, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Người giao: ',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        task.createdByName.isNotEmpty
                            ? task.createdByName
                            : 'Quản lý',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
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

                // 2. Đối tượng nhận việc
                Row(
                  children: [
                    Icon(
                      task.isAllStore
                          ? LucideIcons.store
                          : (task.isDepartment
                              ? LucideIcons.building
                              : LucideIcons.users),
                      size: 15,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Đối tượng: ',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        task.isAllStore
                            ? 'Toàn bộ cửa hàng'
                            : (task.isDepartment
                                ? 'Bộ phận ${task.targetDepartmentNames.isNotEmpty ? task.targetDepartmentNames.join(', ') : (task.targetDepartmentName ?? 'Bộ phận')} (Tự động theo ca/ngày)'
                                : (task.assignedNames.isNotEmpty
                                    ? '${task.assignedNames.length} người (${task.assignedNames.take(2).join(', ')}${task.assignedNames.length > 2 ? '...' : ''})'
                                    : '${task.assignedUserIds.length} người')),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // 3. Ngày thực hiện
                Row(
                  children: [
                    const Icon(LucideIcons.calendarClock,
                        size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Ngày làm: ',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        task.repeatDaily
                            ? 'Lặp lại mỗi ngày'
                            : (task.repeatDaysOfWeek.isNotEmpty
                                ? 'Lặp thứ ${task.repeatDaysOfWeek.map((d) => d == 7 ? 'CN' : 'T${d + 1}').join(', ')} hàng tuần'
                                : (task.executionDates.isNotEmpty
                                    ? task.executionDates
                                        .map((d) => _formatDateShortDisplay(d))
                                        .join(', ')
                                    : 'Chưa đặt ngày')),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      LucideIcons.chevronRight,
                      size: 13,
                      color: AppColors.textDisabled,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Flexible(child: Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
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
