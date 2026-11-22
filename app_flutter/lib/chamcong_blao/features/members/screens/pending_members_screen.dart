import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../models/member_model.dart';
import '../../store/providers/store_provider.dart';

class PendingMembersScreen extends ConsumerStatefulWidget {
  const PendingMembersScreen({super.key});

  @override
  ConsumerState<PendingMembersScreen> createState() => _PendingMembersScreenState();
}

class _PendingMembersScreenState extends ConsumerState<PendingMembersScreen> {
  bool _isLoading = false;

  Future<void> _handleDecision(String storeId, String userId, bool approve) async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      await repo.approveOrRejectMember(storeId, userId, approve);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'Đã duyệt thành viên' : 'Đã từ chối thành viên'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.primary),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingMembersAsync = ref.watch(pendingMembersProvider);
    final storeId = ref.watch(currentStoreIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Yêu cầu tham gia', style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        elevation: 0,
      ),
      body: pendingMembersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (err, _) => Center(child: Text('Lỗi: $err')),
        data: (members) {
          if (members.isEmpty) {
            return const Center(
              child: Text(
                'Không có yêu cầu tham gia nào.',
                style: TextStyle(fontFamily: 'BeVietnamPro', color: AppColors.textSecondary),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final member = members[index];
              return _buildPendingCard(context, storeId, member);
            },
          );
        },
      ),
    );
  }

  Widget _buildPendingCard(BuildContext context, String? storeId, MemberModel member) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: getAvatarImageProvider(member.avatarUrl),
                child: getAvatarImageProvider(member.avatarUrl) == null
                    ? Text(
                        member.initials,
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.neutral,
                      ),
                    ),
                    if (member.phone != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        member.phone!,
                        style: const TextStyle(
                          fontFamily: 'BeVietnamPro',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading || storeId == null ? null : () => _handleDecision(storeId, member.userId, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Từ chối'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading || storeId == null ? null : () => _handleDecision(storeId, member.userId, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Chấp nhận'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
