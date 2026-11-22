import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class CurrencyText extends StatelessWidget {
  final double amountInVnd; // amount in actual VND
  final TextStyle? style;
  final TextAlign textAlign;
  final bool compact; // use 'tr.' suffix for thousands

  const CurrencyText({
    super.key,
    required this.amountInVnd,
    this.style,
    this.textAlign = TextAlign.start,
    this.compact = false,
  });

  /// Format amount (in full VND) as Vietnamese currency string
  /// e.g., 7680000 → '7.680.000 ₫'
  static String format(double amountInVnd) {
    if (amountInVnd == 0) return '0 vnđ';
    final rounded = amountInVnd.round();
    final isNegative = rounded < 0;
    final absValue = rounded.abs();
    final str = absValue.toString();
    final buffer = StringBuffer();
    final mod = str.length % 3;
    for (int i = 0; i < str.length; i++) {
      if (i != 0 && (i - mod) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(str[i]);
    }
    return '${isNegative ? '-' : ''}${buffer.toString()} vnđ';
  }

  /// Format amount in thousands (k VND)
  /// e.g., 7680 → '7.680.000 ₫'
  static String formatThousands(double amountInThousands) {
    return format(amountInThousands * 1000);
  }

  /// Compact format: 7680000 → '7.680 tr.'
  static String formatCompact(double amountInVnd) {
    if (amountInVnd == 0) return '0 vnđ';
    if (amountInVnd >= 1000000) {
      final million = amountInVnd / 1000000;
      if (million == million.roundToDouble()) {
        return '${million.round()} tr. vnđ';
      }
      return '${million.toStringAsFixed(1)} tr. vnđ';
    }
    if (amountInVnd >= 1000) {
      final thousand = amountInVnd / 1000;
      return '${thousand.round()}k vnđ';
    }
    return '${amountInVnd.round()} vnđ';
  }

  @override
  Widget build(BuildContext context) {
    final text = compact ? formatCompact(amountInVnd) : format(amountInVnd);
    return Text(
      text,
      style: style ??
          Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
      textAlign: textAlign,
    );
  }
}

/// Salary display for thousands-denominated values (from Firestore)
class SalaryText extends StatelessWidget {
  final double amountInThousands;
  final TextStyle? style;
  final TextAlign textAlign;

  const SalaryText({
    super.key,
    required this.amountInThousands,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return CurrencyText(
      amountInVnd: amountInThousands,
      style: style,
      textAlign: textAlign,
    );
  }
}
