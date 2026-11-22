import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../models/member_model.dart';
import '../../../models/store_model.dart';
import '../../store/providers/store_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MembersListScreen extends ConsumerWidget {
  const MembersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeMembers = ref.watch(activeMembersProvider);
    final store = ref.watch(currentStoreProvider).valueOrNull;
    final currentMember = ref.watch(currentMemberStreamProvider).valueOrNull;
    final isOwner = currentMember?.isOwner ?? false;

    // Chạy ghost-member cleanup background mỗi khi màn hình này được mở.
    // Phát hiện nhân viên bị xóa tài khoản nhưng vẫn còn trong store,
    // và tự động kick họ khỏi danh sách. Không block UI.
    ref.watch(ghostMemberCleanupProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Danh sách nhân viên',
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
          IconButton(
            icon: const Icon(LucideIcons.userPlus),
            tooltip: 'Yêu cầu chờ duyệt',
            onPressed: () {
              context.push(AppRoutes.pendingMembers);
            },
          ),
        ],
      ),
      body: activeMembers.isEmpty
          ? const Center(
              child: Text(
                'Chưa có nhân viên nào trong cửa hàng.',
                style: TextStyle(
                    fontFamily: 'BeVietnamPro', color: AppColors.textSecondary),
              ),
            )
          : isOwner
              ? ReorderableListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: activeMembers.length,
                  onReorder: (oldIndex, newIndex) {
                    if (oldIndex < newIndex) newIndex -= 1;
                    final items = List<MemberModel>.from(activeMembers);
                    final item = items.removeAt(oldIndex);
                    items.insert(newIndex, item);
                    final newOrder = items.map((m) => m.userId).toList();
                    if (store != null) {
                      ref
                          .read(storeRepositoryProvider)
                          .updateMemberOrder(store.id, newOrder);
                    }
                  },
                  itemBuilder: (context, index) {
                    final member = activeMembers[index];
                    final isHidden = store?.hiddenScheduleUserIds
                            .contains(member.userId) ??
                        false;
                    return Padding(
                      key: ValueKey(member.userId),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildMemberCard(
                        context,
                        member,
                        key: ValueKey('card_${member.userId}'),
                        isOwner: isOwner,
                        isHidden: isHidden,
                        index: index,
                        store: store,
                      ),
                    );
                  },
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: activeMembers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final member = activeMembers[index];
                    final isHidden = store?.hiddenScheduleUserIds
                            .contains(member.userId) ??
                        false;
                    return _buildMemberCard(
                      context,
                      member,
                      key: ValueKey(member.userId),
                      isOwner: isOwner,
                      isHidden: isHidden,
                      index: index,
                      store: store,
                    );
                  },
                ),
    );
  }

  Widget _buildMemberCard(
    BuildContext context,
    MemberModel member, {
    required Key key,
    required bool isOwner,
    required bool isHidden,
    required int index,
    StoreModel? store,
  }) {
    return InkWell(
      key: key,
      onTap: () {
        context.push(AppRoutes.memberDetail, extra: {'userId': member.userId});
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            if (isOwner) ...[
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(LucideIcons.gripHorizontal,
                      color: AppColors.textDisabled, size: 20),
                ),
              ),
            ],
            AvatarWidget(
              avatarUrl: member.avatarUrl,
              name: member.name,
              radius: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          member.name,
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.neutral,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isHidden) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFFEEBA)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.eyeOff,
                                  size: 11, color: Color(0xFFD9480F)),
                              SizedBox(width: 3),
                              Text(
                                'Ẩn lịch',
                                style: TextStyle(
                                  fontFamily: 'BeVietnamPro',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFD9480F),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Wrap: nhiều nhãn (vai trò, bộ phận, loại NV) tự xuống dòng trên màn hẹp
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getRoleColor(member.role).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          member.role.shortLabel,
                          style: TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _getRoleColor(member.role),
                          ),
                        ),
                      ),
                      if (member.department != null && member.department!.isNotEmpty) ...[
                        Builder(
                          builder: (context) {
                            final dept = store?.departments.cast<DepartmentDefinition?>().firstWhere(
                              (d) => d?.id == member.department || d?.name == member.department,
                              orElse: () => null,
                            );
                            final deptName = dept?.name ?? member.department!;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFBAE6FD)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.building,
                                      size: 11, color: Color(0xFF0369A1)),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      deptName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'BeVietnamPro',
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0369A1),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      if (member.isLegacyManager) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFFEEBA)),
                          ),
                          child: const Text(
                            'Cần phân loại',
                            style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF856404),
                            ),
                          ),
                        ),
                      ],
                      Text(
                        member.employeeType.shortLabel,
                        style: const TextStyle(
                          fontFamily: 'BeVietnamPro',
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight,
                color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return AppColors.ownerBadge;
      case UserRole.manager1:
        return AppColors.managerBadge;
      case UserRole.manager2:
        return AppColors.managerBadge;
      case UserRole.legacyManager:
        return const Color(0xFFE65100);
      case UserRole.employee:
        return AppColors.success;
    }
  }
}
