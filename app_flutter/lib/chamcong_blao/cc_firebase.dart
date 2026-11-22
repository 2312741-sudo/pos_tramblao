// lib/chamcong_blao/cc_firebase.dart
//
// Mô-đun Chấm Công Trạm BLAO chạy TRONG app POS nhưng giữ nguyên dữ liệu ở dự án Firebase riêng
// `chamcongtramblao` (Firestore, Auth, Storage, Functions). App POS dùng Firebase mặc định
// (`postramblao`), nên mô-đun này dùng một Firebase app PHỤ tên [CcFirebase.appName].
//
// Mọi chỗ trong mô-đun phải lấy Firebase qua lớp này (không dùng `FirebaseAuth.instance`,
// `FirebaseFirestore.instance`... vì đó là dự án POS).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'cc_firebase_options.dart';

class CcFirebase {
  CcFirebase._();

  /// Tên Firebase app phụ của mô-đun chấm công
  static const String appName = 'chamcong_blao';

  /// Vùng Cloud Functions của dự án chamcongtramblao
  static const String functionsRegion = 'asia-east2';

  static FirebaseApp? _app;
  static Future<FirebaseApp>? _initializing;

  /// Khởi tạo (một lần) Firebase app phụ. Gọi trước khi mở mô-đun chấm công.
  static Future<FirebaseApp> ensureInitialized() {
    final existing = _app;
    if (existing != null) return Future.value(existing);
    return _initializing ??= () async {
      try {
        _app = Firebase.app(appName);
      } catch (_) {
        _app = await Firebase.initializeApp(name: appName, options: CcFirebaseOptions.currentPlatform);
      }
      return _app!;
    }();
  }

  static FirebaseApp get app {
    final a = _app;
    if (a != null) return a;
    // Đã khởi tạo ở nơi khác (vd. hot restart) → lấy theo tên
    return _app = Firebase.app(appName);
  }

  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: app);
  static FirebaseFirestore get firestore => FirebaseFirestore.instanceFor(app: app);
  static FirebaseStorage get storage => FirebaseStorage.instanceFor(app: app);
  static FirebaseFunctions functions({String region = functionsRegion}) =>
      FirebaseFunctions.instanceFor(app: app, region: region);
}
