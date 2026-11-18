import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_merge.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';

/// Tái hiện lỗi "gọi thêm món xong lúc sau mất món" (màn giỏ món quay về sau màn Thêm món).
OrderItemModel item(int id, String name, int orderedAt, {int qty = 1}) =>
    OrderItemModel(productId: id, name: name, price: 20000, quantity: qty, orderedAt: orderedAt);

String js(List<OrderItemModel> l) => jsonEncode(l.map((e) => e.toMap()).toList());
List<String> names(String json) => [for (final e in jsonDecode(json) as List) (e as Map)['name'] as String];

void main() {
  final a = item(1, 'Trà đào', 1000);
  final choco = item(2, 'Choco chip nhỏ', 2000);
  final flan = item(3, 'Bánh flan', 3000); // máy khác gọi
  final matcha = item(4, 'Matcha', 4000); // máy này gọi thêm

  test('gọi thêm món khi máy khác cũng vừa thêm: thứ tự xử lý ĐÚNG giữ đủ món', () {
    final base0 = js([a, choco]);
    final serverByOther = js([a, choco, flan]);
    // Màn Thêm món lưu: gộp phần máy này thêm vào bản mới nhất trên server
    final addLocal = js([a, choco, matcha]);
    final serverAfterAdd = OrderMerge.mergeJson(base: base0, local: addLocal, server: serverByOther);
    expect(names(serverAfterAdd), containsAll(['Trà đào', 'Choco chip nhỏ', 'Bánh flan', 'Matcha']));

    // Về màn giỏ món: lấy giỏ từ màn Thêm món TRƯỚC (giỏ = bản vừa lưu = base mới), rồi mới áp cập nhật đang giữ
    final base1 = addLocal;
    final cartAfterResume = OrderMerge.mergeJson(base: base1, local: addLocal, server: serverAfterAdd);
    expect(names(cartAfterResume), containsAll(['Trà đào', 'Choco chip nhỏ', 'Bánh flan', 'Matcha']));
  });

  test('thứ tự CŨ (áp cập nhật vào giỏ chưa có món mới) làm mất món — lý do phải sửa', () {
    final base0 = js([a, choco]);
    final serverByOther = js([a, choco, flan]);
    final addLocal = js([a, choco, matcha]);
    final serverAfterAdd = OrderMerge.mergeJson(base: base0, local: addLocal, server: serverByOther);
    final oldCart = js([a, choco]); // giỏ màn giỏ món lúc trước khi mở màn Thêm món
    final wrong = OrderMerge.mergeJson(base: addLocal, local: oldCart, server: serverAfterAdd);
    expect(names(wrong), isNot(contains('Matcha')), reason: 'món vừa gọi bị coi là "máy này đã xóa"');
  });
}
