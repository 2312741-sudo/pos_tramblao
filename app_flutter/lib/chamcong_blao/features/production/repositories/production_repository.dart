import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/production_model.dart';
import '../../../cc_firebase.dart';

const List<ProductionTask> kDefaultProductionTasks = [
  ProductionTask(
    id: 'task_san_xuat',
    name: 'Sản lượng sản xuất trong ca',
    unit: ProductionUnitType.qty,
    unitLabel: 'sản phẩm',
    active: true,
    order: 1,
  ),
  ProductionTask(
    id: 'task_ve_sinh',
    name: 'Vệ sinh khu vực sản xuất & dụng cụ',
    unit: ProductionUnitType.qty,
    unitLabel: 'khu vực',
    active: true,
    order: 2,
  ),
  ProductionTask(
    id: 'task_ban_giao',
    name: 'Bàn giao nguyên vật liệu & công cụ',
    unit: ProductionUnitType.qty,
    unitLabel: 'lần',
    active: true,
    order: 3,
  ),
];

class ProductionRepository {
  final FirebaseFirestore _firestore;

  ProductionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? CcFirebase.firestore;

  CollectionReference<Map<String, dynamic>> _tasksRef(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('production_tasks');

  CollectionReference<Map<String, dynamic>> _reportsRef(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('production_reports');

  // Lấy danh sách task active để hiển thị cho nhân viên (Stream)
  Stream<List<ProductionTask>> watchActiveTasks(String storeId) {
    return _tasksRef(storeId)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((doc) => ProductionTask.fromJson(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list.isEmpty ? kDefaultProductionTasks : list;
    });
  }

  // Lấy danh sách task active trực tiếp (Future) với fallback mặc định
  Future<List<ProductionTask>> getActiveTasks(String storeId) async {
    try {
      final snap = await _tasksRef(storeId)
          .where('active', isEqualTo: true)
          .get();
      if (snap.docs.isEmpty) {
        return kDefaultProductionTasks;
      }
      final list = snap.docs
          .map((doc) => ProductionTask.fromJson(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list.isEmpty ? kDefaultProductionTasks : list;
    } catch (_) {
      return kDefaultProductionTasks;
    }
  }

  // Kiểm tra nhân viên đã nộp báo cáo sản xuất trong ngày hôm nay chưa
  Future<bool> hasReportToday(String storeId, String userId, String date) async {
    try {
      final snap = await _reportsRef(storeId)
          .where('userId', isEqualTo: userId)
          .where('date', isEqualTo: date)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Lấy toàn bộ danh sách task (kể cả inactive) để quản lý & sắp xếp (Stream)
  Stream<List<ProductionTask>> watchAllTasks(String storeId) {
    return _tasksRef(storeId).snapshots().map((snap) {
      final list = snap.docs
          .map((doc) => ProductionTask.fromJson(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  // Sắp xếp lại thứ tự checklist tasks
  Future<void> reorderTasks(String storeId, List<ProductionTask> tasks) async {
    try {
      final batch = _firestore.batch();
      for (int i = 0; i < tasks.length; i++) {
        final ref = _tasksRef(storeId).doc(tasks[i].id);
        batch.update(ref, {'order': i + 1});
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Lỗi khi sắp xếp lại checklist: $e');
    }
  }

  // Thêm mới task
  Future<void> addTask(
    String storeId, {
    required String name,
    required ProductionUnitType unit,
    required String unitLabel,
    required int order,
  }) async {
    try {
      await _tasksRef(storeId).add({
        'name': name.trim(),
        'unit': unit.value,
        'unitLabel': unitLabel.trim(),
        'active': true,
        'order': order,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Thêm công việc thất bại: $e');
    }
  }

  // Cập nhật task
  Future<void> updateTask(
      String storeId, String taskId, Map<String, dynamic> data) async {
    try {
      await _tasksRef(storeId).doc(taskId).update(data);
    } catch (e) {
      throw Exception('Cập nhật công việc thất bại: $e');
    }
  }

  // Xóa task
  Future<void> deleteTask(String storeId, String taskId) async {
    try {
      await _tasksRef(storeId).doc(taskId).delete();
    } catch (e) {
      throw Exception('Xóa công việc thất bại: $e');
    }
  }

  // Submit báo cáo
  Future<void> submitReport(String storeId, ProductionReport report) async {
    try {
      await _reportsRef(storeId).add(report.toJson());
    } catch (e) {
      throw Exception('Nộp báo cáo thất bại: $e');
    }
  }
}
