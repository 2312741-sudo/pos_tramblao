// lib/chamcong_blao/pos_sso.dart
//
// Mô-đun Chấm Công BLAO dùng CHÍNH tài khoản POS: đổi phiên đăng nhập POS lấy phiên đăng nhập dự án
// chamcongtramblao qua Cloud Function chamCongBlaoSignIn (functions/src/chamCongBlao.ts) rồi đăng nhập
// Firebase app phụ bằng custom token. Lần đầu: máy chủ tự nối với tài khoản chấm công cũ CÙNG TÊN
// (giữ lịch sử) hoặc tạo tài khoản chấm công mới.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/services/auth_service.dart';
import 'cc_firebase.dart';

class ChamCongBlaoSsoException implements Exception {
  ChamCongBlaoSsoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ChamCongBlaoSso {
  ChamCongBlaoSso._();

  /// Tài khoản POS ↔ chấm công của lần đổi phiên gần nhất (dùng khi mất mạng mà phiên chấm công còn hạn)
  static String? _lastPosUid;
  static String? _lastCcUid;

  /// Đăng nhập mô-đun chấm công bằng tài khoản POS đang đăng nhập.
  static Future<void> signInWithPos({FirebaseFunctions? functions}) async {
    final pos = AuthService();
    final posUid = FirebaseAuth.instance.currentUser?.uid;
    if (!pos.isLoggedIn || posUid == null) {
      throw ChamCongBlaoSsoException('Vui lòng đăng nhập POS trước khi chấm công.');
    }
    await CcFirebase.ensureInitialized();
    final ccAuth = CcFirebase.auth;

    Map<String, dynamic> data;
    try {
      final res = await (functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1'))
          .httpsCallable('chamCongBlaoSignIn')
          .call(<String, dynamic>{'storeCode': pos.currentStoreCode});
      data = Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      // Mất mạng nhưng phiên chấm công của đúng tài khoản POS này vẫn còn → cho dùng tiếp (dữ liệu tự đồng bộ sau)
      final offline = e.code == 'unavailable' || e.code == 'deadline-exceeded' || (e.code == 'internal' && (e.message ?? '').contains('network'));
      if (offline && _lastPosUid == posUid && ccAuth.currentUser?.uid == _lastCcUid) return;
      throw ChamCongBlaoSsoException(e.message ?? 'Không đăng nhập được Chấm Công. Vui lòng thử lại.');
    }

    final token = data['customToken'] as String?;
    final ccUid = data['ccUid'] as String?;
    if (token == null || ccUid == null) {
      throw ChamCongBlaoSsoException('Máy chủ trả về dữ liệu đăng nhập Chấm Công không hợp lệ.');
    }
    // Máy dùng chung: phiên chấm công của người khác → đăng xuất rồi vào đúng người
    if (ccAuth.currentUser != null && ccAuth.currentUser!.uid != ccUid) {
      await ccAuth.signOut();
    }
    if (ccAuth.currentUser?.uid != ccUid) {
      await ccAuth.signInWithCustomToken(token);
    }
    _lastPosUid = posUid;
    _lastCcUid = ccUid;
  }

  /// Đăng xuất chấm công (gọi khi đăng xuất POS). Không lỗi nếu mô-đun chưa từng mở.
  static Future<void> signOut() async {
    _lastPosUid = null;
    _lastCcUid = null;
    try {
      if (Firebase.apps.any((a) => a.name == CcFirebase.appName)) {
        await CcFirebase.auth.signOut();
      }
    } catch (e) {
      debugPrint('[ChamCongBlaoSso] signOut: $e');
    }
  }
}
