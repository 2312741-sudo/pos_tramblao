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

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authNotifierProvider.notifier).register(
          email: _emailController.text,
          password: _passwordController.text,
          name: _nameController.text.trim(),
        );

    if (!mounted) return;

    if (success) {
      context.go(AppRoutes.profileSetup);
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.register),
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: LoadingOverlay(
        isLoading: authState.isLoading,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ────────────────────────────────────────────
                  Text(
                    'Tạo tài khoản mới',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Điền thông tin để bắt đầu sử dụng ứng dụng',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),

                  const SizedBox(height: 32),

                  // ── Full Name ─────────────────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: AppStrings.fullName,
                      hintText: AppStrings.fullNameHint,
                      prefixIcon: Icon(LucideIcons.user),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return AppStrings.errorNameRequired;
                      }
                      if (value.trim().length < 2) {
                        return 'Tên phải có ít nhất 2 ký tự';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Email ─────────────────────────────────────────────
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

                  // ── Password ──────────────────────────────────────────
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
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
                          setState(
                              () => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppStrings.errorRequiredField;
                      }
                      if (value.length < 6) {
                        return AppStrings.errorWeakPassword;
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Confirm Password ──────────────────────────────────
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleRegister(),
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: AppStrings.confirmPassword,
                      hintText: AppStrings.confirmPasswordHint,
                      prefixIcon: const Icon(LucideIcons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff,
                        ),
                        onPressed: () {
                          setState(() =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppStrings.errorRequiredField;
                      }
                      if (value != _passwordController.text) {
                        return AppStrings.errorPasswordMismatch;
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 32),

                  // ── Register Button ───────────────────────────────────
                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _handleRegister,
                    child: const Text(AppStrings.register),
                  ),

                  const SizedBox(height: 24),

                  // ── Divider ───────────────────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Hoặc đăng ký nhanh bằng',
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
                        ? 'Đăng ký bằng Apple'
                        : 'Sign up with Apple',
                    height: 48,
                    style: SignInWithAppleButtonStyle.black,
                    borderRadius: BorderRadius.circular(12),
                  ),

                  const SizedBox(height: 12),

                  // Google Sign In Button (Synchronized with Apple button)
                  SignInWithGoogleButton(
                    onPressed: authState.isLoading ? null : _handleGoogleSignIn,
                    text: Localizations.maybeLocaleOf(context)?.languageCode == 'vi'
                        ? 'Đăng ký bằng Google'
                        : 'Sign up with Google',
                    height: 48,
                    borderRadius: BorderRadius.circular(12),
                  ),

                  const SizedBox(height: 24),

                  // ── Login Link ────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppStrings.haveAccount,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text(AppStrings.login),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
