import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand Colors - Trạm BLAO Ecosystem
  static const Color primary = Color(0xFF7FE3C7); // Xanh mint Trạm BLAO
  static const Color primaryDark = Color(0xFF143A2F);
  static const Color logoRed = Color(0xFFC91506); // Đỏ thương hiệu Trạm trên logo
  static const Color mintAccent = Color(0xFF7FE3C7); // Tone màu tươi mát Trạm BLAO
  static const Color success = Color(0xFF146A65); // Accessible teal for white text
  static const Color tealAccent = Color(0xFF1E8E87);
  static const Color accent = Color(0xFF7FE3C7);
  static const Color accentInk = Color(0xFF143A2F);
  static const Color info = Color(0xFF2D2A4A);
  static const Color neutral = Color(0xFF1C1A2D);
  static const Color surface = Color(0xFFF4E9D5); // Nền kem chuẩn logo
  static const Color background = surface;
  static const Color paperInk = Color(0xFFE8DCB8);
  static const Color cardOutline = info;
  static const Color white = Colors.white;

  // Semantic Colors
  static const Color checkIn = success;
  static const Color checkOut = Color(0xFF888780);
  static const Color pending = accent;
  static const Color danger = logoRed;
  static const Color warning = Color(0xFFF59E0B);

  // Text Colors
  static const Color textPrimary = neutral;
  static const Color textSecondary = Color(0xFF5D5B63);
  static const Color textDisabled = Color(0xFFAAAAAA);
  static const Color textOnPrimary = Color(0xFF143A2F); // Tương phản cao trên nền mint #7FE3C7

  // Border & Divider
  static const Color border = Color(0xFFD8CFBD);
  static const Color divider = paperInk;

  // Card & Shadow
  static const Color cardSurface = Color(0xFFFFFEF9);
  static const Color shadow = Color(0x262D2A4A);

  // Dashboard role accents. Keep these separate from business-status colors.
  static const Color ownerAccent = Color(0xFF171717);
  static const Color ownerAccentDark = Color(0xFF050505);
  static const Color ownerTint = Color(0xFFEDEBE6);
  static const Color managerAccent = Color(0xFF126CC3);
  static const Color managerAccentDark = Color(0xFF095AA8);
  static const Color managerTint = Color(0xFFE8F3FE);

  // Status Colors
  static const Color statusActive = success;
  static const Color statusInactive = Color(0xFF6B6870);
  static const Color statusPending = accentInk;
  static const Color statusDanger = danger;

  // Role Badge Colors
  static const Color ownerBadge = ownerAccent;
  static const Color managerBadge = managerAccent;
  static const Color employeeBadge = Color(0xFF6B6870);

  // Shift Colors
  static const Color shiftMorning = accent;
  static const Color shiftAfternoon = Color(0xFFC77639);
  static const Color shiftEvening = info;
  static const Color shiftOff = Color(0xFFCCCCCC);

  // Gradient Definitions
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B4D3E), Color(0xFF13382D)],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2D2A4A), Color(0xFF1C1A2D)],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E8E87), Color(0xFF146A65)],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1B4D3E), Color(0xFFF4E9D5)],
    stops: [0.0, 0.45],
  );

  static const RadialGradient checkInButtonGradient = RadialGradient(
    colors: [Color(0xFF1E8E87), Color(0xFF146A65)],
    radius: 0.85,
  );

  static const RadialGradient checkOutButtonGradient = RadialGradient(
    colors: [Color(0xFF1B4D3E), Color(0xFF13382D)],
    radius: 0.85,
  );
}
