import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/app_colors.dart';
import '../utils/version_utils.dart';
import '../widgets/app_update_dialog.dart';
import '../../cc_firebase.dart';

export '../widgets/app_update_dialog.dart';

class AppVersionControlModel {
  final String latestVersion;
  final String minimumRequiredVersion;
  final String updateMessage;
  final String? updateUrlIos;
  final String? updateUrlAndroid;
  final String? updateUrl;
  final String? apkUrl;

  const AppVersionControlModel({
    required this.latestVersion,
    required this.minimumRequiredVersion,
    required this.updateMessage,
    this.updateUrlIos,
    this.updateUrlAndroid,
    this.updateUrl,
    this.apkUrl,
  });

  factory AppVersionControlModel.fromMap(Map<String, dynamic> data) {
    final rawApkUrl = data['apkUrl'] as String?;
    final rawAndroidUrl = data['updateUrlAndroid'] as String?;

    String? resolvedApkUrl;
    if (rawApkUrl != null && rawApkUrl.trim().isNotEmpty) {
      resolvedApkUrl = rawApkUrl.trim();
    } else if (rawAndroidUrl != null &&
        rawAndroidUrl.trim().toLowerCase().endsWith('.apk')) {
      resolvedApkUrl = rawAndroidUrl.trim();
    }

    return AppVersionControlModel(
      latestVersion: data['latestVersion'] as String? ?? '1.1.0',
      minimumRequiredVersion:
          data['minimumRequiredVersion'] as String? ?? '1.0.2',
      updateMessage: data['updateMessage'] as String? ??
          'Đã có phiên bản mới với nhiều cải tiến vận hành Trạm BLAO. Vui lòng cập nhật ứng dụng.',
      updateUrlIos: data['updateUrlIos'] as String? ??
          'https://chamcong-tramblao.vercel.app',
      updateUrlAndroid: rawAndroidUrl ??
          'https://play.google.com/store/apps/details?id=com.tramblao.chamcong',
      updateUrl:
          data['updateUrl'] as String? ?? 'https://chamcong-tramblao.vercel.app',
      apkUrl: resolvedApkUrl,
    );
  }

  factory AppVersionControlModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppVersionControlModel.fromMap(data);
  }

  String get targetStoreUrl {
    if (kIsWeb) {
      return updateUrl ?? 'https://chamcong-tramblao.vercel.app';
    }
    if (Platform.isIOS) {
      return updateUrlIos ?? updateUrl ?? 'https://chamcong-tramblao.vercel.app';
    }
    if (Platform.isAndroid) {
      return updateUrlAndroid ??
          updateUrl ??
          'https://play.google.com/store/apps/details?id=com.tramblao.chamcong';
    }
    return updateUrl ?? 'https://chamcong-tramblao.vercel.app';
  }
}

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  bool _isDialogShowing = false;
  http.Client? _httpClient;

  @visibleForTesting
  void setHttpClientForTest(http.Client client) {
    _httpClient = client;
  }

  /// Fetches version control configuration from Firestore collection `app_config`, doc `version_control`
  /// Chạy trong app POS: TẮT kiểm tra cập nhật riêng của app chấm công. Cấu hình phiên bản (app_config/version_control)
  /// là của app chấm công cũ, so với số phiên bản POS sẽ báo sai / chặn màn khởi động. POS có trình cập nhật riêng.
  static const bool embeddedInPos = true;

  Future<AppVersionControlModel?> fetchVersionConfig() async {
    if (embeddedInPos) return null;
    try {
      final doc = await CcFirebase.firestore
          .collection('app_config')
          .doc('version_control')
          .get()
          .timeout(const Duration(seconds: 4));

      if (!doc.exists) return null;
      return AppVersionControlModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('Failed to fetch version_control from Firestore: $e');
      return null;
    }
  }

  /// Checks the current app version against Firestore config.
  /// If force update is required, displays a blocking dialog.
  /// If optional update is available, displays a dismissible dialog.
  Future<void> checkAppVersion(
    BuildContext context, {
    bool isManualCheck = false,
  }) async {
    if (embeddedInPos) return;
    if (_isDialogShowing) return;
    if (!isManualCheck && !kIsWeb && Platform.isIOS) return;

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
              'Bạn đang sử dụng phiên bản mới nhất ($currentVersion)',
              style: GoogleFonts.beVietnamPro(),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error in checkAppVersion: $e');
    }
  }

  void _showUpdateDialog({
    required BuildContext context,
    required bool isForce,
    required AppVersionControlModel config,
    required String currentVersion,
  }) {
    _isDialogShowing = true;

    AppUpdateDialog.show(
      context,
      config: config,
      isForce: isForce,
      currentVersion: currentVersion,
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  /// Tải file APK từ URL với báo cáo tiến trình %
  Future<File> downloadApkFile(
    String url, {
    required void Function(double progress, int received, int total) onProgress,
    void Function(String status)? onStatusChange,
  }) async {
    if (!kIsWeb && !Platform.isAndroid && _httpClient == null) {
      throw UnsupportedError(
          'Tự động cập nhật APK chỉ hỗ trợ trên thiết bị Android');
    }

    final uri = Uri.parse(url);
    final client = _httpClient ?? http.Client();
    final request = http.Request('GET', uri);
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception(
          'Không thể tải file APK (Mã lỗi HTTP ${response.statusCode})');
    }

    final totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;

    // Lấy thư mục lưu file tạm trên Android
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/blao_chamcong_update.apk';
    final file = File(filePath);

    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    onStatusChange?.call('Đang tải xuống...');
    final sink = file.openWrite();

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress =
            totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        onProgress(progress, receivedBytes, totalBytes);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    onStatusChange?.call('Tải xong, chuẩn bị cài đặt...');
    return file;
  }

  /// Kích hoạt trình cài đặt APK của Android PackageInstaller
  Future<OpenResult> installApk(String filePath) async {
    if (!kIsWeb && !Platform.isAndroid) {
      throw UnsupportedError('Chức năng cài đặt APK chỉ hỗ trợ trên Android');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File APK không tồn tại hoặc đã bị xóa');
    }

    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
    return result;
  }
}
