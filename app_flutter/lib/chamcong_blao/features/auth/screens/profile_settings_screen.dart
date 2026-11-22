import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../models/member_model.dart';
import '../../../models/user_model.dart';
import '../../../models/store_model.dart';
import '../providers/auth_notifier.dart';
import '../providers/auth_provider.dart';
import '../../store/providers/store_provider.dart';
import '../../store/providers/user_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../cc_firebase.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  DateTime? _selectedBirthday;
  bool _isSavingProfile = false;
  bool _isSavingDept = false;
  bool _isUploadingAvatar = false;
  String? _selectedDepartmentId;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _initUserData(UserModel? userModel, MemberModel? currentMember) {
    if (_initialized) return;
    final fbUser = CcFirebase.auth.currentUser;
    _nameController.text = userModel?.name ?? fbUser?.displayName ?? '';
    _phoneController.text = userModel?.phone ?? '';
    _selectedBirthday = userModel?.birthday;
    if (currentMember != null) {
      _selectedDepartmentId = currentMember.department;
    }
    _initialized = true;
  }

  Future<void> _pickAndUploadAvatar() async {
    final uid = CcFirebase.auth.currentUser?.uid;
    if (uid == null || _isUploadingAvatar) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cập nhật ảnh đại diện',
                style: GoogleFonts.beVietnamPro(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(LucideIcons.images, color: AppColors.primary),
                title: Text('Chọn từ thư viện ảnh', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(LucideIcons.camera, color: AppColors.primary),
                title: Text('Chụp ảnh mới', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() => _isUploadingAvatar = true);
      final bytes = await pickedFile.readAsBytes();
      final store = ref.read(currentStoreProvider).valueOrNull;

      final downloadUrl = await ref.read(authNotifierProvider.notifier).uploadAvatar(
        uid: uid,
        imageBytes: bytes,
        currentStoreId: store?.id,
      );

      if (mounted) {
        if (downloadUrl != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã cập nhật ảnh đại diện thành công'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          final err = ref.read(authNotifierProvider).errorMessage ?? 'Không thể tải lên ảnh đại diện';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải ảnh: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _selectBirthday() async {
    final now = DateTime.now();
    final initialDate = _selectedBirthday ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(1940),
      lastDate: now,
      locale: const Locale('vi', 'VN'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.neutral,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedBirthday = picked;
      });
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập họ và tên'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final uid = CcFirebase.auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSavingProfile = true);
    try {
      final store = ref.read(currentStoreProvider).valueOrNull;
      final phone = _phoneController.text.trim();
      final success = await ref.read(authNotifierProvider.notifier).updateProfile(
            uid: uid,
            name: name,
            phone: phone.isEmpty ? null : phone,
            birthday: _selectedBirthday,
            currentStoreId: store?.id,
          );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã lưu thông tin hồ sơ thành công'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          final err = ref.read(authNotifierProvider).errorMessage ?? 'Không thể cập nhật hồ sơ';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingProfile = false);
      }
    }
  }

  Future<void> _saveDepartment(String storeId) async {
    final uid = CcFirebase.auth.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isSavingDept = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      await repo.updateMemberDepartment(storeId, uid, _selectedDepartmentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật bộ phận làm việc'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDept = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final currentMember = ref.watch(currentMemberProvider);
    final storeAsync = ref.watch(currentStoreProvider);
    final fbUser = CcFirebase.auth.currentUser;

    userAsync.whenData((userModel) {
      _initUserData(userModel, currentMember);
    });

    final currentDisplayName = _nameController.text.isNotEmpty
        ? _nameController.text
        : (fbUser?.displayName ?? 'Người dùng');

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        title: Text(
          'Hồ sơ của tôi',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── 1. AVATAR & HEADER CARD ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Center(
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 3),
                        ),
                        child: AvatarWidget(
                          avatarUrl: userAsync.valueOrNull?.avatarUrl ?? currentMember?.avatarUrl ?? fbUser?.photoURL,
                          name: currentDisplayName,
                          radius: 46,
                        ),
                      ),
                      if (_isUploadingAvatar)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: InkWell(
                          onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              LucideIcons.camera,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  currentDisplayName,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.neutral,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fbUser?.email ?? '',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (currentMember != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      currentMember.role.label,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 2. EDIT PROFILE FORM ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.user, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Thông tin cá nhân',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.neutral,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Full Name
                Text(
                  'Họ và tên *',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Nhập họ và tên',
                    prefixIcon: const Icon(LucideIcons.idCard, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 16),

                // Phone Number
                Text(
                  'Số điện thoại',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Nhập số điện thoại',
                    prefixIcon: const Icon(LucideIcons.phone, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 16),

                // Date of Birth (Birthday)
                Text(
                  'Ngày tháng năm sinh',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _selectBirthday,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.cake, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedBirthday != null
                                ? DateFormat('dd/MM/yyyy').format(_selectedBirthday!)
                                : 'Chọn ngày sinh (dd/MM/yyyy)',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              color: _selectedBirthday != null
                                  ? AppColors.textPrimary
                                  : Colors.grey[600],
                              fontWeight: _selectedBirthday != null ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        const Icon(LucideIcons.calendar, size: 18, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Email (Read-only)
                Text(
                  'Email đăng nhập',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    border: Border.all(color: const Color(0xFFE9ECEF)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.mail, size: 20, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          fbUser?.email ?? 'Chưa liên kết email',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13.5,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Đã liên kết',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Save Profile Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isSavingProfile ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isSavingProfile
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.save, size: 20),
                    label: Text(
                      'Lưu thông tin cá nhân',
                      style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 3. DEPARTMENT SELECTION ─────────────────────────────────────────
          storeAsync.when(
            data: (store) {
              if (store == null || store.departments.isEmpty) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.briefcase, color: AppColors.info, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Bộ phận của tôi',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.neutral,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chọn bộ phận bạn đang làm việc tại cửa hàng này.',
                      style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _DeptTile(
                            label: 'Không thuộc bộ phận nào',
                            shortName: '—',
                            isSelected: _selectedDepartmentId == null,
                            onTap: () => setState(() => _selectedDepartmentId = null),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ...store.departments.map((dept) {
                            final isSelected = _selectedDepartmentId == dept.id;
                            return Column(
                              children: [
                                _DeptTile(
                                  label: dept.name,
                                  shortName: dept.shortName,
                                  isSelected: isSelected,
                                  onTap: () => setState(() => _selectedDepartmentId = dept.id),
                                ),
                                if (dept != store.departments.last)
                                  const Divider(height: 1, indent: 16, endIndent: 16),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton(
                        onPressed: _isSavingDept ? null : () => _saveDepartment(store.id),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.info),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSavingDept
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info),
                              )
                            : Text(
                                'Cập nhật bộ phận',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.info,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // ── 4. NOTIFICATION SETTINGS ─────────────────────────────────────────
          if (currentMember?.role.isOwner == true || currentMember?.role.isManager == true) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.bellRing, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Cài đặt thông báo',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neutral,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thông báo nhân viên vào/ra ca',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Nhận thông báo thời gian thực khi nhân viên trong cửa hàng chấm công vào ca hoặc kết thúc ca.',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: userAsync.valueOrNull?.notifyShiftInOut ?? true,
                        activeColor: AppColors.primary,
                        onChanged: (val) async {
                          final uid = CcFirebase.auth.currentUser?.uid;
                          if (uid != null) {
                            try {
                              await ref.read(userRepositoryProvider).updateNotifyShiftInOut(uid, val);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Lỗi cập nhật: $e')),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── 5. ABOUT APP ───────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.push(AppRoutes.aboutApp),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          LucideIcons.info,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thông tin ứng dụng',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.neutral,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Phiên bản, chính sách bảo mật & hỗ trợ',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 14,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── 5.5 STORE MANAGEMENT (LEAVE STORE) ─────────────────────────────
          if (storeAsync.valueOrNull != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
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
                  Row(
                    children: [
                      const Icon(LucideIcons.store, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Cửa hàng hiện tại',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    storeAsync.valueOrNull!.name,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.neutral,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Vai trò của bạn: ',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          currentMember?.role.label ?? 'Nhân viên',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _confirmLeaveStore(
                      context,
                      storeAsync.valueOrNull!,
                      currentMember,
                    ),
                    icon: const Icon(LucideIcons.logOut, color: AppColors.warning, size: 18),
                    label: Text(
                      'Rời cửa hàng này',
                      style: GoogleFonts.beVietnamPro(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.warning),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── 6. ACCOUNT MANAGEMENT ───────────────────────────────────────────

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.triangleAlert, color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Quản lý tài khoản',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Xóa tài khoản vĩnh viễn khỏi hệ thống. Hành động này không thể hoàn tác.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showDeleteAccountDialog(context),
                  icon: const Icon(LucideIcons.trash2, color: AppColors.danger, size: 18),
                  label: Text(
                    'Xóa tài khoản',
                    style: GoogleFonts.beVietnamPro(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isDeleting = false;
    String? localError;

    // Detect login provider to show correct re-auth UI
    final currentUser = CcFirebase.auth.currentUser;
    final providerIds =
        currentUser?.providerData.map((p) => p.providerId).toList() ?? [];
    final isGoogleUser = providerIds.contains('google.com');
    final isAppleUser = providerIds.contains('apple.com');
    final isEmailUser = !isGoogleUser && !isAppleUser;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Xác nhận xóa tài khoản',
            style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, color: AppColors.danger),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isGoogleUser
                    ? 'Tất cả dữ liệu sẽ bị xóa hoàn toàn.\nBạn sẽ được yêu cầu đăng nhập lại Google để xác nhận.'
                    : isAppleUser
                        ? 'Tất cả dữ liệu sẽ bị xóa hoàn toàn.\nBạn sẽ được yêu cầu xác nhận qua Apple ID.'
                        : 'Tất cả dữ liệu tài khoản sẽ bị xóa hoàn toàn. Nhập mật khẩu để xác nhận:',
                style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.neutral),
              ),
              // Chỉ hiển thị password field cho email/password users
              if (isEmailUser) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: Icon(obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff),
                      onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                ),
              ],
              if (localError != null) ...[
                const SizedBox(height: 8),
                Text(
                  localError!,
                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(dialogCtx),
              child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.neutral)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              onPressed: isDeleting
                  ? null
                  : () async {
                      // Email users phải nhập password
                      if (isEmailUser && passwordController.text.trim().isEmpty) {
                        setDialogState(() => localError = 'Vui lòng nhập mật khẩu');
                        return;
                      }

                      setDialogState(() {
                        isDeleting = true;
                        localError = null;
                      });

                      final success = await ref
                          .read(authNotifierProvider.notifier)
                          .deleteAccount(
                            password: isEmailUser
                                ? passwordController.text.trim()
                                : null,
                          );

                      if (!dialogCtx.mounted) return;

                      if (success) {
                        Navigator.pop(dialogCtx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tài khoản đã được xóa vĩnh viễn'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                          context.go(AppRoutes.login);
                        }
                      } else {
                        final errMsg = ref.read(authNotifierProvider).errorMessage ?? 'Không thể xóa tài khoản';
                        setDialogState(() {
                          isDeleting = false;
                          localError = errMsg;
                        });
                      }
                    },
              child: isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isGoogleUser
                          ? 'Tiếp tục với Google'
                          : isAppleUser
                              ? 'Tiếp tục với Apple'
                              : 'Xóa vĩnh viễn',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLeaveStore(
    BuildContext context,
    StoreModel store,
    MemberModel? currentMember,
  ) async {
    final repo = ref.read(storeRepositoryProvider);
    final isOwner = currentMember?.isOwner ?? false;

    String? successorName;
    bool isAlone = false;

    if (isOwner) {
      final currentUserId = CcFirebase.auth.currentUser?.uid ?? '';
      final nextOwnerId = await repo.findNextOwnerId(store.id, currentUserId);
      if (nextOwnerId != null) {
        final memberDoc = await CcFirebase.firestore
            .collection('stores')
            .doc(store.id)
            .collection('members')
            .doc(nextOwnerId)
            .get();
        successorName = memberDoc.data()?['name'] as String? ?? 'Quản lý 1';
      } else {
        isAlone = true;
      }
    }

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.triangleAlert, color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            Text(
              'Rời cửa hàng',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          isOwner
              ? (isAlone
                  ? 'Bạn là thành viên duy nhất của "${store.name}".\n\nKhi bạn rời đi, cửa hàng sẽ tự động đóng và không thể hoàn tác. Bạn có chắc chắn muốn rời cửa hàng?'
                  : 'Bạn đang là Chủ cửa hàng "${store.name}".\n\nKhi bạn rời đi, quyền Chủ cửa hàng sẽ được TỰ ĐỘNG CHUYỂN GIAO cho: $successorName.\n\nBạn có chắc chắn muốn rời cửa hàng?')
              : 'Bạn có chắc chắn muốn rời khỏi cửa hàng "${store.name}"?',
          style: GoogleFonts.beVietnamPro(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.neutral)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Xác nhận rời'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await repo.leaveStore(store.id);

        if (!context.mounted) return;

        // Invalidate providers
        ref.invalidate(userStoresProvider);
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStoreProvider);
        ref.invalidate(currentMemberStreamProvider);
        ref.invalidate(currentMemberProvider);
        ref.invalidate(storeMembersProvider);
        ref.invalidate(activeMembersProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bạn đã rời khỏi cửa hàng "${store.name}"'),
            backgroundColor: AppColors.success,
          ),
        );

        context.go(AppRoutes.splash);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rời cửa hàng thất bại: $e'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    }
  }
}



class _DeptTile extends StatelessWidget {
  final String label;
  final String shortName;
  final bool isSelected;
  final VoidCallback onTap;

  const _DeptTile({
    required this.label,
    required this.shortName,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.12)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  shortName,
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'BeVietnamPro',
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.primary : AppColors.neutral,
                ),
              ),
            ),
            if (isSelected)
              const Icon(LucideIcons.circleCheck,
                  color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}
