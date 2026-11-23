import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../cc_firebase.dart';
import '../constants/app_colors.dart';

/// Nút pill "Về POS" gọn nhẹ đặt trong header của các Dashboard Chấm Công.
class PosExitPillButton extends StatelessWidget {
  const PosExitPillButton({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => CcFirebase.exitModule(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.arrowLeft, color: Colors.white, size: 15),
            SizedBox(width: 4),
            Text(
              'Về POS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'BeVietnamPro',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nút "Về POS" ở góc trái AppBar/đầu trang khi đang ở tab gốc (`!canPop`).
class PosExitAppBarLeading extends StatelessWidget {
  final Color color;

  const PosExitAppBarLeading({super.key, this.color = Colors.white});

  /// Trả về nút "Về POS" nếu màn hình không thể pop trong router Chấm Công, ngược lại `null`.
  static Widget? maybeFor(BuildContext context, {Color color = Colors.white}) {
    if (Navigator.of(context).canPop()) return null;
    return PosExitAppBarLeading(color: color);
  }

  /// Chiều rộng `leadingWidth` phù hợp khi hiển thị nút "Về POS".
  static double? leadingWidthFor(BuildContext context) =>
      Navigator.of(context).canPop() ? null : 96;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color;
    return InkWell(
      onTap: () => CcFirebase.exitModule(context),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.arrowLeft, color: effectiveColor, size: 18),
            const SizedBox(width: 4),
            Text(
              'Về POS',
              style: TextStyle(
                color: effectiveColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'BeVietnamPro',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hàng tiêu đề nhỏ cho các màn hình tab không dùng AppBar chuẩn (VD: Hồ sơ Quản lý).
class PosExitTabHeader extends StatelessWidget {
  final String title;

  const PosExitTabHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const PosExitAppBarLeading(color: AppColors.neutral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'BeVietnamPro',
                color: AppColors.neutral,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
