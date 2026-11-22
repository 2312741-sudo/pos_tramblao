import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/attendance_model.dart';
import '../../store/providers/store_provider.dart';
import '../../salary/providers/salary_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../cc_firebase.dart';

class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  final String? userId;
  final String? month;

  const AttendanceHistoryScreen({
    super.key,
    this.userId,
    this.month,
  });

  @override
  ConsumerState<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends ConsumerState<AttendanceHistoryScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    if (widget.month != null && widget.month!.contains('-')) {
      final parts = widget.month!.split('-');
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null) {
        _selectedMonth = DateTime(y, m);
        return;
      }
    }
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  String get _monthKey =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  void _prevMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (next.isAfter(DateTime(now.year + 1, 12))) return;
    setState(() {
      _selectedMonth = next;
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    showDialog(
      context: context,
      builder: (ctx) {
        DateTime temp = _selectedMonth;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Chọn tháng',
            style: GoogleFonts.beVietnamPro(
                fontWeight: FontWeight.w700, fontSize: 18),
          ),
          content: SizedBox(
            height: 220,
            width: 300,
            child: YearPicker(
              firstDate: DateTime(now.year - 3),
              lastDate: DateTime(now.year + 2),
              selectedDate: temp,
              onChanged: (d) {
                setState(() {
                  _selectedMonth = DateTime(d.year, d.month);
                });
                Navigator.pop(ctx);
              },
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  String _formatDateHeader(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final weekdayStr = switch (date.weekday) {
        DateTime.monday => 'Thứ Hai',
        DateTime.tuesday => 'Thứ Ba',
        DateTime.wednesday => 'Thứ Tư',
        DateTime.thursday => 'Thứ Năm',
        DateTime.friday => 'Thứ Sáu',
        DateTime.saturday => 'Thứ Bảy',
        DateTime.sunday => 'Chủ Nhật',
        _ => '',
      };
      return '$weekdayStr, ${DateFormat('dd/MM/yyyy').format(date)}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = CcFirebase.auth.currentUser?.uid ?? '';
    final targetUserId = widget.userId ?? currentUid;
    final isSelf = targetUserId == currentUid;

    final storeId = ref.watch(currentStoreIdProvider);
    final currentMember = ref.watch(currentMemberProvider);
    final isManagerOrOwner = currentMember?.isOwner == true ||
        currentMember?.isManager == true;

    if (storeId == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final attendancesAsync = ref.watch(
      memberMonthAttendancesProvider((userId: targetUserId, month: _monthKey)),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft,
              color: AppColors.neutral, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          isSelf ? 'Lịch sử chấm công' : 'Lịch sử chấm công nhân viên',
          style: GoogleFonts.beVietnamPro(
            color: AppColors.neutral,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.calendarDays,
                color: AppColors.neutral),
            onPressed: _pickMonth,
            tooltip: 'Chọn tháng',
          ),
        ],
      ),
      body: attendancesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (attendances) {
          final sorted = List<AttendanceModel>.from(attendances)
            ..sort((a, b) => b.date.compareTo(a.date));

          final totalHours =
              attendances.fold(0.0, (sum, a) => sum + a.totalHours);
          final totalShifts = attendances.length;
          final uniqueDays =
              attendances.where((a) => a.totalHours > 0).map((a) => a.date).toSet().length;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(memberMonthAttendancesProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                // Month Selector Bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: _prevMonth,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(LucideIcons.chevronLeft,
                              size: 20, color: AppColors.neutral),
                        ),
                      ),
                      Flexible(child: Text(
                        'Tháng ${_selectedMonth.month.toString().padLeft(2, '0')}/${_selectedMonth.year}',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.neutral,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                      InkWell(
                        onTap: _nextMonth,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(LucideIcons.chevronRight,
                              size: 20, color: AppColors.neutral),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Stats Summary Cards Row
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBadge(
                        icon: LucideIcons.clock,
                        color: AppColors.primary,
                        title: 'Tổng giờ',
                        value: '${totalHours.toStringAsFixed(1)}h',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatBadge(
                        icon: LucideIcons.calendarCheck,
                        color: const Color(0xFF70B843),
                        title: 'Ngày làm',
                        value: '$uniqueDays ngày',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatBadge(
                        icon: LucideIcons.receiptText,
                        color: const Color(0xFF0066CC),
                        title: 'Số ca',
                        value: '$totalShifts ca',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Chi tiết từng ca làm',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.neutral,
                      ),
                    ),
                    Text(
                      '${sorted.length} lượt',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Attendances List or Empty State
                if (sorted.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.history,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có dữ liệu chấm công',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.neutral,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tháng ${_selectedMonth.month}/${_selectedMonth.year} chưa ghi nhận lượt vào/ra nào.',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ...sorted.map((a) {
                    final isActive = a.isActive;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isActive
                              ? AppColors.primary.withOpacity(0.4)
                              : const Color(0xFFE5E7EB),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Header of card: Date & Duration
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    LucideIcons.calendar,
                                    size: 14,
                                    color: isActive
                                        ? AppColors.primary
                                        : const Color(0xFF0066CC),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatDateHeader(a.date),
                                    style: GoogleFonts.beVietnamPro(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: AppColors.neutral,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? const Color(0xFFFFF3CD)
                                      : a.totalHours > 0
                                          ? const Color(0xFFE8F5E9)
                                          : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isActive
                                      ? 'Đang trong ca'
                                      : '${a.totalHours.toStringAsFixed(1)} giờ',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: isActive
                                        ? const Color(0xFF856404)
                                        : a.totalHours > 0
                                            ? const Color(0xFF2E7D32)
                                            : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),
                          const Divider(height: 1, color: Color(0xFFF3F4F6)),
                          const SizedBox(height: 10),

                          // In & Out Row
                          Row(
                            children: [
                              // Check In
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8F5E9),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        LucideIcons.logIn,
                                        color: Color(0xFF2E7D32),
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Vào ca',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          _formatTime(a.checkIn),
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.neutral,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Arrow
                              const Icon(LucideIcons.arrowRight,
                                  size: 14, color: Color(0xFF9CA3AF)),

                              // Check Out
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Ra ca',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          a.checkOut != null
                                              ? _formatTime(a.checkOut)
                                              : 'Chưa ra',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: a.checkOut != null
                                              ? AppColors.neutral
                                              : AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: a.checkOut != null
                                            ? const Color(0xFFFFEBEE)
                                            : const Color(0xFFFFF3CD),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        a.checkOut != null
                                            ? LucideIcons.logOut
                                            : LucideIcons.timer,
                                        color: a.checkOut != null
                                            ? AppColors.primary
                                            : const Color(0xFF856404),
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Badges for Edited or Note
                          if (a.isEdited || (a.editNote != null && a.editNote!.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (a.isEdited)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3CD),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Đã chỉnh sửa',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF856404),
                                      ),
                                    ),
                                  ),
                                if (a.editNote != null && a.editNote!.isNotEmpty)
                                  Text(
                                    'Ghi chú: ${a.editNote}',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatBadge({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                title,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.neutral,
            ),
          ),
        ],
      ),
    );
  }
}
