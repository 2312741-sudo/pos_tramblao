import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class ShareUtils {
  ShareUtils._();

  /// Calculates a valid, non-zero sharePositionOrigin Rect for iOS / iPad popovers
  static Rect getSharePositionOrigin(BuildContext? context) {
    if (context != null && context.mounted) {
      try {
        final renderObject = context.findRenderObject();
        if (renderObject is RenderBox &&
            renderObject.hasSize &&
            renderObject.size != Size.zero) {
          final size = renderObject.size;
          final position = renderObject.localToGlobal(Offset.zero);
          if (size.width > 0 && size.height > 0) {
            return position & size;
          }
        }
      } catch (_) {}
    }

    // Fallback: Use window / MediaQuery dimensions to anchor safely
    if (context != null && context.mounted) {
      try {
        final mediaQuery = MediaQuery.of(context);
        final size = mediaQuery.size;
        if (size.width > 0 && size.height > 0) {
          return Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2);
        }
      } catch (_) {}
    }

    // Default safe non-zero Rect for iPad/iOS coordinate space
    return const Rect.fromLTWH(0, 100, 300, 300);
  }

  /// Share one or more files safely with iOS sharePositionOrigin and user-friendly error handling
  static Future<bool> shareFiles(
    List<String> filePaths, {
    BuildContext? context,
    String? text,
    String? subject,
  }) async {
    try {
      final xFiles = <XFile>[];
      for (final path in filePaths) {
        final file = File(path);
        if (await file.exists()) {
          xFiles.add(XFile(path));
        }
      }

      if (xFiles.isEmpty) {
        throw Exception('File cần chia sẻ không tồn tại.');
      }

      final origin = getSharePositionOrigin(context);
      final result = await Share.shareXFiles(
        xFiles,
        text: text,
        subject: subject,
        sharePositionOrigin: origin,
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (e) {
      debugPrint('ShareUtils.shareFiles error: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở hộp thoại chia sẻ. Vui lòng thử lại.'),
            backgroundColor: Color(0xFFC8102E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// Share text / link / invite message safely
  static Future<bool> shareText(
    String text, {
    BuildContext? context,
    String? subject,
  }) async {
    try {
      final origin = getSharePositionOrigin(context);
      final result = await Share.share(
        text,
        subject: subject,
        sharePositionOrigin: origin,
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (e) {
      debugPrint('ShareUtils.shareText error: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở hộp thoại chia sẻ. Vui lòng thử lại.'),
            backgroundColor: Color(0xFFC8102E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }
}
