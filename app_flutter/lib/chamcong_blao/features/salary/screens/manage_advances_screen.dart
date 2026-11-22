import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/advance_request_model.dart';
import '../../store/providers/store_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ManageAdvancesScreen extends ConsumerStatefulWidget {
  const ManageAdvancesScreen({super.key});

  @override
  ConsumerState<ManageAdvancesScreen> createState() => _ManageAdvancesScreenState();
}

class _ManageAdvancesScreenState extends ConsumerState<ManageAdvancesScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime.now();
  }

  String get _monthStr {
    return '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final advancesAsync = ref.watch(storeAdvancesProvider(_monthStr));
    final membersAsync = ref.watch(storeMembersProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Duyệt Ứng Lương', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'BeVietnamPro')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      body: Column(
        children: [
          _buildMonthSelector(),
          Expanded(
            child: advancesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (advances) {
                final pendingAdvances = advances.where((a) => a.status == AdvanceStatus.pending).toList();
                
                if (pendingAdvances.isEmpty) {
                  return const Center(child: Text('Không có yêu cầu ứng lương chờ duyệt trong tháng này.'));
                }

                return membersAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Center(child: Text('Lỗi: $e')),
                  data: (members) {
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: pendingAdvances.length,
                      itemBuilder: (context, index) {
                        final advance = pendingAdvances[index];
                        final member = members.firstWhere(
                          (m) => m.userId == advance.userId,
                          orElse: () => throw Exception('Member not found'),
                        );
                        
                        return _buildAdvanceCard(advance, member.name);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            'Tháng ${_selectedMonth.month}/${_selectedMonth.year}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'BeVietnamPro'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.chevronRight),
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvanceCard(AdvanceRequestModel advance, String memberName) {
    final formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    final requestDate = DateFormat('dd/MM/yyyy HH:mm').format(advance.requestDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    memberName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'BeVietnamPro'),
                  ),
                ),
                Flexible(child: Text(
                  formatCurrency.format(advance.amount),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary, fontFamily: 'BeVietnamPro'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Text('Ngày xin: $requestDate', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamily: 'BeVietnamPro')),
            if (advance.note != null && advance.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Ghi chú: ${advance.note}', style: const TextStyle(fontSize: 14, fontFamily: 'BeVietnamPro')),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _updateStatus(advance, AdvanceStatus.rejected),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Từ chối', style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _updateStatus(advance, AdvanceStatus.approved),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Duyệt', style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(AdvanceRequestModel advance, AdvanceStatus status) async {
    final repo = ref.read(storeRepositoryProvider);
    try {
      await repo.updateAdvanceRequestStatus(advance.storeId, advance.id, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == AdvanceStatus.approved ? 'Đã duyệt yêu cầu' : 'Đã từ chối yêu cầu'),
            backgroundColor: status == AdvanceStatus.approved ? AppColors.success : AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}
