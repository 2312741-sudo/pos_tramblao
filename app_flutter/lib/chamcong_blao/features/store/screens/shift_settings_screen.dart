import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/store_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ── Model ────────────────────────────────────────────────────────────────────

class ShiftDefinition {
  final String id;
  final String name;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final bool isProduction;

  const ShiftDefinition({
    required this.id,
    required this.name,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.isProduction = false,
  });

  String get startTimeStr =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
  String get endTimeStr =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
  String get timeRange => '$startTimeStr - $endTimeStr';

  double get totalHours {
    final start = startHour * 60 + startMinute;
    var end = endHour * 60 + endMinute;
    if (end < start) end += 24 * 60; // overnight shift
    return (end - start) / 60.0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'isProduction': isProduction,
      };

  factory ShiftDefinition.fromJson(Map<String, dynamic> json) =>
      ShiftDefinition(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        startHour: (json['startHour'] as int?) ?? 8,
        startMinute: (json['startMinute'] as int?) ?? 0,
        endHour: (json['endHour'] as int?) ?? 17,
        endMinute: (json['endMinute'] as int?) ?? 0,
        isProduction: (json['isProduction'] as bool?) ?? false,
      );

  ShiftDefinition copyWith({
    String? name,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    bool? isProduction,
  }) =>
      ShiftDefinition(
        id: id,
        name: name ?? this.name,
        startHour: startHour ?? this.startHour,
        startMinute: startMinute ?? this.startMinute,
        endHour: endHour ?? this.endHour,
        endMinute: endMinute ?? this.endMinute,
        isProduction: isProduction ?? this.isProduction,
      );
}

// ── Default shifts ────────────────────────────────────────────────────────────

final kDefaultShifts = [
  ShiftDefinition(
      id: 'morning', name: 'Ca sáng', startHour: 6, startMinute: 0, endHour: 14, endMinute: 0),
  ShiftDefinition(
      id: 'afternoon', name: 'Ca chiều', startHour: 14, startMinute: 0, endHour: 22, endMinute: 0),
  ShiftDefinition(
      id: 'evening', name: 'Ca tối', startHour: 22, startMinute: 0, endHour: 6, endMinute: 0),
];

// ── Provider ──────────────────────────────────────────────────────────────────

final storeShiftsProvider = Provider<List<ShiftDefinition>>((ref) {
  final storeAsync = ref.watch(currentStoreProvider);
  return storeAsync.whenOrNull(data: (store) {
        if (store == null) return kDefaultShifts;
        final raw = store.customShifts;
        if (raw.isEmpty) return kDefaultShifts;
        return raw;
      }) ??
      kDefaultShifts;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ShiftSettingsScreen extends ConsumerStatefulWidget {
  const ShiftSettingsScreen({super.key});

  @override
  ConsumerState<ShiftSettingsScreen> createState() =>
      _ShiftSettingsScreenState();
}

class _ShiftSettingsScreenState extends ConsumerState<ShiftSettingsScreen> {
  late List<ShiftDefinition> _shifts;
  bool _loaded = false;
  bool _saving = false;

  void _loadShifts(List<ShiftDefinition> shifts) {
    if (_loaded) return;
    _loaded = true;
    _shifts = List.from(shifts);
  }

  Future<void> _save() async {
    final storeId = ref.read(currentStoreIdProvider);
    if (storeId == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      await repo.updateStoreSettings(storeId, {
        'customShifts': _shifts.map((s) => s.toJson()).toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã lưu danh sách ca'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lỗi: $e'),
          backgroundColor: AppColors.primary,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addShift() {
    _showShiftEditor(null);
  }

  void _editShift(int index) {
    _showShiftEditor(index);
  }

  void _deleteShift(int index) {
    setState(() => _shifts.removeAt(index));
  }

  void _showShiftEditor(int? editIndex) {
    final existing = editIndex != null ? _shifts[editIndex] : null;
    final nameCtrl =
        TextEditingController(text: existing?.name ?? '');
    TimeOfDay startTime = existing != null
        ? TimeOfDay(hour: existing.startHour, minute: existing.startMinute)
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = existing != null
        ? TimeOfDay(hour: existing.endHour, minute: existing.endMinute)
        : const TimeOfDay(hour: 17, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editIndex != null ? 'Sửa ca làm' : 'Thêm ca làm',
                  style: const TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.neutral),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontFamily: 'BeVietnamPro'),
                  decoration: InputDecoration(
                    labelText: 'Tên ca',
                    hintText: 'VD: Ca sáng, Ca chiều...',
                    labelStyle: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _TimePickerTile(
                        label: 'Giờ bắt đầu',
                        time: startTime,
                        color: AppColors.success,
                        onTap: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: startTime,
                            builder: (c, child) => Theme(
                              data: Theme.of(c).copyWith(
                                colorScheme: const ColorScheme.light(
                                    primary: AppColors.primary),
                              ),
                              child: child!,
                            ),
                          );
                          if (t != null) {
                            setModalState(() => startTime = t);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimePickerTile(
                        label: 'Giờ kết thúc',
                        time: endTime,
                        color: AppColors.primary,
                        onTap: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: endTime,
                            builder: (c, child) => Theme(
                              data: Theme.of(c).copyWith(
                                colorScheme: const ColorScheme.light(
                                    primary: AppColors.primary),
                              ),
                              child: child!,
                            ),
                          );
                          if (t != null) {
                            setModalState(() => endTime = t);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Hủy',
                            style: TextStyle(
                                fontFamily: 'BeVietnamPro',
                                color: AppColors.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          final shift = ShiftDefinition(
                            id: existing?.id ??
                                'shift_${DateTime.now().millisecondsSinceEpoch}',
                            name: name,
                            startHour: startTime.hour,
                            startMinute: startTime.minute,
                            endHour: endTime.hour,
                            endMinute: endTime.minute,
                          );
                          setState(() {
                            if (editIndex != null) {
                              _shifts[editIndex] = shift;
                            } else {
                              _shifts.add(shift);
                            }
                          });
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Lưu ca',
                            style: TextStyle(
                                fontFamily: 'BeVietnamPro',
                                fontWeight: FontWeight.bold)),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final shifts = ref.watch(storeShiftsProvider);
    _loadShifts(shifts);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        elevation: 0,
        title: const Text('Quản lý ca làm',
            style: TextStyle(
                fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(LucideIcons.download,
                    color: Colors.white, size: 18),
            label: const Text('Lưu',
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'BeVietnamPro',
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addShift,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(LucideIcons.plus),
        label: const Text('Thêm ca',
            style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold)),
      ),
      body: _shifts.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.clock,
                      size: 60, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text('Chưa có ca làm nào',
                      style: TextStyle(
                          fontFamily: 'BeVietnamPro',
                          color: AppColors.textSecondary,
                          fontSize: 15)),
                  SizedBox(height: 8),
                  Text('Nhấn + để thêm ca mới',
                      style: TextStyle(
                          fontFamily: 'BeVietnamPro',
                          color: AppColors.textSecondary,
                          fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _shifts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final shift = _shifts[index];
                return _ShiftCard(
                  shift: shift,
                  index: index,
                  onEdit: () => _editShift(index),
                  onDelete: () => _deleteShift(index),
                );
              },
            ),
    );
  }
}

// ── Shift Card ────────────────────────────────────────────────────────────────

class _ShiftCard extends StatelessWidget {
  final ShiftDefinition shift;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ShiftCard({
    required this.shift,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _color {
    final colors = [
      AppColors.primary,
      AppColors.success,
      AppColors.info,
      AppColors.accent,
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.clock, color: _color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shift.name,
                    style: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.neutral)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(LucideIcons.clock, size: 13, color: _color),
                    const SizedBox(width: 4),
                    Text(shift.timeRange,
                        style: TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 13,
                            color: _color,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Flexible(child: Text('(${shift.totalHours.toStringAsFixed(1)}h)',
                        style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.pencil,
                color: AppColors.info, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash2,
                color: AppColors.primary, size: 20),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Time Picker Tile ──────────────────────────────────────────────────────────

class _TimePickerTile extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final Color color;
  final VoidCallback onTap;

  const _TimePickerTile({
    required this.label,
    required this.time,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label,
                style: const TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 11,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(formatted,
                style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 4),
            Icon(LucideIcons.pointer, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
