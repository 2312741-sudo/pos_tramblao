// lib/chamcong_blao/chamcong_blao_screen.dart
//
// Cổng vào mô-đun Chấm Công Trạm BLAO bên trong app POS (gộp từ app chamcong_tramblao).
// Mô-đun chạy trong một "app con" riêng (MaterialApp.router + Riverpod container riêng) để giữ nguyên
// giao diện, điều hướng, phiên đăng nhập và dữ liệu Firebase (dự án chamcongtramblao) như app cũ.
// Đăng nhập bằng CHÍNH tài khoản POS (pos_sso.dart): không có màn đăng nhập / đăng ký riêng của chấm công.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'cc_firebase.dart';
import 'pos_sso.dart';

class ChamCongBlaoScreen extends StatefulWidget {
  const ChamCongBlaoScreen({super.key});

  /// Mở mô-đun chấm công (màn hình toàn màn hình, nằm trên điều hướng POS)
  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const ChamCongBlaoScreen(), fullscreenDialog: true),
    );
  }

  @override
  State<ChamCongBlaoScreen> createState() => _ChamCongBlaoScreenState();
}

class _ChamCongBlaoScreenState extends State<ChamCongBlaoScreen> {
  late Future<void> _ready = _signIn();
  // Container riêng cho mô-đun (không dùng chung với POS) → mở lại là trạng thái mới, đóng là dọn sạch
  final ProviderContainer _container = ProviderContainer();
  StreamSubscription<User?>? _authSub;

  Future<void> _signIn() async {
    await ChamCongBlaoSso.signInWithPos();
    // Đăng xuất bên trong mô-đun (nút đăng xuất của chấm công) → đóng mô-đun, không hiện màn đăng nhập riêng
    await _authSub?.cancel();
    _authSub = CcFirebase.auth.authStateChanges().skip(1).listen((u) {
      if (u == null && mounted) Navigator.of(context).maybePop();
    });
  }

  void _retry() => setState(() => _ready = _signIn());

  @override
  void dispose() {
    _authSub?.cancel();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF143A2F);
    return Scaffold(
      backgroundColor: brand,
      body: Column(
        children: [
          Material(
            color: brand,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                      label: const Text('Về POS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                    const Expanded(
                      child: Text(
                        'Chấm Công Trạm BLAO',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 96),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: FutureBuilder<void>(
                future: _ready,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _InitError(error: snap.error!, onRetry: _retry);
                  }
                  if (snap.connectionState != ConnectionState.done) {
                    return const ColoredBox(
                      color: Colors.white,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return UncontrolledProviderScope(container: _container, child: const ChamCongTramApp());
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InitError extends StatelessWidget {
  const _InitError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: Colors.black45),
              const SizedBox(height: 12),
              Text(
                error is ChamCongBlaoSsoException ? '$error' : 'Không mở được Chấm Công.\nKiểm tra kết nối mạng rồi thử lại.\n\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ),
        ),
      ),
    );
  }
}
