import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../providers/auth_notifier.dart';
import '../widgets/sign_in_with_google_button.dart';
import '../../../app/router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/loading_overlay.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authNotifierProvider.notifier).signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );

    if (!mounted) return;

    if (success) {
      context.go(AppRoutes.splash);
    } else {
      final error = ref.read(authNotifierProvider).errorMessage;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final success = await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    if (success) {
      context.go(AppRoutes.splash);
    } else {
      final error = ref.read(authNotifierProvider).errorMessage;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    final success = await ref.read(authNotifierProvider.notifier).signInWithApple();
    if (!mounted) return;
    if (success) {
      context.go(AppRoutes.splash);
    } else {
      final error = ref.read(authNotifierProvider).errorMessage;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showForgotPassword() {
    final emailController = TextEditingController(text: _emailController.text.trim());
    final dialogFormKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    bool isSuccess = false;
    String? errorMessage;
    String sentEmail = '';

    showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (isSuccess) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.mailCheck,
                      color: AppColors.success,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Đã gửi email đặt lại mật khẩu',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Link đặt lại mật khẩu đã được gửi tới:\n$sentEmail',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(LucideIcons.info, color: Color(0xFFD97706), size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Lưu ý quan trọng:',
                              style: TextStyle(
                                fontFamily: 'BeVietnamPro',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '• Hãy kiểm tra kỹ mục Thư rác (Spam / Junk) hoặc Quảng cáo nếu không thấy thư ở Hộp thư đến.\n'
                          '• Nếu bạn đăng ký bằng Google hoặc Apple, hãy đăng nhập trực tiếp bằng nút Google/Apple bên dưới mà không cần mật khẩu.\n'
                          '• Nhấp vào link trong email để nhập mật khẩu mới, sau đó quay lại ứng dụng để đăng nhập.',
                          style: TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: Color(0xFF78350F),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Đã hiểu, quay lại đăng nhập',
                      style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: const [
                Icon(LucideIcons.rotateCcwKey, color: AppColors.primary, size: 24),
                SizedBox(width: 8),
                Flexible(child: Text(
                  AppStrings.forgotPassword,
                  style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.bold, fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )),
              ],
            ),
            content: Form(
              key: dialogFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nhập email của bạn để nhận link đặt lại mật khẩu:',
                    style: TextStyle(fontFamily: 'BeVietnamPro', color: AppColors.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    enabled: !isSubmitting,
                    decoration: const InputDecoration(
                      labelText: AppStrings.email,
                      hintText: AppStrings.emailHint,
                      prefixIcon: Icon(LucideIcons.mail),
                    ),
                    validator: (value) {
                      final val = value?.trim() ?? '';
                      if (val.isEmpty) {
                        return 'Vui lòng nhập địa chỉ email';
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                        return 'Địa chỉ email không đúng định dạng';
                      }
                      return null;
                    },
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.circleAlert, color: AppColors.danger, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(
                                fontFamily: 'BeVietnamPro',
                                color: AppColors.danger,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                child: const Text(AppStrings.cancel, style: TextStyle(fontFamily: 'BeVietnamPro')),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!dialogFormKey.currentState!.validate()) return;
                        final targetEmail = emailController.text.trim();
                        setDialogState(() {
                          isSubmitting = true;
                          errorMessage = null;
                        });

                        final success = await ref
                            .read(authNotifierProvider.notifier)
                            .sendPasswordResetEmail(targetEmail);

                        if (!ctx.mounted) return;

                        if (success) {
                          setDialogState(() {
                            isSubmitting = false;
                            isSuccess = true;
                            sentEmail = targetEmail;
                          });
                        } else {
                          setDialogState(() {
                            isSubmitting = false;
                            errorMessage = ref.read(authNotifierProvider).errorMessage ??
                                'Không thể gửi email đặt lại mật khẩu. Vui lòng thử lại sau.';
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        AppStrings.sendResetEmail,
                        style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: LoadingOverlay(
        isLoading: authState.isLoading,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // ── Trạm BLAO Highland Hero Banner ────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF143A2F), Color(0xFF1F5747)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22143A2F),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                                image: const DecorationImage(
                                  image: AssetImage('assets/chamcong_blao/logo.jpg'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TRẠM BLAO WORKFORCE',
                                    style: TextStyle(
                                      fontFamily: 'BeVietnamPro',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    AppStrings.appName,
                                    style: TextStyle(
                                      fontFamily: 'BeVietnamPro',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Hệ thống điều phối ca trực & tiêu chuẩn quầy Trạm Trà - Trạm Bánh',
                                    style: TextStyle(
                                      fontFamily: 'BeVietnamPro',
                                      fontSize: 12,
                                      color: Colors.white70,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildBrandChip(LucideIcons.mapPinCheck, 'GPS & WiFi Quầy'),
                            _buildBrandChip(LucideIcons.cupSoda, 'Trà Ô Long Blao'),
                            _buildBrandChip(LucideIcons.croissant, 'Bánh Lăn Nướng'),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'Đăng nhập ca trực',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dành cho Nhân viên, Quản lý & Chủ cửa hàng Trạm BLAO',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),

                  const SizedBox(height: 20),

                  // ── Email Field ───────────────────────────────────────
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: AppStrings.email,
                      hintText: AppStrings.emailHint,
                      prefixIcon: Icon(LucideIcons.mail),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppStrings.errorRequiredField;
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                          .hasMatch(value)) {
                        return AppStrings.errorInvalidEmail;
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Password Field ────────────────────────────────────
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleLogin(),
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: AppStrings.password,
                      hintText: AppStrings.passwordHint,
                      prefixIcon: const Icon(LucideIcons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppStrings.errorRequiredField;
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // ── Forgot Password ───────────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPassword,
                      child: const Text(AppStrings.forgotPassword),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Login Button ──────────────────────────────────────
                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _handleLogin,
                    child: const Text(AppStrings.login),
                  ),

                  const SizedBox(height: 24),

                  // ── Divider ───────────────────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Hoặc tiếp tục với',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                      const Expanded(child: Divider(color: AppColors.border)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Social Buttons ────────────────────────────────────
                  // Official Sign in with Apple button (Apple HIG & Design Resources Compliant)
                  SignInWithAppleButton(
                    onPressed: authState.isLoading ? () {} : _handleAppleSignIn,
                    text: Localizations.maybeLocaleOf(context)?.languageCode == 'vi'
                        ? 'Đăng nhập bằng Apple'
                        : 'Sign in with Apple',
                    height: 48,
                    style: SignInWithAppleButtonStyle.black,
                    borderRadius: BorderRadius.circular(12),
                  ),

                  const SizedBox(height: 12),

                  // Google Sign In Button (Synchronized with Apple button)
                  SignInWithGoogleButton(
                    onPressed: authState.isLoading ? null : _handleGoogleSignIn,
                    text: Localizations.maybeLocaleOf(context)?.languageCode == 'vi'
                        ? 'Đăng nhập bằng Google'
                        : 'Sign in with Google',
                    height: 48,
                    borderRadius: BorderRadius.circular(12),
                  ),

                  const SizedBox(height: 24),

                  // ── Register Link ─────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppStrings.noAccount,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => context.push(AppRoutes.register),
                        child: const Text(AppStrings.register),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'BeVietnamPro',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
