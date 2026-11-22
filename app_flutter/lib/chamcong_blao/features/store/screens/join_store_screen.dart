import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../app/router.dart';
import '../../auth/providers/auth_notifier.dart';
import '../providers/store_provider.dart';
import '../providers/user_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../cc_firebase.dart';

class JoinStoreScreen extends ConsumerStatefulWidget {
  const JoinStoreScreen({super.key});

  @override
  ConsumerState<JoinStoreScreen> createState() => _JoinStoreScreenState();
}

class _JoinStoreScreenState extends ConsumerState<JoinStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _joinStore() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final code = _codeCtrl.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (code.isEmpty) {
        _showError('Vui lòng nhập mã hợp lệ');
        return;
      }
      final repo = ref.read(storeRepositoryProvider);
      final userRepo = ref.read(userRepositoryProvider);
      final user = CcFirebase.auth.currentUser;
      if (user == null) throw Exception('Chưa đăng nhập');

      final store = await repo.findStoreByCode(code);
      if (store == null) {
        _showError('Không tìm thấy cửa hàng với mã "$code"');
        return;
      }

      await repo.joinStore(store.id, user.uid);
      await userRepo.updateCurrentStoreId(user.uid, store.id);
      
      ref.invalidate(userStoresProvider);

      if (mounted) context.go('/pending-approval');
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        title: const Text(
          'Tham gia cửa hàng',
          style: TextStyle(
            fontFamily: 'BeVietnamPro',
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.logOut, color: Colors.white),
            tooltip: 'Đăng xuất',
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ],
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),

                // Icon
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.store,
                    color: AppColors.primary,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Nhập mã cửa hàng',
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.neutral,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Yêu cầu chủ cửa hàng cung cấp mã 6 ký tự',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),

                // Code input
                TextFormField(
                  controller: _codeCtrl,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9]')),
                    UpperCaseTextFormatter(),
                  ],
                  style: const TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                    color: AppColors.neutral,
                  ),
                  decoration: InputDecoration(
                    hintText: 'XXXXXX',
                    hintStyle: const TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      color: AppColors.textDisabled,
                    ),
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 2),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Vui lòng nhập mã cửa hàng';
                    }
                    if (v.trim().length != 6) {
                      return 'Mã cửa hàng phải có đúng 6 ký tự';
                    }
                    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(v.trim())) {
                      return 'Mã chỉ gồm chữ và số';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Join button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _joinStore,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.primary.withOpacity(0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Tham gia',
                            style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 28),

                // Divider
                const Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'hoặc',
                        style: TextStyle(
                          fontFamily: 'BeVietnamPro',
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: AppColors.border)),
                  ],
                ),
                const SizedBox(height: 28),

                // QR button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/join-qr'),
                    icon: const Icon(LucideIcons.scanQrCode),
                    label: const Text(
                      'Quét mã QR',
                      style: TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Logout / Switch Account Button
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      await ref.read(authNotifierProvider.notifier).signOut();
                      if (context.mounted) context.go(AppRoutes.login);
                    },
                    icon: const Icon(LucideIcons.logOut, size: 18, color: AppColors.textSecondary),
                    label: const Text(
                      'Đăng xuất / Đăng nhập tài khoản khác',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontFamily: 'BeVietnamPro',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
