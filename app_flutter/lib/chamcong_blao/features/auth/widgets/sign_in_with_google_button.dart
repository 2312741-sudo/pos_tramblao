import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A Google Sign In button that visually matches [SignInWithAppleButton]
/// in height, typography, corner radius, and interaction feel.
class SignInWithGoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final double height;
  final BorderRadius borderRadius;

  const SignInWithGoogleButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.height = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    // Aligns exactly with Apple's button font scale (height * 0.43)
    final fontSize = height * 0.43;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CupertinoButton(
        borderRadius: borderRadius,
        padding: EdgeInsets.zero,
        color: Colors.white,
        disabledColor: Colors.white.withValues(alpha: 0.6),
        onPressed: onPressed,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: borderRadius,
            border: Border.all(
              color: const Color(0xFFD1D5DB),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/chamcong_blao/google_logo.png',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    inherit: false,
                    fontSize: fontSize,
                    color: const Color(0xFF1F2937),
                    fontFamily: '.SF Pro Text',
                    letterSpacing: -0.41,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
