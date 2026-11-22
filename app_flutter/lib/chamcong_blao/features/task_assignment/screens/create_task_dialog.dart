import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../core/widgets/role_badge.dart';
import '../../../models/member_model.dart';
import '../../../models/store_model.dart';
import '../../../models/task_assignment_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../store/providers/store_provider.dart';
import '../providers/task_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Modal / Dialog tạo và giao việc mới cho nhân viên cửa hàng.
/// Dành cho Chủ cửa hàng (Owner), Quản lý 1 (Manager 1), Quản lý 2 (Manager 2).
class CreateTaskDialog extends ConsumerStatefulWidget {
  final AssignedTask? taskToEdit;
  const CreateTaskDialog({super.key, this.taskToEdit});

  /// Helper mở modal bottom sheet thuận tiện từ bất kỳ màn hình nào
  static Future<bool?> show(BuildContext context, {AssignedTask? taskToEdit}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateTaskDialog(taskToEdit: taskToEdit),
    );
  }

  @override
  ConsumerState<CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends ConsumerState<CreateTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _memberSearchController = TextEditingController();

  // Danh sách các ngày thực hiện được chọn (YYYY-MM-DD)
  final Set<String> _selectedDates = {};

  // Chế độ lặp lại: 0: Ngày cụ thể, 1: Lặp mỗi ngày, 2: Lặp theo thứ hàng tuần
  int _repeatMode = 0;
  final Set<int> _selectedDaysOfWeek = {}; // 1 = T2 ... 7 = CN

  // Đối tượng nhận việc
  TaskTargetType _targetType = TaskTargetType.allStore;

  // Bộ phận được chọn khi targetType == department (hỗ trợ chọn nhiều bộ phận)
  final Set<String> _selectedDepartmentIds = {};

  // Danh sách ID thành viên được chọn khi targetType == individual
  final Set<String> _selectedMemberIds = {};

  // Yêu cầu ảnh chụp minh chứng
  bool _requirePhoto = false;

  // Trạng thái công việc (dùng khi chỉnh sửa)
  TaskStatus _status = TaskStatus.active;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.taskToEdit != null) {
      final t = widget.taskToEdit!;
      _titleController.text = t.title;
      _descController.text = t.description;
      _selectedDates.addAll(t.executionDates);
      _selectedDaysOfWeek.addAll(t.repeatDaysOfWeek);
      if (t.repeatDaily) {
        _repeatMode = 1;
      } else if (t.repeatDaysOfWeek.isNotEmpty) {
        _repeatMode = 2;
      } else {
        _repeatMode = 0;
      }
      _targetType = t.targetType;
      if (t.targetDepartmentIds.isNotEmpty) {
        _selectedDepartmentIds.addAll(t.targetDepartmentIds);
      } else if (t.targetDepartmentId != null && t.targetDepartmentId!.isNotEmpty) {
        _selectedDepartmentIds.add(t.targetDepartmentId!);
      }
      _selectedMemberIds.addAll(t.assignedUserIds);
      _requirePhoto = t.requirePhoto;
      _status = t.status;
    } else {
      // Mặc định chọn ngày hôm nay
      final today = _formatDateIso(DateTime.now());
      _selectedDates.add(today);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  String _formatDateIso(DateTime dt) {
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  String _formatDateDisplay(String isoDate) {
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
        return '$weekdayName, ${DateFormat('dd/MM/yyyy').format(dt)}';
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
        return 'Chủ Nhật';
      default:
        return '';
    }
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
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
      final iso = _formatDateIso(picked);
      setState(() {
        _selectedDates.add(iso);
        _errorMessage = null;
      });
    }
  }

  Future<void> _submitTask() async {
    if (_isSubmitting) return;

    setState(() {
      _errorMessage = null;
    });

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (_selectedDates.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng chọn ít nhất một ngày thực hiện!';
      });
      return;
    }

    if (_targetType == TaskTargetType.individual && _selectedMemberIds.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng chọn ít nhất một người nhận việc!';
      });
      return;
    }

    if (_targetType == TaskTargetType.department && _selectedDepartmentIds.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng chọn ít nhất một bộ phận nhận việc!';
      });
      return;
    }

    final isRepeatDaily = _repeatMode == 1;
    final isRepeatDaysOfWeek = _repeatMode == 2;
    final daysOfWeekList = isRepeatDaysOfWeek ? (_selectedDaysOfWeek.toList()..sort()) : <int>[];

    if (_repeatMode == 0 && _selectedDates.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng chọn ít nhất 1 ngày thực hiện!';
      });
      return;
    }
    if (isRepeatDaysOfWeek && daysOfWeekList.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng chọn ít nhất một thứ trong tuần để lặp lại!';
      });
      return;
    }

    final storeId = ref.read(currentStoreIdProvider);
    if (storeId == null || storeId.isEmpty) {
      setState(() {
        _errorMessage = 'Không xác định được cửa hàng hiện tại!';
      });
      return;
    }

    final currentMember = ref.read(currentMemberProvider);
    final currentUser = ref.read(currentUserProvider).valueOrNull;

    final creatorId = currentMember?.userId ?? currentUser?.id ?? '';
    final creatorName = currentMember?.name ?? currentUser?.name ?? 'Quản lý';
    final creatorRole = currentMember?.role ?? UserRole.manager1;

    final currentStore = ref.read(currentStoreProvider).valueOrNull;
    final departments = currentStore?.departments ?? const <DepartmentDefinition>[];

    final selectedDeptNames = <String>[];
    for (final dId in _selectedDepartmentIds) {
      final d = departments.cast<DepartmentDefinition?>().firstWhere(
        (element) => element?.id == dId,
        orElse: () => null,
      );
      if (d != null) selectedDeptNames.add(d.name);
    }

    // Lấy thành viên được giao việc
    final allMembers = ref.read(activeMembersProvider);
    final List<String> assignedUids;
    final List<String> assignedNames;

    if (_targetType == TaskTargetType.allStore) {
      assignedUids = const [];
      assignedNames = const [];
    } else if (_targetType == TaskTargetType.department) {
      final deptMembers = allMembers.where((m) {
        if (m.department == null || m.department!.trim().isEmpty) return false;
        final mDept = m.department!.trim().toLowerCase();
        return _selectedDepartmentIds.any((dId) {
          final d = departments.cast<DepartmentDefinition?>().firstWhere(
            (element) => element?.id == dId,
            orElse: () => null,
          );
          if (d == null) return false;
          final sId = d.id.trim().toLowerCase();
          final sName = d.name.trim().toLowerCase();
          final sShort = d.shortName.trim().toLowerCase();
          return mDept == sId || mDept == sName || (sShort.isNotEmpty && mDept == sShort);
        });
      }).toList();

      final combinedIds = <String>{
        ...deptMembers.map((m) => m.userId),
        ..._selectedMemberIds,
      }.toList();

      assignedUids = combinedIds;
      assignedNames = combinedIds.map((uid) {
        final m = allMembers.cast<MemberModel?>().firstWhere(
              (element) => element?.userId == uid,
              orElse: () => null,
            );
        return m?.name ?? uid;
      }).toList();
    } else {
      final selectedNames = <String>[];
      for (final id in _selectedMemberIds) {
        final m = allMembers.cast<MemberModel?>().firstWhere(
              (element) => element?.userId == id,
              orElse: () => null,
            );
        if (m != null) {
          selectedNames.add(m.name);
        } else {
          selectedNames.add('Thành viên');
        }
      }
      assignedUids = _selectedMemberIds.toList();
      assignedNames = selectedNames;
    }

    final sortedDates = <String>[];
    if (isRepeatDaysOfWeek) {
      final currNow = DateTime.now();
      for (int i = 0; i < 60; i++) {
        final dt = currNow.add(Duration(days: i));
        if (daysOfWeekList.contains(dt.weekday)) {
          sortedDates.add(_formatDateIso(dt));
        }
      }
    } else if (isRepeatDaily) {
      final currNow = DateTime.now();
      for (int i = 0; i < 60; i++) {
        sortedDates.add(_formatDateIso(currNow.add(Duration(days: i))));
      }
    } else {
      sortedDates.addAll(_selectedDates.toList()..sort());
    }

    final task = AssignedTask(
      id: '',
      storeId: storeId,
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      createdBy: creatorId,
      createdByName: creatorName,
      createdByRole: creatorRole,
      targetType: _targetType,
      targetDepartmentId: _targetType == TaskTargetType.department && _selectedDepartmentIds.isNotEmpty ? _selectedDepartmentIds.first : null,
      targetDepartmentName: _targetType == TaskTargetType.department && selectedDeptNames.isNotEmpty ? selectedDeptNames.first : null,
      targetDepartmentIds: _targetType == TaskTargetType.department ? _selectedDepartmentIds.toList() : const [],
      targetDepartmentNames: _targetType == TaskTargetType.department ? selectedDeptNames : const [],
      assignedUserIds: assignedUids,
      assignedNames: assignedNames,
      executionDates: sortedDates,
      repeatDaily: isRepeatDaily,
      repeatDaysOfWeek: daysOfWeekList,
      requirePhoto: _requirePhoto,
      status: TaskStatus.active,
      createdAt: DateTime.now(),
    );

    setState(() {
      _isSubmitting = true;
    });

    try {
      final repo = ref.read(taskRepositoryProvider);
      if (widget.taskToEdit != null) {
        final updatedTask = AssignedTask(
          id: widget.taskToEdit!.id,
          storeId: widget.taskToEdit!.storeId,
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          createdBy: widget.taskToEdit!.createdBy,
          createdByName: widget.taskToEdit!.createdByName,
          createdByRole: widget.taskToEdit!.createdByRole,
          targetType: _targetType,
          targetDepartmentId: _targetType == TaskTargetType.department && _selectedDepartmentIds.isNotEmpty ? _selectedDepartmentIds.first : null,
          targetDepartmentName: _targetType == TaskTargetType.department && selectedDeptNames.isNotEmpty ? selectedDeptNames.first : null,
          targetDepartmentIds: _targetType == TaskTargetType.department ? _selectedDepartmentIds.toList() : const [],
          targetDepartmentNames: _targetType == TaskTargetType.department ? selectedDeptNames : const [],
          assignedUserIds: assignedUids,
          assignedNames: assignedNames,
          executionDates: sortedDates,
          repeatDaily: isRepeatDaily,
          repeatDaysOfWeek: daysOfWeekList,
          requirePhoto: _requirePhoto,
          status: _status,
          createdAt: widget.taskToEdit!.createdAt,
          updatedAt: DateTime.now(),
        );
        await repo.updateTask(updatedTask);
      } else {
        await repo.createTask(task);
      }

      // Ép làm mới các provider để giao diện cập nhật ngay lập tức
      ref.invalidate(todayUserTasksProvider);
      ref.invalidate(unfinishedUserTasksProvider);
      ref.invalidate(storeTasksProvider(storeId));
      ref.invalidate(storeTasksFilteredProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.circleCheck, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.taskToEdit != null
                        ? 'Đã cập nhật công việc thành công!'
                        : 'Đã giao công việc thành công!',
                    style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = widget.taskToEdit != null
              ? 'Lỗi cập nhật công việc: $e'
              : 'Lỗi tạo công việc: $e';
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMembers = ref.watch(activeMembersProvider);
    final currentStore = ref.watch(currentStoreProvider).valueOrNull;
    final departments = currentStore?.departments ?? const <DepartmentDefinition>[];
    final viewInsets = MediaQuery.of(context).viewInsets;
    final size = MediaQuery.of(context).size;

    return Container(
      constraints: BoxConstraints(
        maxHeight: size.height * 0.9,
      ),
      margin: EdgeInsets.only(bottom: viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.taskToEdit != null
                        ? LucideIcons.notebookPen
                        : LucideIcons.clipboardPlus,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.taskToEdit != null
                            ? 'Chỉnh sửa công việc'
                            : 'Giao việc mới',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.taskToEdit != null
                            ? 'Cập nhật nội dung & đối tượng nhận việc'
                            : 'Chủ & Quản lý phân công công việc',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => FocusScope.of(context).unfocus(),
                  icon: const Icon(LucideIcons.keyboardOff),
                  tooltip: 'Ẩn bàn phím',
                  splashRadius: 20,
                  color: AppColors.textSecondary,
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(LucideIcons.x),
                  splashRadius: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Form content
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.circleAlert,
                              color: AppColors.danger,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 1. Tiêu đề công việc
                    Text(
                      'Tiêu đề công việc *',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: 'VD: Kiểm tra tồn kho cuối ngày, Vệ sinh máy pha...',
                        hintStyle: GoogleFonts.beVietnamPro(
                          fontSize: 13.5,
                          color: AppColors.textDisabled,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        prefixIcon: const Icon(
                          LucideIcons.type,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Vui lòng nhập tiêu đề công việc';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    // 2. Mô tả chi tiết
                    Text(
                      'Mô tả chi tiết',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Mô tả cụ thể các việc cần làm, tiêu chí hoàn thành...',
                        hintStyle: GoogleFonts.beVietnamPro(
                          fontSize: 13.5,
                          color: AppColors.textDisabled,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 3. Chọn ngày thực hiện (executionDates)
                    _buildExecutionDatesSection(),
                    const SizedBox(height: 20),

                    // 4. Chọn đối tượng nhận việc
                    _buildTargetSelectionSection(activeMembers, departments),
                    const SizedBox(height: 20),

                    // 5. Switch Yêu cầu ảnh minh chứng
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (_requirePhoto ? AppColors.warning : AppColors.textDisabled)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              LucideIcons.camera,
                              color: _requirePhoto
                                  ? const Color(0xFFD97706)
                                  : AppColors.textSecondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bắt buộc chụp ảnh minh chứng',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Nhân viên phải chụp ảnh kết quả khi báo cáo hoàn thành',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _requirePhoto,
                            activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) {
                              setState(() {
                                _requirePhoto = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    if (widget.taskToEdit != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Trạng thái công việc',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          TaskStatus.active,
                          TaskStatus.completed,
                          TaskStatus.cancelled,
                          TaskStatus.archived,
                        ].map((s) {
                          final isSelected = _status == s;
                          return ChoiceChip(
                            label: Text(
                              s.label,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: s == TaskStatus.active
                                ? AppColors.primary
                                : (s == TaskStatus.completed
                                    ? AppColors.success
                                    : (s == TaskStatus.cancelled
                                        ? AppColors.danger
                                        : AppColors.textSecondary)),
                            backgroundColor: AppColors.surface,
                            showCheckmark: false,
                            onSelected: (_) {
                              setState(() {
                                _status = s;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Nút Tạo công việc / Lưu thay đổi
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitTask,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.5),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.taskToEdit != null
                                        ? LucideIcons.save
                                        : LucideIcons.listPlus,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(
                                    widget.taskToEdit != null
                                        ? 'Lưu thay đổi'
                                        : 'Giao công việc',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )),
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
      ],
    ),
  );
}

  Widget _buildPresetChip(String label, List<int> days) {
    final isMatching = days.length == _selectedDaysOfWeek.length &&
        days.every((d) => _selectedDaysOfWeek.contains(d));
    return ActionChip(
      label: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 11,
          fontWeight: isMatching ? FontWeight.w600 : FontWeight.normal,
          color: isMatching ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
      backgroundColor: isMatching
          ? AppColors.primary.withValues(alpha: 0.1)
          : AppColors.cardSurface,
      side: BorderSide(
        color: isMatching ? AppColors.primary : AppColors.border,
      ),
      onPressed: () {
        setState(() {
          _selectedDaysOfWeek.clear();
          _selectedDaysOfWeek.addAll(days);
          _errorMessage = null;
        });
      },
    );
  }

  String _formatDaysOfWeekNames(Set<int> days) {
    final sorted = days.toList()..sort();
    return sorted.map((d) => d == 7 ? 'Chủ Nhật' : 'Thứ $d').join(', ');
  }

  /// Section chọn ngày thực hiện linh hoạt, lặp mỗi ngày hoặc lặp theo thứ hàng tuần
  Widget _buildExecutionDatesSection() {
    final now = DateTime.now();
    final today = _formatDateIso(now);
    final tomorrow = _formatDateIso(now.add(const Duration(days: 1)));
    final dayAfterTomorrow = _formatDateIso(now.add(const Duration(days: 2)));

    // 4 ngày kế tiếp để chọn nhanh
    final upcomingDays = List.generate(4, (i) {
      final dt = now.add(Duration(days: i + 3));
      return dt;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thời gian thực hiện *',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // 3 chế độ: Ngày cụ thể, Lặp mỗi ngày, Lặp theo thứ hàng tuần
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.8),
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _buildSegmentButton(
                  title: 'Ngày cụ thể',
                  icon: LucideIcons.calendar,
                  isSelected: _repeatMode == 0,
                  onTap: () {
                    setState(() {
                      _repeatMode = 0;
                      if (_selectedDates.isEmpty) {
                        _selectedDates.add(_formatDateIso(DateTime.now()));
                      }
                      _errorMessage = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildSegmentButton(
                  title: 'Lặp mỗi ngày',
                  icon: LucideIcons.repeat,
                  isSelected: _repeatMode == 1,
                  onTap: () {
                    setState(() {
                      _repeatMode = 1;
                      _errorMessage = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildSegmentButton(
                  title: 'Lặp theo thứ',
                  icon: LucideIcons.calendarSync,
                  isSelected: _repeatMode == 2,
                  onTap: () {
                    setState(() {
                      _repeatMode = 2;
                      if (_selectedDaysOfWeek.isEmpty) {
                        _selectedDaysOfWeek.add(DateTime.now().weekday);
                      }
                      _errorMessage = null;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Hiển thị nội dung theo từng chế độ:
        if (_repeatMode == 1) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.info,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đã bật lặp mỗi ngày: Công việc sẽ tự động xuất hiện trong ca làm việc của nhân viên hàng ngày kể từ hôm nay.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (_repeatMode == 2) ...[
          // Chế độ lặp lại theo thứ hàng tuần
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: Text(
                      'Chọn các thứ trong tuần lặp lại:',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    )),
                    Text(
                      '(${_selectedDaysOfWeek.length}/7 thứ)',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 7 nút thứ T2 -> CN
                Row(
                  children: [
                    for (int day = 1; day <= 7; day++) ...[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_selectedDaysOfWeek.contains(day)) {
                                  _selectedDaysOfWeek.remove(day);
                                } else {
                                  _selectedDaysOfWeek.add(day);
                                }
                                _errorMessage = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: _selectedDaysOfWeek.contains(day)
                                    ? AppColors.primary
                                    : AppColors.cardSurface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _selectedDaysOfWeek.contains(day)
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: _selectedDaysOfWeek.contains(day) ? 1.5 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                day == 7 ? 'CN' : 'T$day',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12.5,
                                  fontWeight: _selectedDaysOfWeek.contains(day)
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: _selectedDaysOfWeek.contains(day)
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),

                // Nút chọn nhanh (Presets)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildPresetChip('T2, T4, T6', [1, 3, 5]),
                    _buildPresetChip('T3, T5, T7', [2, 4, 6]),
                    _buildPresetChip('Cuối tuần (T7, CN)', [6, 7]),
                    _buildPresetChip('T2 - T6', [1, 2, 3, 4, 5]),
                    _buildPresetChip('Cả tuần', [1, 2, 3, 4, 5, 6, 7]),
                  ],
                ),
                const SizedBox(height: 10),

                // Thông tin tóm tắt
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.circleCheck,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedDaysOfWeek.isEmpty
                              ? 'Vui lòng chọn ít nhất một thứ để lặp lại'
                              : 'Tự động lặp lại vào: ${_formatDaysOfWeekNames(_selectedDaysOfWeek)} hàng tuần.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Row(
            children: [
              Text(
                'Ngày thực hiện *',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${_selectedDates.length} ngày đã chọn)',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Chọn một hoặc nhiều ngày trong tương lai task này cần làm:',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          // Quick add buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickDateChip(
                  label: 'Hôm nay',
                  isoDate: today,
                  isSelected: _selectedDates.contains(today),
                ),
                const SizedBox(width: 6),
                _buildQuickDateChip(
                  label: 'Ngày mai',
                  isoDate: tomorrow,
                  isSelected: _selectedDates.contains(tomorrow),
                ),
                const SizedBox(width: 6),
                _buildQuickDateChip(
                  label: 'Ngày kia',
                  isoDate: dayAfterTomorrow,
                  isSelected: _selectedDates.contains(dayAfterTomorrow),
                ),
                const SizedBox(width: 6),
                for (final dt in upcomingDays) ...[
                  _buildQuickDateChip(
                    label: '${_weekdayName(dt.weekday)} (${DateFormat('dd/MM').format(dt)})',
                    isoDate: _formatDateIso(dt),
                    isSelected: _selectedDates.contains(_formatDateIso(dt)),
                  ),
                  const SizedBox(width: 6),
                ],
                ActionChip(
                  avatar: const Icon(
                    LucideIcons.calendarDays,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    '+ Chọn ngày khác',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                  onPressed: _pickCustomDate,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Danh sách Chips các ngày đã chọn
          if (_selectedDates.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.7),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (_selectedDates.toList()..sort()).map((iso) {
                  return Chip(
                    label: Text(
                      _formatDateDisplay(iso),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                    deleteIcon: const Icon(
                      LucideIcons.x,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    onDeleted: () {
                      setState(() {
                        _selectedDates.remove(iso);
                      });
                    },
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                }).toList(),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.info, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Flexible(child: Text(
                    'Chưa chọn ngày nào. Vui lòng bấm chọn ngày phía trên.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      color: Colors.deepOrange,
                    ),
                  )),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildQuickDateChip({
    required String label,
    required String isoDate,
    required bool isSelected,
  }) {
    return FilterChip(
      selected: isSelected,
      label: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        ),
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      checkmarkColor: Colors.white,
      showCheckmark: false,
      side: BorderSide(
        color: isSelected
            ? AppColors.primary
            : AppColors.border.withValues(alpha: 0.8),
      ),
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedDates.add(isoDate);
          } else {
            _selectedDates.remove(isoDate);
          }
          _errorMessage = null;
        });
      },
    );
  }

  /// Section chọn đối tượng nhận việc: Toàn cửa hàng, Theo bộ phận, Chỉ định cá nhân
  Widget _buildTargetSelectionSection(
    List<MemberModel> members,
    List<DepartmentDefinition> departments,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Đối tượng nhận việc *',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // Segmented Control (3 nút: Toàn cửa hàng, Theo bộ phận, Cá nhân/nhóm)
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.8),
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _buildSegmentButton(
                  title: 'Toàn cửa hàng',
                  icon: LucideIcons.store,
                  isSelected: _targetType == TaskTargetType.allStore,
                  onTap: () {
                    setState(() {
                      _targetType = TaskTargetType.allStore;
                      _errorMessage = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildSegmentButton(
                  title: 'Theo bộ phận',
                  icon: LucideIcons.building,
                  isSelected: _targetType == TaskTargetType.department,
                  onTap: () {
                    setState(() {
                      _targetType = TaskTargetType.department;
                      if (_selectedDepartmentIds.isEmpty && departments.isNotEmpty) {
                        _selectedDepartmentIds.add(departments.first.id);
                      }
                      _errorMessage = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildSegmentButton(
                  title: 'Cá nhân/nhóm',
                  icon: LucideIcons.users,
                  isSelected: _targetType == TaskTargetType.individual,
                  onTap: () {
                    setState(() {
                      _targetType = TaskTargetType.individual;
                      _errorMessage = null;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Khi chọn "Theo bộ phận"
        if (_targetType == TaskTargetType.department) ...[
          _buildDepartmentSelectionSection(members, departments),
        ],

        // Khi chọn "Chỉ định cá nhân / nhóm"
        if (_targetType == TaskTargetType.individual) ...[
          _buildIndividualMembersList(members),
        ],
      ],
    );
  }

  /// UI chọn bộ phận và hiển thị danh sách thành viên thuộc bộ phận đó
  Widget _buildDepartmentSelectionSection(
    List<MemberModel> members,
    List<DepartmentDefinition> departments,
  ) {
    if (departments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.info, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Chưa thiết lập bộ phận',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Cửa hàng chưa có danh sách bộ phận (ví dụ: Pha chế, Phục vụ, Thu ngân...). Bạn có thể thêm bộ phận trong Cài đặt cửa hàng hoặc chọn giao theo Toàn cửa hàng / Cá nhân.',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    final selectedDepts = departments
        .where((d) => _selectedDepartmentIds.contains(d.id))
        .toList();

    final deptMembers = members.where((m) {
      if (m.department == null || m.department!.trim().isEmpty) return false;
      final mDept = m.department!.trim().toLowerCase();
      return _selectedDepartmentIds.any((dId) {
        final d = departments.cast<DepartmentDefinition?>().firstWhere((element) => element?.id == dId, orElse: () => null);
        if (d == null) return false;
        final dIdLower = d.id.trim().toLowerCase();
        final dNameLower = d.name.trim().toLowerCase();
        final dShortLower = d.shortName.trim().toLowerCase();
        return mDept == dIdLower || mDept == dNameLower || (dShortLower.isNotEmpty && mDept == dShortLower);
      });
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(
                'Chọn các bộ phận nhận việc:',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              )),
              if (departments.length > 1)
                InkWell(
                  onTap: () {
                    setState(() {
                      if (_selectedDepartmentIds.length == departments.length) {
                        _selectedDepartmentIds.clear();
                      } else {
                        _selectedDepartmentIds.clear();
                        _selectedDepartmentIds.addAll(departments.map((d) => d.id));
                      }
                      _errorMessage = null;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      _selectedDepartmentIds.length == departments.length
                          ? 'Bỏ chọn tất cả'
                          : 'Chọn tất cả',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.info, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Công việc sẽ tự động giao cho nhân sự có ca làm thuộc các bộ phận được chọn theo từng ngày (dựa trên Lịch làm việc tuần / Bộ phận của nhân viên).',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      color: AppColors.primary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Danh sách FilterChips các bộ phận (cho phép chọn nhiều bộ phận)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: departments.map((dept) {
              final isSelected = _selectedDepartmentIds.contains(dept.id);
              final count = members.where((m) {
                if (m.department == null || m.department!.trim().isEmpty) return false;
                final mDept = m.department!.trim().toLowerCase();
                final dId = dept.id.trim().toLowerCase();
                final dName = dept.name.trim().toLowerCase();
                final dShort = dept.shortName.trim().toLowerCase();
                return mDept == dId || mDept == dName || (dShort.isNotEmpty && mDept == dShort);
              }).length;

              return FilterChip(
                label: Text('${dept.name} ($count)'),
                selected: isSelected,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.cardSurface,
                showCheckmark: isSelected,
                checkmarkColor: Colors.white,
                labelStyle: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedDepartmentIds.add(dept.id);
                    } else {
                      _selectedDepartmentIds.remove(dept.id);
                    }
                    _errorMessage = null;
                  });
                },
              );
            }).toList(),
          ),

          if (_selectedDepartmentIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(LucideIcons.users, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Thành viên thuộc ${selectedDepts.map((d) => d.name).join(', ')} (${deptMembers.length}):',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (deptMembers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Chưa có nhân viên nào được gán vào các bộ phận đã chọn. Công việc sẽ tự động áp dụng khi có nhân viên có ca làm ở các bộ phận này.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: deptMembers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (context, index) {
                    final member = deptMembers[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.circleCheck, size: 18, color: AppColors.success),
                          const SizedBox(width: 8),
                          AvatarWidget(name: member.name, avatarUrl: member.avatarUrl, radius: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              member.name,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          RoleBadge(role: member.role, compact: true),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Danh sách thành viên để tick chọn
  Widget _buildIndividualMembersList(List<MemberModel> members) {
    final query = _memberSearchController.text.trim().toLowerCase();
    final filteredMembers = members.where((m) {
      if (query.isEmpty) return true;
      return m.name.toLowerCase().contains(query) ||
          (m.phone?.toLowerCase().contains(query) ?? false);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header chọn nhanh & Đếm
          Row(
            children: [
              Expanded(
                child: Text(
                  'Đã chọn: ${_selectedMemberIds.length}/${members.length} người',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    if (_selectedMemberIds.length == members.length) {
                      _selectedMemberIds.clear();
                    } else {
                      _selectedMemberIds.addAll(members.map((e) => e.userId));
                    }
                    _errorMessage = null;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    _selectedMemberIds.length == members.length
                        ? 'Bỏ chọn tất cả'
                        : 'Chọn tất cả',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.managerAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tìm kiếm nhanh nếu danh sách > 4
          if (members.length > 4) ...[
            TextField(
              controller: _memberSearchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc SĐT...',
                hintStyle: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: AppColors.textDisabled,
                ),
                prefixIcon: const Icon(
                  LucideIcons.search,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                isDense: true,
                filled: true,
                fillColor: AppColors.cardSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppColors.border.withValues(alpha: 0.6),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              style: GoogleFonts.beVietnamPro(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
          ],

          // Danh sách thành viên (có thể chọn cả Chủ, QL1, QL2, Nhân viên)
          if (filteredMembers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Không tìm thấy thành viên phù hợp',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                  ),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filteredMembers.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (context, index) {
                  final member = filteredMembers[index];
                  final isSelected = _selectedMemberIds.contains(member.userId);

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedMemberIds.remove(member.userId);
                        } else {
                          _selectedMemberIds.add(member.userId);
                        }
                        _errorMessage = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isSelected,
                            activeColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedMemberIds.add(member.userId);
                                } else {
                                  _selectedMemberIds.remove(member.userId);
                                }
                                _errorMessage = null;
                              });
                            },
                          ),
                          AvatarWidget(
                            name: member.name,
                            avatarUrl: member.avatarUrl,
                            radius: 15,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.name,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (member.phone != null && member.phone!.isNotEmpty)
                                  Text(
                                    member.phone!,
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          RoleBadge(role: member.role, compact: true),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
