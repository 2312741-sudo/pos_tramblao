import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/remote_table_sync.dart';
import 'package:tram_flutter/core/services/sync_status.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/table_model.dart';

OrderItemModel item(int id, String name, [int qty = 1]) => OrderItemModel(productId: id, name: name, price: 10000, quantity: qty);

TableModel table(List<OrderItemModel> items, {bool inUse = true, String? billId = 'HD-1'}) => TableModel(
      name: 'Bàn 01',
      zone: 'Khu A',
      inUse: inUse,
      currentBillId: billId,
      currentOrderJson: items.isEmpty ? '' : jsonEncode(items.map((e) => e.toMap()).toList()),
    );

void main() {
  final three = [item(1, 'Trà'), item(2, 'Cà phê'), item(3, 'Bánh')];
  final five = [...three, item(4, 'Sữa'), item(5, 'Flan')];
  String sig(List<OrderItemModel> l) => RemoteTableSync.signature(l);

  group('Đồng bộ đơn bàn giữa nhiều máy', () {
    test('máy khác thêm món, máy này không có thay đổi chưa lưu → cập nhật ngay', () {
      final c = RemoteTableSync.classify(baseSignature: sig(three), localSignature: sig(three), localBillId: 'HD-1', remote: table(five));
      expect(c, RemoteTableChange.applySilently);
    });

    test('máy này cũng đang có thay đổi chưa lưu → hỏi trước (không ghi đè lặng lẽ)', () {
      final local = [...three, item(9, 'Matcha')];
      final c = RemoteTableSync.classify(baseSignature: sig(three), localSignature: sig(local), localBillId: 'HD-1', remote: table(five));
      expect(c, RemoteTableChange.conflict);
    });

    test('bản ghi của chính máy này dội về → không làm gì', () {
      expect(RemoteTableSync.classify(baseSignature: sig(three), localSignature: sig(five), localBillId: 'HD-1', remote: table(five)), RemoteTableChange.none);
      expect(RemoteTableSync.classify(baseSignature: sig(three), localSignature: sig(three), ownTableSignature: sig(five), localBillId: 'HD-1', remote: table(five)), RemoteTableChange.none);
    });

    test('chính máy này vừa thanh toán (bàn trống) → không báo nhầm', () {
      final c = RemoteTableSync.classify(baseSignature: sig(three), localSignature: sig(three), ownTableSignature: sig(const []), localBillId: 'HD-1', remote: table(const [], inUse: false, billId: null));
      expect(c, RemoteTableChange.none);
    });

    test('máy khác thanh toán / hủy đơn → báo đã đóng', () {
      final c = RemoteTableSync.classify(baseSignature: sig(three), localSignature: sig(three), ownTableSignature: sig(three), localBillId: 'HD-1', remote: table(const [], inUse: false, billId: null));
      expect(c, RemoteTableChange.closedElsewhere);
    });

    test('bàn sang hóa đơn khác (đơn mới của người khác) → để luồng tách bàn xử lý', () {
      final c = RemoteTableSync.classify(baseSignature: sig(three), localSignature: sig(three), localBillId: 'HD-1', remote: table(five, billId: 'HD-2'));
      expect(c, RemoteTableChange.none);
    });

    test('mở bàn mới chưa có món, bàn vẫn trống → không báo', () {
      final c = RemoteTableSync.classify(baseSignature: sig(const []), localSignature: sig([item(1, 'Trà')]), localBillId: 'HD-1', remote: table(const [], inUse: false));
      expect(c, RemoteTableChange.none);
    });
  });

  group('Dải cảnh báo mất kết nối / chưa đồng bộ', () {
    testWidgets('mất kết nối > 3 giây mới hiện; có mạng lại thì ẩn; màn hình bên dưới không bị dựng lại', (tester) async {
      final status = SyncStatus.instance;
      status.connected.value = true;
      await tester.pumpWidget(MaterialApp(home: SyncStatusFrame(status: status, child: const _Counter())));
      await tester.tap(find.text('0'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      status.connected.value = false;
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Mất kết nối'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Mất kết nối'), findsOneWidget);
      expect(find.text('1'), findsOneWidget, reason: 'trạng thái màn hình bên dưới phải được giữ');

      status.connected.value = true;
      await tester.pump();
      expect(find.textContaining('Mất kết nối'), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('ghi chưa được xác nhận > 4 giây → báo đang đồng bộ, xác nhận xong thì ẩn', (tester) async {
      final status = SyncStatus.instance;
      status.connected.value = true;
      await tester.pumpWidget(MaterialApp(home: SyncStatusFrame(status: status, child: const SizedBox())));
      final c = Completer<void>();
      status.track(c.future);
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('Đang đồng bộ 1 thay đổi'), findsOneWidget);
      c.complete();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Đang đồng bộ'), findsNothing);
      expect(status.pending.value, 0);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: () => setState(() => n++), child: Text('$n'));
}
