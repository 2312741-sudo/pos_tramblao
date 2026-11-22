import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_notifier.dart';
import '../providers/auth_provider.dart';
import '../../../app/router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/loading_overlay.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill name from Firebase Auth
    final user = ref.read(currentFirebaseUserProvider);
    if (user?.displayName != null) {
      _nameController.text = user!.displayName!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = ref.read(currentUserIdProvider);
    if (uid == null) {
      if (mounted) context.go(AppRoutes.welcome);
      return;
    }

    final success = await ref.read(authNotifierProvider.notifier).updateProfile(
          uid: uid,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
        );

    if (!mounted) return;

    if (success) {
      context.go(AppRoutes.welcome);
    } else {
      final error = ref.read(authNotifierProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? AppStrings.errorGeneral),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    return LoadingOverlay(
      isLoading: isLoading,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(AppStrings.profileSetup),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => context.go(AppRoutes.welcome),
              child: const Text(
                AppStrings.skip,
                style: TextStyle(color: AppColors.white),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Text(
                    AppStrings.profileSetup,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.profileSetupSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // ── Icon Display ──────────────────────────────────────
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.user,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Full Name ──────────────────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: AppStrings.fullName,
                      hintText: AppStrings.fullNameHint,
                      prefixIcon: Icon(LucideIcons.user),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return AppStrings.errorNameRequired;
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Phone ──────────────────────────────────────────────
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleContinue(),
                    decoration: const InputDecoration(
                      labelText: AppStrings.phoneNumber,
                      hintText: AppStrings.phoneHint,
                      prefixIcon: Icon(LucideIcons.phone),
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        if (!RegExp(r'^[0-9]{9,11}$')
                            .hasMatch(value.replaceAll(RegExp(r'[\s\-]'), ''))) {
                          return 'Số điện thoại không hợp lệ';
                        }
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 32),

                  // ── Continue Button ────────────────────────────────────
                  ElevatedButton(
                    onPressed: isLoading ? null : _handleContinue,
                    child: const Text(AppStrings.continueButton),
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
