import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';

class StoreCreationLockedDialog extends StatelessWidget {
  const StoreCreationLockedDialog({super.key});

  static const String adminName = 'Nguyễn Thanh Tâm';
  static const String hotline = '0865.062.205';
  static const String hotlineRaw = '0865062205';
  static const String email = 'nthanhtam.402@gmail.com';

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const StoreCreationLockedDialog(),
    );
  }

  Future<void> _makePhoneCall() async {
    final uri = Uri.parse('tel:$hotlineRaw');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép $label: $text'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primaryDark,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tạo Cửa Hàng Mới',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hệ Thống Trạm BLAO',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chức năng tự tạo cửa hàng mới trên hệ thống hiện đang được tạm khóa để quản lý tập trung và bảo mật dữ liệu chuỗi.',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13.5,
              color: const Color(0xFF334155),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Quý khách hoặc chủ cửa hàng cần khởi tạo chi nhánh mới, xin vui lòng liên hệ trực tiếp với quản trị viên:',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E293B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildContactRow(
                  context,
                  icon: Icons.person_outline_rounded,
                  label: 'Quản trị viên',
                  value: adminName,
                  onCopy: () => _copyToClipboard(context, adminName, 'Họ tên'),
                ),
                const Divider(height: 16),
                _buildContactRow(
                  context,
                  icon: Icons.phone_in_talk_rounded,
                  label: 'Hotline / Zalo',
                  value: hotline,
                  isHighlight: true,
                  onCopy: () => _copyToClipboard(context, hotlineRaw, 'Số điện thoại'),
                  onAction: _makePhoneCall,
                  actionTooltip: 'Gọi ngay',
                  actionIcon: Icons.call,
                ),
                const Divider(height: 16),
                _buildContactRow(
                  context,
                  icon: Icons.mail_outline_rounded,
                  label: 'Email hỗ trợ',
                  value: email,
                  onCopy: () => _copyToClipboard(context, email, 'Email'),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.primaryDark,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Đã Hiểu',
              style: GoogleFonts.beVietnamPro(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool isHighlight = false,
    VoidCallback? onCopy,
    VoidCallback? onAction,
    IconData? actionIcon,
    String? actionTooltip,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: isHighlight ? AppColors.primaryDark : const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
              Text(
                value,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isHighlight ? AppColors.primaryDark : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
        if (onAction != null && actionIcon != null)
          IconButton(
            icon: Icon(actionIcon, size: 18, color: AppColors.primaryDark),
            tooltip: actionTooltip,
            visualDensity: VisualDensity.compact,
            onPressed: onAction,
          ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF64748B)),
            tooltip: 'Sao chép',
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
          ),
      ],
    );
  }
}
