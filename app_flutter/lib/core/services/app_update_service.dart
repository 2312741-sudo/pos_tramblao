// lib/core/services/app_update_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/version_utils.dart';

class AppVersionControlModel {
  final String latestVersion;
  final String minimumRequiredVersion;
  final String updateMessage;
  final String? updateUrlIos;
  final String? updateUrlAndroid;
  final String? updateUrl;

  const AppVersionControlModel({
    required this.latestVersion,
    required this.minimumRequiredVersion,
    required this.updateMessage,
    this.updateUrlIos,
    this.updateUrlAndroid,
    this.updateUrl,
  });

  factory AppVersionControlModel.fromMap(Map<dynamic, dynamic> data) {
    return AppVersionControlModel(
      latestVersion: data['latestVersion']?.toString() ?? '1.0.0',
      minimumRequiredVersion: data['minimumRequiredVersion']?.toString() ?? '1.0.0',
      updateMessage: data['updateMessage']?.toString() ??
          'Đã có phiên bản POS Trạm BLAO mới với nhiều cải tiến và tối ưu hóa hệ thống. Vui lòng cập nhật ứng dụng.',
      updateUrlIos: data['updateUrlIos']?.toString() ??
          'https://apps.apple.com/app/id6742385802',
      updateUrlAndroid: data['updateUrlAndroid']?.toString() ??
          'https://play.google.com/store/apps/details?id=com.tramblao.pos',
      updateUrl: data['updateUrl']?.toString() ?? 'https://pos-tramblao.vercel.app',
    );
  }

  String get targetStoreUrl {
    if (kIsWeb) {
      return updateUrl ?? 'https://pos-tramblao.vercel.app';
    }
    if (Platform.isIOS) {
      return updateUrlIos ?? updateUrl ?? 'https://apps.apple.com/app/id6742385802';
    }
    if (Platform.isAndroid) {
      return updateUrlAndroid ?? updateUrl ?? 'https://play.google.com/store/apps/details?id=com.tramblao.pos';
    }
    return updateUrl ?? 'https://pos-tramblao.vercel.app';
  }
}

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  bool _isDialogShowing = false;

  /// Fetches version control configuration.
  /// Tries Realtime Database `/app_config/version_control` first,
  /// then falls back to Firestore `app_config/version_control`.
  Future<AppVersionControlModel?> fetchVersionConfig() async {
    // 1. Try Realtime Database
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('app_config/version_control')
          .get()
          .timeout(const Duration(seconds: 4));
      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        return AppVersionControlModel.fromMap(snapshot.value as Map);
      }
    } catch (e) {
      debugPrint('[AppUpdateService] RTDB fetch version_control error: $e');
    }

    // 2. Fallback to Cloud Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version_control')
          .get()
          .timeout(const Duration(seconds: 4));
      if (doc.exists && doc.data() != null) {
        return AppVersionControlModel.fromMap(doc.data()!);
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Firestore fetch version_control error: $e');
    }

    return null;
  }

  /// Checks the current app version against config.
  /// If force update is required, displays a non-dismissible dialog.
  /// If optional update is available, displays a dismissible dialog.
  Future<void> checkAppVersion(
    BuildContext context, {
    bool isManualCheck = false,
  }) async {
    if (_isDialogShowing) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final config = await fetchVersionConfig();
      if (config == null) {
        if (isManualCheck && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Không thể kết nối máy chủ để kiểm tra phiên bản',
                style: GoogleFonts.beVietnamPro(),
              ),
              backgroundColor: TramColors.danger,
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;

      // 1. Force update check: currentVersion < minimumRequiredVersion
      if (VersionUtils.isBelow(currentVersion, config.minimumRequiredVersion)) {
        _showUpdateDialog(
          context: context,
          isForce: true,
          config: config,
          currentVersion: currentVersion,
        );
        return;
      }

      // 2. Optional update check: currentVersion < latestVersion
      if (VersionUtils.isBelow(currentVersion, config.latestVersion)) {
        _showUpdateDialog(
          context: context,
          isForce: false,
          config: config,
          currentVersion: currentVersion,
        );
        return;
      }

      // 3. App is up to date
      if (isManualCheck && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bạn đang sử dụng phiên bản POS Trạm BLAO mới nhất ($currentVersion)',
              style: GoogleFonts.beVietnamPro(),
            ),
            backgroundColor: TramColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateService] checkAppVersion error: $e');
    }
  }

  void _showUpdateDialog({
    required BuildContext context,
    required bool isForce,
    required AppVersionControlModel config,
    required String currentVersion,
  }) {
    _isDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (ctx) {
        return PopScope(
          canPop: !isForce,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: TramColors.cardSurface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isForce
                          ? TramColors.dangerSurface
                          : TramColors.brandPrimary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        isForce ? Icons.warning_amber_rounded : Icons.system_update_rounded,
                        size: 32,
                        color: isForce ? TramColors.danger : TramColors.brandDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    isForce ? 'Yêu Cầu Cập Nhật Bắt Buộc' : 'Đã Có Bản Cập Nhật Mới',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isForce ? TramColors.danger : TramColors.brandDark,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Version tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: TramColors.brandPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'v$currentVersion  ➔  v${config.latestVersion}',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TramColors.brandDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Message
                  Text(
                    config.updateMessage,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 14,
                      height: 1.5,
                      color: TramColors.brandDark.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      if (!isForce) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade700,
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Để sau',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final url = config.targetStoreUrl;
                            final uri = Uri.parse(url);
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            } catch (e) {
                              debugPrint('Failed to launch store url: $e');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isForce ? TramColors.danger : TramColors.brandPrimary,
                            foregroundColor: isForce ? Colors.white : TramColors.brandDark,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            isForce ? 'Cập nhật ngay' : 'Cập nhật',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _isDialogShowing = false;
    });
  }
}
