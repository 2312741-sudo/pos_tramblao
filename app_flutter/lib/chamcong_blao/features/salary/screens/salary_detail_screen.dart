import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../app/router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/attendance_model.dart';
import '../../../models/member_model.dart';
import '../../../models/advance_request_model.dart';
import '../../store/providers/store_provider.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../providers/salary_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../cc_firebase.dart';

class SalaryDetailScreen extends ConsumerStatefulWidget {
  final String? userId;
  final String? memberName;

  const SalaryDetailScreen({
    super.key,
    this.userId,
    this.memberName,
  });

  @override
  ConsumerState<SalaryDetailScreen> createState() => _SalaryDetailScreenState();
}

class _SalaryDetailScreenState extends ConsumerState<SalaryDetailScreen> {
  late DateTime _selectedMonth;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  String get _monthKey =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  String _formatCurrency(double amount) {
    final n = amount.round();
    final formatted = NumberFormat('#,###', 'vi_VN').format(n).replaceAll(',', '.');
    return '$formatted đ';
  }

  String _formatCompactCurrency(double amount) {
    if (amount <= 0) return '';
    if (amount >= 1000000) {
      final val = amount / 1000000.0;
      return '${val.toStringAsFixed(val.truncateToDouble() == val ? 0 : 1)}M';
    } else if (amount >= 1000) {
      final val = amount / 1000.0;
      return '${val.toStringAsFixed(val.truncateToDouble() == val ? 0 : 1)}K';
    }
    return amount.round().toString();
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Chọn tháng',
            style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 18),
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

  void _showAdvanceRequestModal(BuildContext context, String storeId, String targetUid) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Xin ứng lương',
                  style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.neutral),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Số tiền muốn ứng (VNĐ)',
                hintText: 'Ví dụ: 1000000',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(LucideIcons.banknote, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: 'Lý do (không bắt buộc)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(LucideIcons.notebookText, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vui lòng nhập số tiền hợp lệ')),
                    );
                    return;
                  }

                  final request = AdvanceRequestModel(
                    id: '',
                    storeId: storeId,
                    userId: targetUid,
                    month: _monthKey,
                    amount: amount,
                    status: AdvanceStatus.pending,
                    requestDate: DateTime.now(),
                    note: noteCtrl.text.trim(),
                  );

                  try {
                    await ref.read(storeRepositoryProvider).createAdvanceRequest(request);
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã gửi yêu cầu ứng lương thành công'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.danger),
                      );
                    }
                  }
                },
                child: Text(
                  'Gửi yêu cầu',
                  style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = CcFirebase.auth.currentUser?.uid ?? '';
    final targetUserId = widget.userId ?? currentUid;
    final isSelf = targetUserId == currentUid;

    final store = ref.watch(currentStoreProvider).valueOrNull;
    final storeId = ref.watch(currentStoreIdProvider);

    if (storeId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final salaryDataAsync = ref.watch(
      memberSalaryDataProvider((userId: targetUserId, month: _monthKey)),
    );
    final advances = ref.watch(
      userAdvancesProvider((userId: targetUserId, month: _monthKey)),
    );
    final todayAttendanceAsync = isSelf ? ref.watch(myTodayAttendanceProvider) : null;

    final storeName = (store?.name ?? 'TRẠM BLAO').toUpperCase();
    final displayName = widget.memberName ?? storeName;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: AppColors.neutral, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          isSelf ? storeName : displayName,
          style: GoogleFonts.beVietnamPro(
            color: const Color(0xFF0066CC),
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.calendarDays, color: AppColors.neutral),
            onPressed: _pickMonth,
            tooltip: 'Chọn tháng',
          ),
        ],
      ),
      bottomNavigationBar: isSelf
          ? _buildBottomActionBar(
              context: context,
              attendance: todayAttendanceAsync?.valueOrNull,
            )
          : null,
      body: salaryDataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (data) {
          final member = data['member'] as MemberModel?;
          if (member == null) {
            return const Center(child: Text('Không tìm thấy dữ liệu nhân viên'));
          }

          final attendances = (data['attendances'] as List<AttendanceModel>?) ?? [];
          final totalSalary = (data['salary'] as double?) ?? 0.0;
          final totalHours = (data['totalHours'] as double?) ?? 0.0;
          final deliveryPay = (data['deliveryPay'] as double?) ?? 0.0;
          final giaoHangPay = (data['giaoHangPay'] as double?) ?? 0.0;

          final approvedAdvance = advances
              .where((a) => a.status == AdvanceStatus.approved)
              .fold(0.0, (sum, a) => sum + a.amount);
          final pendingAdvance = advances
              .where((a) => a.status == AdvanceStatus.pending)
              .fold(0.0, (sum, a) => sum + a.amount);

          const totalDeductions = 0.0;
          const totalPaid = 0.0;
          final netUnpaid = (totalSalary - approvedAdvance - totalDeductions - totalPaid).clamp(0.0, double.infinity);

          // Build daily earnings map
          final dailyEarningsMap = <int, double>{};
          final dailyHoursMap = <int, double>{};
          final dailyAttendancesMap = <int, List<AttendanceModel>>{};

          final hourlyRate = member.isFulltime
              ? (member.standardHoursPerMonth > 0
                  ? member.baseMonthlySalary / member.standardHoursPerMonth
                  : 0.0)
              : member.baseHourlyRate;

          for (final a in attendances) {
            final parts = a.date.split('-');
            if (parts.length == 3) {
              final day = int.tryParse(parts[2]);
              if (day != null) {
                dailyHoursMap[day] = (dailyHoursMap[day] ?? 0.0) + a.totalHours;
                dailyEarningsMap[day] = (dailyEarningsMap[day] ?? 0.0) + (a.totalHours * hourlyRate);
                dailyAttendancesMap.putIfAbsent(day, () => []).add(a);
              }
            }
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(memberSalaryDataProvider);
              ref.invalidate(storeAdvancesProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Pending Advance Alert (if any)
                if (pendingAdvance > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD54F)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.hourglass, color: Color(0xFFF57F17), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đang có yêu cầu ứng ${_formatCurrency(pendingAdvance)} chờ duyệt.',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFF57F17),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Card 1: Tổng quan Tiền Công Tháng
                _buildSummaryCard(
                  monthStr: _selectedMonth.month.toString().padLeft(2, '0'),
                  totalSalary: totalSalary,
                  totalAdvance: approvedAdvance,
                  totalDeductions: totalDeductions,
                  totalPaid: totalPaid,
                  netUnpaid: netUnpaid,
                  member: member,
                  totalHours: totalHours,
                  deliveryPay: deliveryPay,
                  giaoHangPay: giaoHangPay,
                  storeId: storeId,
                  targetUid: targetUserId,
                  isSelf: isSelf,
                ),

                const SizedBox(height: 16),

                // Card 2: Lịch Chấm Công & Tiền Mỗi Ngày
                _buildCalendarCard(
                  context: context,
                  targetUserId: targetUserId,
                  dailyEarningsMap: dailyEarningsMap,
                  dailyHoursMap: dailyHoursMap,
                  dailyAttendancesMap: dailyAttendancesMap,
                  totalHours: totalHours,
                  hourlyRate: hourlyRate,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── CARD 1: TỔNG QUAN TIỀN CÔNG THÁNG ────────────────────────────────────

  Widget _buildSummaryCard({
    required String monthStr,
    required double totalSalary,
    required double totalAdvance,
    required double totalDeductions,
    required double totalPaid,
    required double netUnpaid,
    required MemberModel member,
    required double totalHours,
    required double deliveryPay,
    required double giaoHangPay,
    required String storeId,
    required String targetUid,
    required bool isSelf,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header inside Card
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tiền Công Tháng $monthStr',
                style: GoogleFonts.beVietnamPro(
                  color: const Color(0xFF0066CC),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              InkWell(
                onTap: _pickMonth,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tháng khác',
                        style: GoogleFonts.beVietnamPro(
                          color: const Color(0xFF0066CC),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(LucideIcons.chevronRight, color: Color(0xFF0066CC), size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const _DashedLine(),
          const SizedBox(height: 12),

          // Row: Tổng lương
          _buildSummaryRow(
            label: 'Tổng lương',
            value: _formatCurrency(totalSalary),
            valueColor: const Color(0xFF0066CC),
            isBold: true,
          ),

          const SizedBox(height: 10),
          const _DashedLine(),
          const SizedBox(height: 10),

          // Row: Tổng đã ứng
          _buildSummaryRow(
            label: 'Tổng đã ứng',
            value: _formatCurrency(totalAdvance),
            valueColor: AppColors.danger,
          ),

          const SizedBox(height: 10),
          const _DashedLine(),
          const SizedBox(height: 10),

          // Row: Tổng tiền trừ
          _buildSummaryRow(
            label: 'Tổng tiền trừ',
            value: _formatCurrency(totalDeductions),
            valueColor: AppColors.danger,
          ),

          const SizedBox(height: 10),
          const _DashedLine(),
          const SizedBox(height: 10),

          // Row: Tổng đã thanh toán
          _buildSummaryRow(
            label: 'Tổng đã thanh toán',
            value: _formatCurrency(totalPaid),
            valueColor: AppColors.danger,
          ),

          const SizedBox(height: 10),
          const _DashedLine(),
          const SizedBox(height: 12),

          // Row: Tổng chưa nhận
          _buildSummaryRow(
            label: 'Tổng chưa nhận',
            value: _formatCurrency(netUnpaid),
            valueColor: AppColors.neutral,
            isBold: true,
            fontSize: 17,
          ),

          const SizedBox(height: 8),

          // Expandable Breakdown
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  _buildSubRow('Loại nhân viên', member.isFulltime ? 'Full-time' : 'Part-time'),
                  const SizedBox(height: 6),
                  _buildSubRow(
                    'Mức lương',
                    member.isFulltime
                        ? '${_formatCurrency(member.baseMonthlySalary)}/tháng'
                        : '${_formatCurrency(member.baseHourlyRate)}/giờ',
                  ),
                  const SizedBox(height: 6),
                  _buildSubRow('Tổng giờ làm', '${totalHours.toStringAsFixed(1)} giờ'),
                  if (deliveryPay > 0) ...[
                    const SizedBox(height: 6),
                    _buildSubRow('Phụ cấp chở hàng', '+${_formatCurrency(deliveryPay)}'),
                  ],
                  if (giaoHangPay > 0) ...[
                    const SizedBox(height: 6),
                    _buildSubRow('Phụ cấp giao hàng', '+${_formatCurrency(giaoHangPay)}'),
                  ],
                  const SizedBox(height: 12),
                  if (isSelf)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(LucideIcons.banknote, size: 16, color: AppColors.primary),
                        label: Text(
                          'Xin ứng lương',
                          style: GoogleFonts.beVietnamPro(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () => _showAdvanceRequestModal(context, storeId, targetUid),
                      ),
                    ),
                ],
              ),
            ),
          ],

          // Toggle Expand Button
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
              icon: Icon(
                _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                color: AppColors.textSecondary,
                size: 18,
              ),
              label: Text(
                _isExpanded ? 'Thu gọn' : 'Xem thêm',
                style: GoogleFonts.beVietnamPro(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required String label,
    required String value,
    required Color valueColor,
    bool isBold = false,
    double fontSize = 14,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.beVietnamPro(
              color: isBold ? AppColors.neutral : const Color(0xFF4B5563),
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: GoogleFonts.beVietnamPro(
            color: valueColor,
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSubRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary))),
        const SizedBox(width: 8),
        Text(value, style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.neutral)),
      ],
    );
  }

  // ─── CARD 2: LỊCH CHẤM CÔNG & TIỀN MỖI NGÀY ───────────────────────────────

  Widget _buildCalendarCard({
    required BuildContext context,
    required String targetUserId,
    required Map<int, double> dailyEarningsMap,
    required Map<int, double> dailyHoursMap,
    required Map<int, List<AttendanceModel>> dailyAttendancesMap,
    required double totalHours,
    required double hourlyRate,
  }) {
    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstDayWeekday = DateTime(year, month, 1).weekday; // 1 = Monday, 7 = Sunday
    final leadingEmptyCount = firstDayWeekday - 1; // 0 for Monday

    final workingDaysCount = dailyHoursMap.values.where((h) => h > 0).length;
    final offDaysCount = (daysInMonth - workingDaysCount).clamp(0, daysInMonth);

    // Build weeks matrix
    final totalCells = leadingEmptyCount + daysInMonth;
    final totalWeeks = (totalCells / 7).ceil();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Navigation Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
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
                      child: const Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.neutral),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Tháng ${month.toString().padLeft(2, '0')}/$year',
                    style: GoogleFonts.beVietnamPro(
                      color: AppColors.neutral,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _nextMonth,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.neutral),
                    ),
                  ),
                ],
              ),

              // Button "Xem chi tiết >"
              InkWell(
                onTap: () {
                  context.push(
                    Uri(
                      path: AppRoutes.attendanceHistory,
                      queryParameters: {
                        'userId': targetUserId,
                        'month': _monthKey,
                      },
                    ).toString(),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Xem chi tiết',
                        style: GoogleFonts.beVietnamPro(
                          color: const Color(0xFF0066CC),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(LucideIcons.chevronRight, color: Color(0xFF0066CC), size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Day Headers: T2 -> CN
          Row(
            children: ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'].map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: GoogleFonts.beVietnamPro(
                      color: const Color(0xFF6B7280),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 10),

          // Calendar Grid using structured Rows
          Column(
            children: List.generate(totalWeeks, (weekIndex) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: List.generate(7, (dayIndex) {
                    final cellIndex = weekIndex * 7 + dayIndex;
                    if (cellIndex < leadingEmptyCount || cellIndex >= totalCells) {
                      return const Expanded(child: SizedBox(height: 52));
                    }

                    final dayNum = cellIndex - leadingEmptyCount + 1;
                    final workedHours = dailyHoursMap[dayNum] ?? 0.0;
                    final dailyEarnings = dailyEarningsMap[dayNum] ?? 0.0;
                    final isWorkingDay = workedHours > 0;
                    final dayAttendances = dailyAttendancesMap[dayNum] ?? [];

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: InkWell(
                          onTap: isWorkingDay
                              ? () => _showDayDetailDialog(
                                    context,
                                    dayNum,
                                    month,
                                    year,
                                    workedHours,
                                    dailyEarnings,
                                    dayAttendances,
                                  )
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: isWorkingDay ? const Color(0xFF70B843) : const Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$dayNum',
                                  style: GoogleFonts.beVietnamPro(
                                    color: isWorkingDay ? Colors.white : const Color(0xFF4B5563),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (isWorkingDay)
                                  Text(
                                    _formatCompactCurrency(dailyEarnings),
                                    style: GoogleFonts.beVietnamPro(
                                      color: Colors.white.withOpacity(0.95),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 12),

          // Legend at bottom
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF70B843),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Đi làm: $workingDaysCount ngày',
                    style: GoogleFonts.beVietnamPro(fontSize: 11.5, color: const Color(0xFF4B5563), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF9CA3AF),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Nghỉ: $offDaysCount ngày',
                    style: GoogleFonts.beVietnamPro(fontSize: 11.5, color: const Color(0xFF4B5563), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(LucideIcons.timer, size: 13, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    '${totalHours.toStringAsFixed(1)}h',
                    style: GoogleFonts.beVietnamPro(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.neutral),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDayDetailDialog(
    BuildContext context,
    int day,
    int month,
    int year,
    double hours,
    double earnings,
    List<AttendanceModel> attendances,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(LucideIcons.calendarCheck, color: Color(0xFF70B843), size: 24),
              const SizedBox(width: 8),
              Flexible(child: Text(
                'Ngày $day/$month/$year',
                style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 17),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tổng giờ làm:', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 13)),
                  Flexible(child: Text('${hours.toStringAsFixed(1)} giờ', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.neutral), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tiền công ngày:', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 13)),
                  Flexible(child: Text(_formatCurrency(earnings), style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF0066CC)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text('Chi tiết các ca làm:', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              ...attendances.map((a) {
                final inTime = DateFormat('HH:mm').format(a.checkIn.toLocal());
                final outTime = a.checkOut != null ? DateFormat('HH:mm').format(a.checkOut!.toLocal()) : 'Đang ca';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.clock, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Flexible(child: Text(
                        '$inTime - $outTime (${a.totalHours.toStringAsFixed(1)}h)',
                        style: GoogleFonts.beVietnamPro(fontSize: 12.5, color: AppColors.neutral),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                      if (a.isEdited)
                        Text(' (Đã sửa)', style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.accent)),
                    ],
                  ),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Đóng', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
          ],
        );
      },
    );
  }

  // ─── BOTTOM FLOATING BAR (FOR EMPLOYEE) ───────────────────────────────────

  Widget _buildBottomActionBar({
    required BuildContext context,
    required AttendanceModel? attendance,
  }) {
    final isActive = attendance != null && attendance.isActive;
    final isDone = attendance != null && !attendance.isActive;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isActive
                          ? 'Đang trong ca làm việc'
                          : isDone
                              ? 'Đã hoàn thành ca hôm nay'
                              : 'Bạn chưa chấm công',
                      style: GoogleFonts.beVietnamPro(
                        color: isActive
                            ? AppColors.success
                            : isDone
                                ? AppColors.info
                                : const Color(0xFF4B5563),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'Vào ca: ${DateFormat('HH:mm').format(attendance.checkIn.toLocal())}'
                          : 'Nhấn Chấm công để quét QR',
                      style: GoogleFonts.beVietnamPro(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.checkIn),
                icon: const Icon(LucideIcons.fingerprint, color: Colors.white, size: 20),
                label: Text(
                  isActive ? 'Ra ca' : 'Chấm công',
                  style: GoogleFonts.beVietnamPro(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? AppColors.success : AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── HELPER: BULLETPROOF DASHED LINE DIVIDER (CUSTOM PAINTER) ──────────────

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({this.color = const Color(0xFFD1D5DB)});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 1,
      child: CustomPaint(
        painter: _DashedLinePainter(color: color),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  const _DashedLinePainter({
    required this.color,
    this.dashWidth = 4,
    this.dashSpace = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    double startX = 0;
    while (startX < size.width) {
      final endX = (startX + dashWidth).clamp(0.0, size.width);
      canvas.drawLine(Offset(startX, 0), Offset(endX, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
