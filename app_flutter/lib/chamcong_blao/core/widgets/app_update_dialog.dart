import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../services/app_update_service.dart';

/// Hộp thoại thông báo và tải bản cập nhật APK trực tiếp trên máy
class AppUpdateDialog extends StatefulWidget {
  final AppVersionControlModel config;
  final bool isForce;
  final String currentVersion;

  const AppUpdateDialog({
    super.key,
    required this.config,
    this.isForce = false,
    required this.currentVersion,
  });

  /// Hàm tiện ích hiển thị Dialog cập nhật
  static Future<void> show(
    BuildContext context, {
    required AppVersionControlModel config,
    bool isForce = false,
    required String currentVersion,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (ctx) => PopScope(
        canPop: !isForce,
        child: AppUpdateDialog(
          config: config,
          isForce: isForce,
          currentVersion: currentVersion,
        ),
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String _status = '';
  String? _errorMessage;
  File? _downloadedFile;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  bool get _isAndroidApkSupported {
    final apkUrl = widget.config.apkUrl;
    return !kIsWeb &&
        Platform.isAndroid &&
        apkUrl != null &&
        apkUrl.trim().isNotEmpty;
  }

  Future<void> _startDownload() async {
    final apkUrl = widget.config.apkUrl;
    if (apkUrl == null || apkUrl.trim().isEmpty) return;

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _status = 'Đang kết nối máy chủ...';
    });

    try {
      final file = await AppUpdateService().downloadApkFile(
        apkUrl.trim(),
        onProgress: (p, received, total) {
          if (mounted) {
            setState(() {
              _progress = p;
              _receivedBytes = received;
              _totalBytes = total;
            });
          }
        },
        onStatusChange: (status) {
          if (mounted) {
            setState(() {
              _status = status;
            });
          }
        },
      );

      _downloadedFile = file;

      if (mounted) {
        setState(() {
          _status = 'Đã tải xong, đang mở trình cài đặt...';
        });
      }

      // Kích hoạt PackageInstaller của Android
      final openRes = await AppUpdateService().installApk(file.path);
      if (openRes.type != ResultType.done && mounted) {
        setState(() {
          _status =
              'Vui lòng nhấn nút "Cài đặt bản cập nhật" bên dưới nếu chưa thấy màn hình cập nhật';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Lỗi tải cập nhật: $e';
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _reInstall() async {
    if (_downloadedFile == null) return;
    try {
      final openRes =
          await AppUpdateService().installApk(_downloadedFile!.path);
      if (openRes.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              openRes.message.isNotEmpty
                  ? openRes.message
                  : 'Không thể mở trình cài đặt APK',
              style: GoogleFonts.beVietnamPro(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lỗi mở trình cài đặt: $e',
              style: GoogleFonts.beVietnamPro(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleUpdatePress() async {
    if (_isAndroidApkSupported) {
      await _startDownload();
    } else {
      final url = widget.config.targetStoreUrl;
      try {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        debugPrint('Failed to launch target store URL: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Không thể mở liên kết cập nhật',
                style: GoogleFonts.beVietnamPro(),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForce = widget.isForce;
    final primaryActionColor =
        isForce ? const Color(0xFFDC2626) : AppColors.primary;
    final primaryTextColor =
        isForce ? Colors.white : AppColors.primaryDark;

    return PopScope(
      canPop: !isForce && !_isDownloading,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        elevation: 8,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Banner
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                  decoration: BoxDecoration(
                    color: isForce
                        ? const Color(0xFFDC2626).withValues(alpha: 0.08)
                        : AppColors.primary.withValues(alpha: 0.15),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isForce
                              ? const Color(0xFFDC2626)
                              : AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (isForce
                                      ? const Color(0xFFDC2626)
                                      : AppColors.primary)
                                  .withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          isForce
                              ? LucideIcons.triangleAlert
                              : LucideIcons.sparkles,
                          color: isForce ? Colors.white : AppColors.primaryDark,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isForce
                            ? 'Bắt buộc cập nhật ứng dụng'
                            : 'Đã có phiên bản mới',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Phiên bản mới: v${widget.config.latestVersion} (Hiện tại: v${widget.currentVersion})',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isForce
                              ? const Color(0xFFB91C1C)
                              : AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Version info card
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Phiên bản hiện tại:',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12.5,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  'v${widget.currentVersion}',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Phiên bản mới:',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12.5,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  'v${widget.config.latestVersion}',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                            if (isForce) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Yêu cầu:',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12.5,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    'Bắt buộc cập nhật',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Changelog / Update message
                      Text(
                        'Nội dung cập nhật:',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            widget.config.updateMessage.isNotEmpty
                                ? widget.config.updateMessage
                                : 'Đã có phiên bản mới với nhiều cải tiến và sửa lỗi quan trọng. Vui lòng cập nhật ứng dụng.',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: const Color(0xFF334155),
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),

                      // Force warning banner if mandatory
                      if (isForce) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.alertCircle,
                                color: Color(0xFFDC2626),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Phiên bản hiện tại không còn được hỗ trợ. Bạn cần cập nhật để tiếp tục sử dụng.',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 11.5,
                                    color: const Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Progress indicator when downloading
                      if (_isDownloading) ...[
                        const SizedBox(height: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _status.isNotEmpty
                                        ? _status
                                        : 'Đang tải bản cập nhật...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${(_progress * 100).toInt()}%',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: _progress > 0 ? _progress : null,
                                minHeight: 8,
                                backgroundColor: const Color(0xFFE2E8F0),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.primaryDark),
                              ),
                            ),
                            if (_totalBytes > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],

                      // Error box if failed
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                LucideIcons.alertCircle,
                                color: Color(0xFFDC2626),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    color: const Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Actions
                      if (!_isDownloading && _downloadedFile == null) ...[
                        Row(
                          children: [
                            if (!isForce) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 12),
                                    side: const BorderSide(
                                        color: Color(0xFFCBD5E1)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Để sau',
                                      style: GoogleFonts.beVietnamPro(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _handleUpdatePress,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryActionColor,
                                  foregroundColor: primaryTextColor,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _errorMessage != null
                                            ? LucideIcons.refreshCw
                                            : LucideIcons.download,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _errorMessage != null
                                            ? 'Thử lại'
                                            : 'Cập nhật ngay',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (_downloadedFile != null) ...[
                        ElevatedButton.icon(
                          onPressed: _reInstall,
                          icon: const Icon(LucideIcons.refreshCw, size: 16),
                          label: Text(
                            'Cài đặt bản cập nhật',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ],
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
