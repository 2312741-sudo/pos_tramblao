import 'dart:convert';

import '../../data/models/order_item_model.dart';
import '../../data/models/table_model.dart';

/// Máy khác vừa đổi đơn của bàn đang mở trên màn giỏ món → máy này nên làm gì.
enum RemoteTableChange {
  /// Không có gì mới (dữ liệu trùng với máy này, hoặc chỉ là bản ghi của chính máy này dội về).
  none,

  /// Máy này không có thay đổi chưa lưu → lấy đơn mới nhất ngay.
  applySilently,

  /// Máy này cũng đang có thay đổi chưa lưu → hỏi nhân viên trước khi tải lại.
  conflict,

  /// Đơn đã được thanh toán / hủy / chuyển sang hóa đơn khác trên máy khác.
  closedElsewhere,
}

/// Đồng bộ đơn của bàn đang mở giữa nhiều máy.
///
/// Trước đây màn giỏ món chỉ chép đơn lúc mở rồi mỗi lần bấm lại GHI ĐÈ cả bàn bằng bản đó:
/// máy A thêm món, máy B đang mở bàn vẫn thấy đơn cũ, B bấm gì đó là món của A biến mất.
class RemoteTableSync {
  /// Chuỗi so sánh của danh sách món (qua toMap để bỏ khác biệt định dạng JSON).
  static String signature(List<OrderItemModel> items) => jsonEncode(items.map((e) => e.toMap()).toList());

  /// [baseSignature]: đơn đã lưu gần nhất mà màn này biết; [localSignature]: giỏ món đang hiển thị;
  /// [ownTableSignature]: đơn trên đối tượng bàn mà chính máy này vừa ghi (vd. vừa thanh toán → rỗng);
  /// [localBillId]: mã hóa đơn của bàn khi mở màn.
  static RemoteTableChange classify({
    required String baseSignature,
    required String localSignature,
    String? ownTableSignature,
    required String? localBillId,
    required TableModel remote,
  }) {
    final remoteSignature = signature(remote.currentItems);
    if (remoteSignature == baseSignature || remoteSignature == localSignature || remoteSignature == ownTableSignature) {
      return RemoteTableChange.none;
    }
    final remoteBill = remote.currentBillId;
    final hadBill = localBillId != null && localBillId.isNotEmpty;
    // Bàn đã sang một lượt đơn khác (hóa đơn khác): để luồng tách bàn sẵn có xử lý, không trộn đơn.
    if (hadBill && remoteBill != null && remoteBill.isNotEmpty && remoteBill != localBillId) {
      return RemoteTableChange.none;
    }
    // Bàn trống trở lại: chỉ coi là "đã đóng ở máy khác" khi máy này đã có đơn được lưu.
    if (!remote.inUse || remote.currentItems.isEmpty) {
      return baseSignature == signature(const []) ? RemoteTableChange.none : RemoteTableChange.closedElsewhere;
    }
    if (localSignature == baseSignature) return RemoteTableChange.applySilently;
    return RemoteTableChange.conflict;
  }
}
