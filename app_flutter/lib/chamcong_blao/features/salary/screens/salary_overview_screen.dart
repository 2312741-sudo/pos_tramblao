import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/member_model.dart';
import '../../store/providers/store_provider.dart';
import '../providers/salary_provider.dart';
import '../../../models/advance_request_model.dart';
import '../../../core/utils/excel_export_service.dart';
import '../../../core/widgets/export_modal.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SalaryOverviewScreen extends ConsumerWidget {
  const SalaryOverviewScreen({super.key});

  void _selectMonth(BuildContext context, WidgetRef ref) async {
    // Simple month picker using dialog (for simplicity, or we can just use showDatePicker focusing on month)
    final now = DateTime.now();
    final firstDate = DateTime(2020);
    
    final currentStr = ref.read(selectedSalaryMonthProvider);
    final currentParts = currentStr.split('-');
    DateTime initialDate = now;
    if (currentParts.length == 2) {
      initialDate = DateTime(int.tryParse(currentParts[0]) ?? now.year, int.tryParse(currentParts[1]) ?? now.month);
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary, onPrimary: Colors.white, onSurface: AppColors.neutral),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
      ref.read(selectedSalaryMonthProvider.notifier).state = formatted;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeId = ref.watch(currentStoreIdProvider);
    final monthStr = ref.watch(selectedSalaryMonthProvider); // YYYY-MM

    if (storeId == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Always watch all providers unconditionally at the top level
    final membersAsync = ref.watch(allActiveMembersProvider(storeId));
    final salariesAsync = ref.watch(allSalariesProvider(monthStr));
    final specialCountsAsync = ref.watch(allMonthlySpecialCountsProvider(monthStr));
    final storeAsync = ref.watch(currentStoreProvider);
    final advancesAsync = ref.watch(storeAdvancesProvider(monthStr));

    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

    if (membersAsync.isLoading || salariesAsync.isLoading || specialCountsAsync.isLoading || storeAsync.isLoading || advancesAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (membersAsync.hasError || salariesAsync.hasError || specialCountsAsync.hasError || storeAsync.hasError || advancesAsync.hasError) {
      final e = membersAsync.error ?? salariesAsync.error ?? specialCountsAsync.error ?? storeAsync.error ?? advancesAsync.error;
      return Scaffold(body: Center(child: Text('Lỗi: $e')));
    }

    final members = membersAsync.valueOrNull ?? [];
    final salaries = salariesAsync.valueOrNull ?? {};
    final specialCounts = specialCountsAsync.valueOrNull ?? {};
    final store = storeAsync.valueOrNull;
    final advances = advancesAsync.valueOrNull ?? [];

    List<Map<String, dynamic>> computedSalaries = [];
    double totalPayout = 0;
    
    for (var member in members) {
      final salaryData = salaries[member.userId];
      final totalHours = salaryData?['totalHours'] ?? 0.0;
      double calculatedSalary = 0;
      
      if (member.employeeType == EmployeeType.fulltime) {
        calculatedSalary = member.baseMonthlySalary * (totalHours / member.standardHoursPerMonth);
      } else {
        calculatedSalary = totalHours * member.baseHourlyRate;
      }

      final counts = specialCounts[member.userId] ?? (delivery: 0, giaoHang: 0);
      final deliveryCount = counts.delivery;
      final giaoHangCount = counts.giaoHang;
      final deliveryPay = deliveryCount * (store?.deliveryAllowance ?? 0);
      final giaoHangPay = giaoHangCount * (store?.giaoHangAllowance ?? 0);
      calculatedSalary += deliveryPay + giaoHangPay;
      totalPayout += calculatedSalary;

      final memberAdvances = advances.where((a) => a.userId == member.userId && a.status == AdvanceStatus.approved);
      final totalAdvance = memberAdvances.fold(0.0, (sum, a) => sum + a.amount);
      final netSalary = calculatedSalary - totalAdvance;
      
      computedSalaries.add({
        'userId': member.userId,
        'name': member.name,
        'role': member.role.label,
        'type': member.employeeType == EmployeeType.fulltime ? 'Toàn thời gian' : 'Bán thời gian',
        'totalHours': totalHours,
        'baseSalary': member.employeeType == EmployeeType.fulltime ? member.baseMonthlySalary : member.baseHourlyRate,
        'deliveryCount': deliveryCount,
        'deliveryPay': deliveryPay,
        'giaoHangCount': giaoHangCount,
        'giaoHangPay': giaoHangPay,
        'advance': totalAdvance,
        'netSalary': netSalary,
        'member': member,
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Báo cáo Lương', style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.download),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => ExportModal(
                  title: 'Xuất Báo cáo Lương',
                  members: members,
                  onExport: ({memberId, required isMonth, monthDate, startDate, endDate}) async {
                    try {
                      final filteredSalaries = memberId != null 
                          ? computedSalaries.where((s) => s['userId'] == memberId).toList()
                          : computedSalaries;
                      final selectedMemberName = memberId != null
                          ? members.where((m) => m.userId == memberId).firstOrNull?.name
                          : null;
                      await ExcelExportService.exportMonthlySalary(
                        storeName: store?.name ?? '',
                        themeColorHex: store?.themeColor ?? '#C8102E',
                        computedSalaries: filteredSalaries,
                        suffix: isMonth ? '${monthDate!.year}-${monthDate.month.toString().padLeft(2, '0')}' : 'Filter',
                        memberOrder: store?.memberOrder ?? [],
                        memberName: selectedMemberName,
                        context: context,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xuất file: $e'), backgroundColor: AppColors.primary));
                      }
                    }
                  },
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.calendar, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text('Tháng: $monthStr', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  OutlinedButton(
                    onPressed: () => _selectMonth(context, ref),
                    child: Text('Chọn tháng', style: GoogleFonts.beVietnamPro()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildSummaryCard(totalPayout, currencyFormat),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final data = computedSalaries[index];
                          return _buildSalaryCard(context, data, currencyFormat);
                        },
                        childCount: computedSalaries.length,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(double total, NumberFormat currencyFormat) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tổng chi trả lương thực tế', style: TextStyle(color: Colors.white70)),
          Text(currencyFormat.format(total), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSalaryCard(BuildContext context, Map<String, dynamic> data, NumberFormat currencyFormat) {
    final member = data['member'] as MemberModel;
    final deliveryCount = data['deliveryCount'] as int;
    final giaoHangCount = data['giaoHangCount'] as int;
    final advanceTotal = data['advance'] as double;
    final netSalary = data['netSalary'] as double;
    final calculatedSalary = netSalary + advanceTotal; // Recover the calculated salary before advance

    return InkWell(
      onTap: () {
        context.push(
          Uri(
            path: AppRoutes.salary,
            queryParameters: {
              'userId': member.userId,
              'memberName': member.name,
            },
          ).toString(),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surface,
                child: Text(member.initials, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('Lương cơ bản: ${currencyFormat.format(data['baseSalary'])}đ', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
                    if (deliveryCount > 0)
                      Text('Phụ cấp chở hàng: $deliveryCount ca x ${currencyFormat.format(data['deliveryPay'] / deliveryCount)}đ', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
                    if (giaoHangCount > 0)
                      Text('Phụ cấp giao hàng: $giaoHangCount ca x ${currencyFormat.format(data['giaoHangPay'] / giaoHangCount)}đ', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
                    if (advanceTotal > 0)
                      Text('Đã tạm ứng: -${currencyFormat.format(advanceTotal)}đ', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.danger)),
                  ],
                ),
              ),
              Text(
                currencyFormat.format(netSalary),
                style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tổng lương thu nhập', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(
                      currencyFormat.format(calculatedSalary),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (advanceTotal > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Đã tạm ứng', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text(
                        '-${currencyFormat.format(advanceTotal)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}
