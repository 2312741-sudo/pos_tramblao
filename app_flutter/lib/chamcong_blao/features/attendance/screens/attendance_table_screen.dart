import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../core/utils/excel_export_service.dart';
import '../../../core/widgets/export_modal.dart';
import '../../../core/auth/app_permissions.dart';
import '../../../models/member_model.dart';
import '../../store/providers/store_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../repositories/attendance_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final dailyAttendancesProvider =
    StreamProvider.family<List<dynamic>, DateTime>((ref, date) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value([]);
  final repo = ref.watch(attendanceRepositoryProvider);
  final dateString =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return repo.watchAllAttendances(storeId, dateString);
});

class AttendanceTableScreen extends ConsumerWidget {
  const AttendanceTableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeId = ref.watch(currentStoreIdProvider);
    final membersAsync = ref.watch(storeMembersProvider);
    final store = ref.watch(currentStoreProvider).valueOrNull;
    final currentMember = ref.watch(currentMemberProvider);
    final currentUid = ref.watch(currentUserIdProvider);
    final isStoreOwner = store?.isOwnerUid(currentUid) ?? false;
    final canView = isStoreOwner || AppPermissions.canViewAllAttendance(currentMember?.role);

    if (!canView) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Bảng công', style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.lock, size: 40, color: AppColors.primary),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Không có quyền truy cập',
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.neutral,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Quản lý 2 không có quyền xem bảng chấm công của nhân viên khác.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Quay lại', style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Bảng công',
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
            icon: const Icon(LucideIcons.download),
            tooltip: 'Xuất Excel Tháng',
            onPressed: () {
              final membersData = membersAsync.valueOrNull;
              if (storeId != null && membersData != null && store != null) {
                final activeMembers = membersData
                    .where((m) => m.status == MemberStatus.active)
                    .toList();
                if (store.memberOrder.isNotEmpty) {
                  activeMembers.sort((a, b) {
                    final idxA = store.memberOrder.indexOf(a.userId);
                    final idxB = store.memberOrder.indexOf(b.userId);
                    if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
                    if (idxA != -1) return -1;
                    if (idxB != -1) return 1;
                    return a.name.compareTo(b.name);
                  });
                }
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ExportModal(
                    title: 'Xuất Bảng Công',
                    members: activeMembers,
                    onExport: ({memberId, required isMonth, monthDate, startDate, endDate}) async {
                      try {
                        final repo = ref.read(attendanceRepositoryProvider);
                        List<dynamic> attendances = [];
                        
                        if (isMonth && monthDate != null) {
                          final monthStr = '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}';
                          attendances = await repo.getMonthAttendances(storeId, monthStr);
                        } else if (!isMonth && startDate != null && endDate != null) {
                          final startStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
                          final endStr = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
                          attendances = await repo.getAttendancesInRange(storeId, startStr, endStr);
                        }
                        
                        final filteredMembers = memberId != null 
                            ? activeMembers.where((m) => m.userId == memberId).toList()
                            : activeMembers;
                            
                        await ExcelExportService.exportMonthlyAttendance(
                          members: filteredMembers,
                          attendances: attendances.cast(),
                          month: isMonth ? '${monthDate!.year}-${monthDate.month.toString().padLeft(2, '0')}' : '',
                          store: store,
                          startDate: !isMonth ? startDate : null,
                          endDate: !isMonth ? endDate : null,
                          memberName: memberId != null ? filteredMembers.first.name : null,
                          context: context,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Lỗi xuất file: $e'),
                              backgroundColor: AppColors.primary));
                        }
                      }
                    },
                  ),
                );
              }
            },
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.salaryOverview),
            child: const Text('Lương',
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'BeVietnamPro',
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: membersAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (allMembers) {
          final members =
              allMembers.where((m) => m.status == MemberStatus.active).toList();
          if (store != null && store.memberOrder.isNotEmpty) {
            members.sort((a, b) {
              final idxA = store.memberOrder.indexOf(a.userId);
              final idxB = store.memberOrder.indexOf(b.userId);
              if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
              if (idxA != -1) return -1;
              if (idxB != -1) return 1;
              return a.name.compareTo(b.name);
            });
          }

          if (members.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.userX,
                      size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text('Cửa hàng chưa có nhân viên nào',
                      style: TextStyle(
                          fontFamily: 'BeVietnamPro',
                          color: AppColors.textSecondary,
                          fontSize: 15)),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header hint
              Container(
                width: double.infinity,
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(LucideIcons.pointer,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Chọn nhân viên để xem bảng công tháng',
                        style: TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 13,
                            color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${members.length} NV',
                        style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),

              // Member list
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return _MemberCard(member: member);
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

class _MemberCard extends StatelessWidget {
  final MemberModel member;

  const _MemberCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final roleColors = {
      UserRole.owner: AppColors.ownerBadge,
      UserRole.manager1: AppColors.managerBadge,
      UserRole.manager2: AppColors.managerBadge,
      UserRole.legacyManager: const Color(0xFFE65100),
      UserRole.employee: AppColors.textSecondary,
    };
    final roleColor = roleColors[member.role] ?? AppColors.textSecondary;

    return GestureDetector(
      onTap: () {
        context.push(AppRoutes.monthlyAttendance, extra: {
          'memberId': member.userId,
          'memberName': member.name,
        });
      },
      child: Container(
        padding: const EdgeInsets.all(14),
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
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withOpacity(0.12),
              backgroundImage: getAvatarImageProvider(member.avatarUrl),
              child: getAvatarImageProvider(member.avatarUrl) == null
                  ? Text(member.initials,
                      style: const TextStyle(
                          fontFamily: 'BeVietnamPro',
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 16))
                  : null,
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name,
                      style: const TextStyle(
                          fontFamily: 'BeVietnamPro',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.neutral)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(member.role.label,
                            style: TextStyle(
                                fontFamily: 'BeVietnamPro',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: roleColor)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Chevron
            const Icon(LucideIcons.calendarDays,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronRight,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
