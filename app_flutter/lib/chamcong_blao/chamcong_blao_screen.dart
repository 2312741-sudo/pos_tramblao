// lib/chamcong_blao/chamcong_blao_screen.dart
//
// Cổng vào mô-đun Chấm Công Trạm BLAO bên trong app POS (gộp từ app chamcong_tramblao).
// Mô-đun chạy trong một "app con" riêng (MaterialApp.router + Riverpod container riêng) để giữ nguyên
// giao diện, điều hướng, phiên đăng nhập và dữ liệu Firebase (dự án chamcongtramblao) như app cũ.
// Không cần đăng nhập POS: nhân viên mở được từ màn hình đăng nhập để chấm công vào ca.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'cc_firebase.dart';

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
  late final Future<void> _ready = CcFirebase.ensureInitialized();
  // Container riêng cho mô-đun (không dùng chung với POS) → mở lại là trạng thái mới, đóng là dọn sạch
  final ProviderContainer _container = ProviderContainer();

  @override
  void dispose() {
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
                    return _InitError(error: snap.error!);
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
  const _InitError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Không khởi động được Chấm Công.\nKiểm tra kết nối mạng rồi mở lại.\n\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
