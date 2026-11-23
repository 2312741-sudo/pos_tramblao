// lib/chamcong_blao/cc_firebase.dart
//
// Điểm truy cập Firebase duy nhất của mô-đun Chấm Công Trạm BLAO bên trong app POS.
// Chấm công đã được chuyển sang chính dự án Firebase mặc định của POS (`postramblao`),
// vùng Cloud Functions `asia-southeast1`.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';

class CcFirebase {
  CcFirebase._();

  /// Vùng Cloud Functions của dự án postramblao
  static const String functionsRegion = 'asia-southeast1';

  /// Callback do ChamCongBlaoScreen gắn để đóng mô-đun và quay về POS từ bất kỳ màn hình con nào.
  static VoidCallback? onExitModule;

  static void exitModule([BuildContext? fallbackContext]) {
    final cb = onExitModule;
    if (cb != null) {
      cb();
      return;
    }
    if (fallbackContext != null && fallbackContext.mounted) {
      Navigator.of(fallbackContext, rootNavigator: true).maybePop();
    }
  }

  /// Firebase app mặc định của POS đã được khởi tạo ở main.dart.
  static Future<FirebaseApp> ensureInitialized() => Future.value(Firebase.app());

  static FirebaseApp get app => Firebase.app();

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;
  static FirebaseFunctions functions({String region = functionsRegion}) =>
      FirebaseFunctions.instanceFor(region: region);
}
