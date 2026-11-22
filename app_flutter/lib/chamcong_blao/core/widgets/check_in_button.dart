import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../constants/app_colors.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CheckInButton extends StatefulWidget {
  final bool isCheckedIn;
  final VoidCallback? onPressed;
  final bool isLoading;

  const CheckInButton({
    super.key,
    required this.isCheckedIn,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  State<CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<CheckInButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (!widget.isCheckedIn) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(CheckInButton old) {
    super.didUpdateWidget(old);
    if (widget.isCheckedIn != old.isCheckedIn) {
      if (!widget.isCheckedIn) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.isLoading || widget.onPressed == null) return;
    setState(() => _isPressed = true);
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _isPressed = false);
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isCheckedIn ? AppColors.checkIn : AppColors.primary;
    final gradient = widget.isCheckedIn
        ? AppColors.checkInButtonGradient
        : AppColors.checkOutButtonGradient;
    final icon =
        widget.isCheckedIn ? LucideIcons.logOut : LucideIcons.fingerprint;
    final label =
        widget.isCheckedIn ? 'Chấm ra' : 'CHẤM CÔNG';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _handleTap,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulseValue = _pulseController.value * 8;
              return Container(
                width: 160 + pulseValue,
                height: 160 + pulseValue,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.1 + _pulseController.value * 0.05),
                ),
                child: child,
              );
            },
            child: AnimatedScale(
              scale: _isPressed ? 0.94 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: widget.isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: AppColors.white,
                            strokeWidth: 3,
                          ),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 52, color: AppColors.white),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        )
            .animate(target: widget.isCheckedIn ? 1 : 0)
            .tint(color: AppColors.success.withOpacity(0.1), duration: 400.ms),
        const SizedBox(height: 16),
        Text(
          widget.isCheckedIn
              ? 'Nhấn để chấm ra'
              : 'Nhấn để chấm công',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
