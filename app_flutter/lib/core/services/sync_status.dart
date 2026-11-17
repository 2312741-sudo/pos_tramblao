import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

/// Trạng thái kết nối tới Firebase và số thao tác ghi chưa được máy chủ xác nhận.
///
/// App bật lưu tạm offline: mất mạng thì món vừa thêm vẫn hiện trên máy này nhưng
/// các máy khác CHƯA thấy cho tới khi có mạng lại. Trước đây nhân viên không hề được báo.
class SyncStatus {
  SyncStatus._();
  static final SyncStatus instance = SyncStatus._();

  /// Đang kết nối máy chủ (mặc định true để không nháy cảnh báo lúc mở app)
  final ValueNotifier<bool> connected = ValueNotifier<bool>(true);

  /// Số thao tác ghi đang chờ máy chủ xác nhận
  final ValueNotifier<int> pending = ValueNotifier<int>(0);

  StreamSubscription<DatabaseEvent>? _sub;

  /// Nghe `.info/connected` của Firebase Realtime Database
  void attach(DatabaseReference infoConnected) {
    _sub?.cancel();
    _sub = infoConnected.onValue.listen(
      (e) => connected.value = e.snapshot.value == true,
      onError: (_) {},
    );
  }

  /// Theo dõi một thao tác ghi tới khi máy chủ xác nhận (hoặc báo lỗi)
  void track(Future<void> write) {
    pending.value = pending.value + 1;
    unawaited(write.then((_) {}, onError: (_) {}).whenComplete(() {
      pending.value = pending.value > 0 ? pending.value - 1 : 0;
    }));
  }
}

/// Dải cảnh báo trên cùng màn hình khi mất kết nối / còn dữ liệu chưa đồng bộ.
/// Có độ trễ để không nháy khi mạng chỉ chậm trong chốc lát.
class SyncStatusFrame extends StatefulWidget {
  const SyncStatusFrame({super.key, required this.child, this.status});

  final Widget child;
  final SyncStatus? status;

  @override
  State<SyncStatusFrame> createState() => _SyncStatusFrameState();
}

class _SyncStatusFrameState extends State<SyncStatusFrame> {
  static const _offlineDelay = Duration(seconds: 3);
  static const _pendingDelay = Duration(seconds: 4);

  late final SyncStatus _status = widget.status ?? SyncStatus.instance;
  Timer? _offlineTimer;
  Timer? _pendingTimer;
  bool _showOffline = false;
  bool _showPending = false;

  @override
  void initState() {
    super.initState();
    _status.connected.addListener(_onConnected);
    _status.pending.addListener(_onPending);
    _onConnected();
    _onPending();
  }

  @override
  void dispose() {
    _status.connected.removeListener(_onConnected);
    _status.pending.removeListener(_onPending);
    _offlineTimer?.cancel();
    _pendingTimer?.cancel();
    super.dispose();
  }

  void _onConnected() {
    if (_status.connected.value) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      if (_showOffline && mounted) setState(() => _showOffline = false);
    } else {
      _offlineTimer ??= Timer(_offlineDelay, () {
        _offlineTimer = null;
        if (mounted && !_status.connected.value) setState(() => _showOffline = true);
      });
    }
  }

  void _onPending() {
    if (_status.pending.value <= 0) {
      _pendingTimer?.cancel();
      _pendingTimer = null;
      if (_showPending && mounted) setState(() => _showPending = false);
    } else {
      _pendingTimer ??= Timer(_pendingDelay, () {
        _pendingTimer = null;
        if (mounted && _status.pending.value > 0) setState(() => _showPending = true);
      });
      if (_showPending && mounted) setState(() {}); // cập nhật số đếm
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? message;
    final Color color;
    if (_showOffline) {
      message = 'Mất kết nối máy chủ — món vừa thao tác chỉ lưu trên máy này, máy khác CHƯA thấy. Kiểm tra Wi-Fi / 4G.';
      color = const Color(0xFFB3261E);
    } else if (_showPending) {
      message = 'Đang đồng bộ ${_status.pending.value} thay đổi lên máy chủ… (mạng chậm)';
      color = const Color(0xFFB45309);
    } else {
      message = null;
      color = Colors.transparent;
    }
    // Cấu trúc cây luôn giống nhau (chỉ đổi nội dung dải) để màn hình bên dưới không bị dựng lại.
    return Column(
      children: [
        // Ô đầu luôn tồn tại (rỗng khi không cảnh báo) để màn hình bên dưới giữ nguyên vị trí trong cây.
        if (message == null)
          const SizedBox.shrink()
        else
          Material(
            color: color,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(_showOffline ? Icons.cloud_off : Icons.cloud_sync, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: message != null, child: widget.child),
        ),
      ],
    );
  }
}
