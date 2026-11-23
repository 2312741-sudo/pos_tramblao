// lib/chamcong_blao/chamcong_blao_screen.dart
//
// Cổng vào mô-đun Chấm Công Trạm BLAO bên trong app POS (gộp từ app chamcong_tramblao).
// Dùng CHÍNH Firebase Auth & Firestore mặc định của POS (`postramblao`):
// trước khi mở mô-đun, gọi `chamCongEnsureMember({ storeCode })` để đảm bảo hồ sơ cửa hàng
// và thành viên tồn tại trên Firestore (hỗ trợ mở ngoại tuyến nếu dữ liệu đã có trong cache).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/auth_service.dart';
import 'app/app.dart';
import 'cc_firebase.dart';
import 'core/services/notification_service.dart';

class ChamCongModuleException implements Exception {
  ChamCongModuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

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
  late Future<void> _ready = _ensureMember();
  // Container riêng cho mô-đun (không dùng chung với POS) → mở lại là trạng thái mới, đóng là dọn sạch
  final ProviderContainer _container = ProviderContainer();

  @override
  void initState() {
    super.initState();
    CcFirebase.onExitModule = () {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    };
  }

  Future<void> _ensureMember() async {
    final pos = AuthService();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final storeCode = pos.currentStoreCode.trim().toUpperCase();
    if (!pos.isLoggedIn || uid == null || storeCode.isEmpty) {
      throw ChamCongModuleException('Vui lòng đăng nhập POS trước khi sử dụng Chấm Công.');
    }

    await CcFirebase.ensureInitialized();

    try {
      await CcFirebase.functions()
          .httpsCallable('chamCongEnsureMember')
          .call<dynamic>(<String, dynamic>{'storeCode': storeCode})
          .timeout(const Duration(seconds: 15));
    } on FirebaseFunctionsException catch (e) {
      final isNetworkError = e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          (e.code == 'internal' && (e.message ?? '').toLowerCase().contains('network'));
      if (isNetworkError && await _hasOfflineCache(storeCode, uid)) {
        // Mất mạng nhưng thành viên đã đồng bộ trước đó → cho phép vào mô-đun ngoại tuyến
      } else {
        throw ChamCongModuleException(
          e.message ?? 'Không khởi tạo được hồ sơ Chấm Công. Vui lòng thử lại.',
        );
      }
    } on TimeoutException {
      if (!await _hasOfflineCache(storeCode, uid)) {
        throw ChamCongModuleException('Kết nối máy chủ quá chậm. Vui lòng kiểm tra mạng và thử lại.');
      }
    }

    unawaited(() async {
      try {
        await NotificationService().initialize();
        await NotificationService().saveTokenForUser(uid);
      } catch (_) {}
    }());
  }

  Future<bool> _hasOfflineCache(String storeCode, String uid) async {
    try {
      final db = CcFirebase.firestore;
      final memberSnap = await db
          .collection('stores')
          .doc(storeCode)
          .collection('members')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      if (!memberSnap.exists) return false;
      final status = memberSnap.data()?['status'] as String?;
      return status == null || status == 'active';
    } catch (_) {
      return false;
    }
  }

  void _retry() => setState(() => _ready = _ensureMember());

  @override
  void dispose() {
    CcFirebase.onExitModule = null;
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF143A2F);
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<void>(
        future: _ready,
        builder: (context, snap) {
          if (snap.hasError) {
            return _LoadingOrErrorWrapper(
              brand: brand,
              child: _InitError(
                error: snap.error!,
                onRetry: _retry,
                onExit: () => Navigator.of(context).maybePop(),
              ),
            );
          }
          if (snap.connectionState != ConnectionState.done) {
            return const _LoadingOrErrorWrapper(
              brand: brand,
              child: ColoredBox(
                color: Colors.white,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          return UncontrolledProviderScope(container: _container, child: const ChamCongTramApp());
        },
      ),
    );
  }
}

class _LoadingOrErrorWrapper extends StatelessWidget {
  const _LoadingOrErrorWrapper({required this.brand, required this.child});
  final Color brand;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: brand,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 44,
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
        Expanded(child: child),
      ],
    );
  }
}

class _InitError extends StatelessWidget {
  const _InitError({required this.error, required this.onRetry, required this.onExit});
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onExit;

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
                error is ChamCongModuleException
                    ? '$error'
                    : 'Không mở được Chấm Công.\nKiểm tra kết nối mạng rồi thử lại.\n\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(onPressed: onExit, child: const Text('Về POS')),
                  FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
