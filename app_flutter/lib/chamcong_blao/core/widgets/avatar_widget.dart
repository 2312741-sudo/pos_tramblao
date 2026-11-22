import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../constants/app_colors.dart';

/// Helper to get an ImageProvider for any avatar representation (Network URL, Data URI, or local bytes)
ImageProvider? getAvatarImageProvider(String? avatarUrl, [Uint8List? localBytes]) {
  if (localBytes != null && localBytes.isNotEmpty) {
    return MemoryImage(localBytes);
  }
  if (avatarUrl == null || avatarUrl.trim().isEmpty) {
    return null;
  }
  final trimmed = avatarUrl.trim();
  if (trimmed.startsWith('data:image')) {
    try {
      final base64Part = trimmed.split(',').last;
      return MemoryImage(base64Decode(base64Part));
    } catch (_) {
      return null;
    }
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return CachedNetworkImageProvider(trimmed);
  }
  return null;
}

class AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double radius;
  final Color? backgroundColor;

  const AvatarWidget({
    super.key,
    this.avatarUrl,
    required this.name,
    this.radius = 24,
    this.backgroundColor,
  });

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '?';
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';
    return '$first$last'.toUpperCase();
  }

  Color _getColorFromName() {
    if (name.isEmpty) return AppColors.primary;
    final colors = [
      AppColors.primary,
      AppColors.info,
      AppColors.success,
      const Color(0xFF7B2FBE),
      const Color(0xFFE07B39),
      const Color(0xFF2196F3),
      const Color(0xFF009688),
    ];
    final index = name.codeUnitAt(0) % colors.length;
    return colors[index];
  }

  Widget _buildFallback(Color bgColor) {
    final textColor = bgColor.computeLuminance() > 0.45 ? const Color(0xFF143A2F) : AppColors.white;
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      child: Text(
        _initials,
        style: TextStyle(
          color: textColor,
          fontSize: radius * 0.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    final bgColor = backgroundColor ?? _getColorFromName();
    final diameter = radius * 2;

    if (!hasAvatar) {
      return _buildFallback(bgColor);
    }

    final trimmed = avatarUrl!.trim();

    // Check if base64 Data URI
    if (trimmed.startsWith('data:image')) {
      try {
        final base64Part = trimmed.split(',').last;
        final bytes = base64Decode(base64Part);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallback(bgColor),
          ),
        );
      } catch (_) {
        return _buildFallback(bgColor);
      }
    }

    // Network image
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: trimmed,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          placeholder: (context, url) => Shimmer.fromColors(
            baseColor: const Color(0xFFECE8E2),
            highlightColor: const Color(0xFFF8F4EE),
            child: Container(
              width: diameter,
              height: diameter,
              color: AppColors.white,
            ),
          ),
          errorWidget: (context, url, error) => _buildFallback(bgColor),
        ),
      );
    }

    return _buildFallback(bgColor);
  }
}
