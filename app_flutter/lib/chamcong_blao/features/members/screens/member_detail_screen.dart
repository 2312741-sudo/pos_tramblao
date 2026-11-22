import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../models/member_model.dart';
import '../../store/providers/store_provider.dart';

class MemberDetailScreen extends ConsumerStatefulWidget {
  final String userId;
  const MemberDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  UserRole _selectedRole = UserRole.employee;
  EmployeeType _selectedType = EmployeeType.fulltime;
  
  final _monthlySalaryCtrl = TextEditingController();
  final _hourlyRateCtrl = TextEditingController();
  final _standardHoursCtrl = TextEditingController();
  final _employeeCodeCtrl = TextEditingController();
  DateTime? _joinedAt;
  String? _selectedDepartmentId;
  bool _hideSchedule = false;

  bool _isInit = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _monthlySalaryCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _standardHoursCtrl.dispose();
    _employeeCodeCtrl.dispose();
    super.dispose();
  }

  void _initData(MemberModel member) {
    if (_isInit) return;
    _selectedRole = member.role;
    _selectedType = member.employeeType;
    _employeeCodeCtrl.text = member.employeeCode ?? '';
    _joinedAt = member.joinedAt;
    _selectedDepartmentId = member.department;
    _monthlySalaryCtrl.text = member.baseMonthlySalary.toStringAsFixed(0);
    _hourlyRateCtrl.text = member.baseHourlyRate.toStringAsFixed(0);
    _standardHoursCtrl.text = member.standardHoursPerMonth.toStringAsFixed(0);
    final store = ref.read(currentStoreProvider).valueOrNull;
    _hideSchedule = store?.hiddenScheduleUserIds.contains(widget.userId) ?? false;
    _isInit = true;
  }

  Future<void> _saveChanges(String storeId) async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      
      // Update role
      await repo.updateMemberRole(storeId, widget.userId, _selectedRole);

      // Update department
      await repo.updateMemberDepartment(storeId, widget.userId, _selectedDepartmentId);
      
      // Update salary
      double salary = _selectedType == EmployeeType.fulltime
          ? double.tryParse(_monthlySalaryCtrl.text) ?? 0
          : double.tryParse(_hourlyRateCtrl.text) ?? 0;
      double hours = double.tryParse(_standardHoursCtrl.text) ?? 208;
          
      await repo.updateMemberSalary(storeId, widget.userId, _selectedType, salary, hours);
      
      // Update employee info
      await repo.updateMemberInfo(
        storeId, 
        widget.userId, 
        _employeeCodeCtrl.text.trim(), 
        _joinedAt ?? DateTime.now()
      );

      // Update hide schedule
      await repo.toggleHideMemberSchedule(storeId, widget.userId, _hideSchedule);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lưu thành công'), backgroundColor: AppColors.success),
        );
        context.pop();
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

  Future<void> _kickMember(String storeId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận'),
        content: const Text('Bạn có chắc muốn xóa nhân viên này khỏi cửa hàng?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      await repo.kickMember(storeId, widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa nhân viên'), backgroundColor: AppColors.success),
        );
        context.pop();
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
    final storeId = ref.watch(currentStoreIdProvider);
    final store = ref.watch(currentStoreProvider).valueOrNull;
    final membersAsync = ref.watch(storeMembersProvider);
    final currentMember = ref.watch(currentMemberProvider);
    final isOwner = currentMember?.isOwner ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Chi tiết nhân viên', style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Lỗi: $err')),
        data: (members) {
          final member = members.firstWhere(
            (m) => m.userId == widget.userId,
            orElse: () => MemberModel(
              userId: '', name: 'Not Found', role: UserRole.employee, 
              status: MemberStatus.kicked, employeeType: EmployeeType.fulltime, joinedAt: DateTime.now()
            ) as dynamic, 
          );
          
          if (member.userId.isEmpty) {
            return const Center(child: Text('Không tìm thấy nhân viên.'));
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initData(member);
          });

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header info
                Row(
                  children: [
                    AvatarWidget(
                      avatarUrl: member.avatarUrl,
                      name: member.name,
                      radius: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(member.name, style: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 18, fontWeight: FontWeight.bold)),
                          if (member.phone != null) ...[
                            const SizedBox(height: 4),
                            Text(member.phone!, style: const TextStyle(fontFamily: 'BeVietnamPro', color: AppColors.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                
                const Text('Mã nhân viên', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _employeeCodeCtrl,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'VD: NV001',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Ngày vào làm', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _joinedAt ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _joinedAt = picked);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _joinedAt != null ? '${_joinedAt!.day.toString().padLeft(2, '0')}/${_joinedAt!.month.toString().padLeft(2, '0')}/${_joinedAt!.year}' : 'Chọn ngày',
                      style: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Department Setup
                const Text('Bộ phận làm việc', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: (store?.departments.any((d) => d.id == _selectedDepartmentId || d.name == _selectedDepartmentId) ?? false)
                      ? store?.departments.firstWhere((d) => d.id == _selectedDepartmentId || d.name == _selectedDepartmentId).id
                      : null,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('-- Chưa phân bộ phận --'),
                    ),
                    if (store != null)
                      ...store.departments.map(
                        (dept) => DropdownMenuItem<String?>(
                          value: dept.id,
                          child: Text('${dept.name}${dept.shortName.isNotEmpty ? ' (${dept.shortName})' : ''}'),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedDepartmentId = v);
                  },
                ),
                if (store != null && store.departments.isEmpty) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Cửa hàng chưa có danh sách bộ phận. Vào Cài đặt cửa hàng để thiết lập (Pha chế, Thu ngân, Bếp...).',
                    style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 12, color: AppColors.warning),
                  ),
                ],
                const SizedBox(height: 24),

                // Role Setup
                const Text('Vai trò', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<UserRole>(
                  value: _selectedRole,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: UserRole.employee,
                      child: Text('Nhân viên'),
                    ),
                    const DropdownMenuItem(
                      value: UserRole.manager2,
                      child: Text('Quản lý 2 (Chỉ xem lịch, tick chở/giao hàng)'),
                    ),
                    const DropdownMenuItem(
                      value: UserRole.manager1,
                      child: Text('Quản lý 1 (Toàn quyền, xếp lịch, duyệt TV mới)'),
                    ),
                    const DropdownMenuItem(
                      value: UserRole.owner,
                      child: Text('Chủ cửa hàng'),
                    ),
                    if (_selectedRole == UserRole.legacyManager)
                      const DropdownMenuItem(
                        value: UserRole.legacyManager,
                        child: Text('Quản lý (Cũ - Chưa phân loại)'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedRole = v);
                  },
                ),
                const SizedBox(height: 10),
                _buildRoleDescriptionCard(_selectedRole),
                const SizedBox(height: 24),
                
                // Employee Type Setup
                const Text('Loại hình', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<EmployeeType>(
                  value: _selectedType,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  items: EmployeeType.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedType = v);
                  },
                ),
                const SizedBox(height: 24),

                // Salary configs
                if (_selectedType == EmployeeType.fulltime) ...[
                  const Text('Lương cơ bản (tháng)', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _monthlySalaryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'VD: 5000000',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Số giờ chuẩn (tháng)', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _standardHoursCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'VD: 208',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ] else ...[
                  const Text('Lương cơ bản (giờ)', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _hourlyRateCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'VD: 20000',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    activeColor: AppColors.primary,
                    title: const Text(
                      'Ẩn lịch trên Lịch cửa hàng',
                      style: TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: const Text(
                      'Khi bật, chỉ Chủ cửa hàng mới nhìn thấy lịch của nhân viên này trên bảng Lịch cửa hàng.',
                      style: TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    value: _hideSchedule,
                    onChanged: (v) => setState(() => _hideSchedule = v),
                  ),
                ),

                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading || storeId == null ? null : () => _saveChanges(storeId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Lưu thay đổi', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: TextButton(
                      onPressed: _isLoading || storeId == null ? null : () => _kickMember(storeId),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      child: const Text('Xóa khỏi cửa hàng', style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16)),
                    ),
                  ),
                ],
              ],
            ),
          );
          },
        ),
    );
  }

  Widget _buildRoleDescriptionCard(UserRole role) {
    switch (role) {
      case UserRole.manager1:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F4F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFB3D7E8)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quyền hạn Quản lý 1 (Toàn quyền quản lý):',
                style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.info),
              ),
              SizedBox(height: 4),
              Text(
                '• Xếp ca / Sửa / Xóa lịch làm việc cho cả cửa hàng\n• Chấp nhận (duyệt) thành viên mới xin gia nhập\n• Xếp / Tick chọn Chở hàng và Giao hàng\n• Xem và chỉnh sửa bảng chấm công toàn bộ nhân viên',
                style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 11.5, color: Color(0xFF2C3E50), height: 1.4),
              ),
            ],
          ),
        );
      case UserRole.manager2:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF80CBC4)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quyền hạn Quản lý 2 (Giới hạn ca làm):',
                style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF00695C)),
              ),
              SizedBox(height: 4),
              Text(
                '• Xem lịch làm việc của cả cửa hàng (Chỉ xem)\n• Xếp / Tick chọn Chở hàng và Giao hàng\n• KHÔNG được tạo/sửa/xoá ca làm việc của nhân viên\n• KHÔNG được duyệt thành viên mới xin vào\n• KHÔNG được xem/sửa bảng chấm công của nhân viên khác',
                style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 11.5, color: Color(0xFF004D40), height: 1.4),
              ),
            ],
          ),
        );
      case UserRole.legacyManager:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFEEBA)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tài khoản Quản lý cũ (Chưa phân loại):',
                style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF856404)),
              ),
              SizedBox(height: 4),
              Text(
                'Đang tạm giữ quyền Quản lý 1. Vui lòng chọn Quản lý 1 hoặc Quản lý 2 ở trên rồi nhấn "Lưu thay đổi" để phân loại.',
                style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 11.5, color: Color(0xFF533F03), height: 1.4),
              ),
            ],
          ),
        );
      case UserRole.owner:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFDE8E8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF8B4B4)),
          ),
          child: const Text(
            'Chủ cửa hàng: Toàn quyền cao nhất trên toàn bộ hệ thống cửa hàng.',
            style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 11.5, color: Color(0xFF9B1C1C), height: 1.3),
          ),
        );
      case UserRole.employee:
        return const SizedBox.shrink();
    }
  }
}
