import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/production_model.dart';
import '../../store/providers/store_provider.dart';
import '../providers/production_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ProductionTasksScreen extends ConsumerStatefulWidget {
  const ProductionTasksScreen({super.key});

  @override
  ConsumerState<ProductionTasksScreen> createState() =>
      _ProductionTasksScreenState();
}

class _ProductionTasksScreenState extends ConsumerState<ProductionTasksScreen> {
  void _openTaskDialog({ProductionTask? task, required int currentCount}) {
    final nameCtrl = TextEditingController(text: task?.name ?? '');
    final unitCtrl = TextEditingController(text: task?.unitLabel ?? 'Kg');
    bool hasUnit = task != null ? (task.unitLabel.trim().isNotEmpty) : true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                task == null ? 'Thêm công việc checklist' : 'Sửa công việc',
                style: GoogleFonts.beVietnamPro(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tên công việc sản xuất *',
                        style: GoogleFonts.beVietnamPro(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        hintText: 'VD: Nấu trà đào, Vệ sinh máy...',
                        hintStyle: GoogleFonts.beVietnamPro(
                            fontSize: 13, color: AppColors.textDisabled),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: GoogleFonts.beVietnamPro(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: hasUnit,
                          activeColor: AppColors.primary,
                          onChanged: (val) {
                            setDialogState(() {
                              hasUnit = val ?? true;
                            });
                          },
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                hasUnit = !hasUnit;
                              });
                            },
                            child: Text(
                              'Có đơn vị đo lường (Số lượng)',
                              style: GoogleFonts.beVietnamPro(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasUnit) ...[
                      const SizedBox(height: 8),
                      Text('Tên đơn vị *',
                          style: GoogleFonts.beVietnamPro(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: unitCtrl,
                        decoration: InputDecoration(
                          hintText: 'VD: Kg, Lít, Ly, Thùng, Ca, Lần...',
                          hintStyle: GoogleFonts.beVietnamPro(
                              fontSize: 13, color: AppColors.textDisabled),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: GoogleFonts.beVietnamPro(fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Hủy',
                      style: GoogleFonts.beVietnamPro(
                          color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Vui lòng nhập tên công việc sản xuất')),
                      );
                      return;
                    }
                    final storeId = ref.read(currentStoreIdProvider);
                    if (storeId == null) return;
                    final repo = ref.read(productionRepositoryProvider);

                    Navigator.pop(ctx);
                    try {
                      if (task == null) {
                        await repo.addTask(
                          storeId,
                          name: name,
                          unit: hasUnit
                              ? ProductionUnitType.qty
                              : ProductionUnitType.qty,
                          unitLabel: hasUnit
                              ? (unitCtrl.text.trim().isEmpty
                                  ? 'Sản phẩm'
                                  : unitCtrl.text.trim())
                              : '',
                          order: currentCount + 1,
                        );
                      } else {
                        await repo.updateTask(storeId, task.id, {
                          'name': name,
                          'unitLabel': hasUnit
                              ? (unitCtrl.text.trim().isEmpty
                                  ? 'Sản phẩm'
                                  : unitCtrl.text.trim())
                              : '',
                        });
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Lỗi: $e')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(task == null ? 'Thêm' : 'Lưu',
                      style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeId = ref.watch(currentStoreIdProvider);
    final tasksAsync = ref.watch(allProductionTasksProvider);
    final currentMember = ref.watch(currentMemberStreamProvider).valueOrNull;
    final isOwner = currentMember?.isOwner ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Danh mục Checklist Sản xuất',
            style: TextStyle(
                fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        elevation: 0,
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(LucideIcons.circlePlus),
              tooltip: 'Thêm công việc',
              onPressed: () {
                final count = tasksAsync.valueOrNull?.length ?? 0;
                _openTaskDialog(currentCount: count);
              },
            ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.listChecks,
                        size: 64, color: AppColors.textDisabled),
                    const SizedBox(height: 16),
                    Text(
                      'Chưa có công việc nào',
                      style: GoogleFonts.beVietnamPro(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isOwner
                          ? 'Bấm nút "+" để thêm các đầu việc checklist sản xuất'
                          : 'Chưa có danh mục checklist nào được tạo.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                          fontSize: 13, color: AppColors.textDisabled),
                    ),
                    if (isOwner) ...[
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _openTaskDialog(currentCount: 0),
                        icon: const Icon(LucideIcons.plus),
                        label: const Text('Thêm công việc mới'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFFF1F3F5),
                child: Row(
                  children: [
                    const Icon(LucideIcons.info,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isOwner
                            ? 'Kéo giữ biểu tượng ☰ để sắp xếp thứ tự checklist'
                            : 'Chế độ xem: Danh sách checklist theo thứ tự do Chủ quán sắp xếp',
                        style: GoogleFonts.beVietnamPro(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isOwner
                    ? ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: tasks.length,
                        onReorder: (oldIndex, newIndex) {
                          if (oldIndex < newIndex) newIndex -= 1;
                          final list = List<ProductionTask>.from(tasks);
                          final moved = list.removeAt(oldIndex);
                          list.insert(newIndex, moved);
                          if (storeId != null) {
                            ref
                                .read(productionRepositoryProvider)
                                .reorderTasks(storeId, list);
                          }
                        },
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final hasUnit = task.unitLabel.trim().isNotEmpty;

                          return Container(
                            key: ValueKey(task.id),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Icon(LucideIcons.gripHorizontal,
                                          color: AppColors.textDisabled, size: 22),
                                    ),
                                  ),
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      (index + 1).toString(),
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              title: Text(
                                task.name,
                                style: GoogleFonts.beVietnamPro(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                  color: task.active
                                      ? AppColors.neutral
                                      : AppColors.textDisabled,
                                  decoration: task.active
                                      ? TextDecoration.none
                                      : TextDecoration.lineThrough,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: hasUnit
                                            ? const Color(0xFFE7F5FF)
                                            : const Color(0xFFF1F3F5),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        hasUnit
                                            ? task.unitLabel
                                            : '✓ Checklist',
                                        style: TextStyle(
                                          fontFamily: 'BeVietnamPro',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: hasUnit
                                              ? const Color(0xFF1C7ED6)
                                              : const Color(0xFF868E96),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: task.active,
                                    activeColor: AppColors.primary,
                                    onChanged: (val) {
                                      if (storeId != null) {
                                        ref
                                            .read(productionRepositoryProvider)
                                            .updateTask(storeId, task.id,
                                                {'active': val});
                                      }
                                    },
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(LucideIcons.ellipsisVertical,
                                        color: AppColors.textSecondary, size: 20),
                                    onSelected: (val) async {
                                      if (val == 'edit') {
                                        _openTaskDialog(
                                            task: task, currentCount: tasks.length);
                                      } else if (val == 'delete') {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text('Xác nhận xóa'),
                                            content: Text(
                                                'Bạn có chắc muốn xóa công việc "${task.name}"?'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c, false),
                                                  child: const Text('Hủy')),
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c, true),
                                                  child: const Text('Xóa',
                                                      style: TextStyle(
                                                          color: AppColors.danger))),
                                            ],
                                          ),
                                        );
                                        if (confirm == true && storeId != null) {
                                          ref
                                              .read(productionRepositoryProvider)
                                              .deleteTask(storeId, task.id);
                                        }
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(LucideIcons.pencil, size: 18),
                                            SizedBox(width: 8),
                                            Text('Chỉnh sửa'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(LucideIcons.trash2,
                                                size: 18, color: AppColors.danger),
                                            SizedBox(width: 8),
                                            Text('Xóa',
                                                style: TextStyle(
                                                    color: AppColors.danger)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final hasUnit = task.unitLabel.trim().isNotEmpty;

                          return Container(
                            key: ValueKey(task.id),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  (index + 1).toString(),
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              title: Text(
                                task.name,
                                style: GoogleFonts.beVietnamPro(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                  color: task.active
                                      ? AppColors.neutral
                                      : AppColors.textDisabled,
                                  decoration: task.active
                                      ? TextDecoration.none
                                      : TextDecoration.lineThrough,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: hasUnit
                                            ? const Color(0xFFE7F5FF)
                                            : const Color(0xFFF1F3F5),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        hasUnit
                                            ? task.unitLabel
                                            : '✓ Checklist',
                                        style: TextStyle(
                                          fontFamily: 'BeVietnamPro',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: hasUnit
                                              ? const Color(0xFF1C7ED6)
                                              : const Color(0xFF868E96),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: task.active
                                      ? const Color(0xFFE6FCF5)
                                      : const Color(0xFFF1F3F5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  task.active ? 'Đang bật' : 'Đang tắt',
                                  style: TextStyle(
                                    fontFamily: 'BeVietnamPro',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: task.active
                                        ? const Color(0xFF0CA678)
                                        : AppColors.textDisabled,
                                  ),
                                ),
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
