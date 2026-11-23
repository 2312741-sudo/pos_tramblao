// lib/chamcong_blao/link_store_dialog.dart
//
// Chủ quán liên kết cửa hàng POS hiện tại với một cửa hàng bên Chấm Công BLAO (dự án chamcongtramblao).
// Làm một lần; sau đó nhân viên POS của cửa hàng này mở Chấm công là tự đăng nhập (chamCongBlaoSignIn).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../core/services/auth_service.dart';

class ChamCongBlaoLinkDialog extends StatefulWidget {
  const ChamCongBlaoLinkDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const ChamCongBlaoLinkDialog());

  @override
  State<ChamCongBlaoLinkDialog> createState() => _ChamCongBlaoLinkDialogState();
}

class _ChamCongBlaoLinkDialogState extends State<ChamCongBlaoLinkDialog> {
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  late final String _storeCode = AuthService().currentStoreCode;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _stores = const [];
  String? _currentId;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _functions.httpsCallable('chamCongBlaoListStores').call({'storeCode': _storeCode});
      final data = Map<String, dynamic>.from(res.data as Map);
      final stores = [for (final s in (data['stores'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
      final current = data['current'] is Map ? Map<String, dynamic>.from(data['current'] as Map) : null;
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _currentId = current?['ccStoreId'] as String?;
        _selected = _currentId;
        _loading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() {
        _error = e.message ?? 'Không tải được danh sách cửa hàng chấm công.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final id = _selected;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await _functions.httpsCallable('chamCongBlaoLinkStore').call({'storeCode': _storeCode, 'ccStoreId': id});
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã liên kết Chấm Công BLAO. Nhân viên mở mục Chấm công là tự đăng nhập.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() {
        _error = e.message ?? 'Liên kết thất bại.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Liên kết Chấm Công BLAO'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chọn cửa hàng chấm công tương ứng với chi nhánh $_storeCode. '
                      'Nhân viên sẽ chấm công bằng chính tài khoản POS; ai trùng tên với nhân viên chấm công cũ sẽ được nối vào tài khoản cũ.'),
                  const SizedBox(height: 12),
                  if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (_stores.isEmpty && _error == null) const Text('Chưa có cửa hàng nào bên Chấm Công BLAO.'),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final s in _stores)
                          RadioListTile<String>(
                            value: s['ccStoreId'] as String,
                            groupValue: _selected,
                            onChanged: _saving ? null : (v) => setState(() => _selected = v),
                            title: Text(s['name'] as String? ?? ''),
                            subtitle: Text([
                              if ((s['code'] as String? ?? '').isNotEmpty) 'Mã: ${s['code']}',
                              if (s['ccStoreId'] == _currentId) 'Đang liên kết',
                            ].join(' • ')),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Đóng')),
        if (!_loading && _error != null && _stores.isEmpty)
          TextButton(onPressed: _load, child: const Text('Thử lại')),
        FilledButton(
          onPressed: _saving || _selected == null || _selected == _currentId ? null : _save,
          child: Text(_saving ? 'Đang lưu...' : 'Liên kết'),
        ),
      ],
    );
  }
}
