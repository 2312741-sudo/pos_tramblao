import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../../../models/store_model.dart';
import '../../../app/router.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/store_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../cc_firebase.dart';

class StoreSettingsScreen extends ConsumerStatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  ConsumerState<StoreSettingsScreen> createState() =>
      _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends ConsumerState<StoreSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _deptNameCtrl = TextEditingController();
  final _deptShortCtrl = TextEditingController();
  final _wifiNameCtrl = TextEditingController();

  String? _networkIP;
  String? _detectedSsid;
  String? _detectedBssid;
  String? _detectedLocalIp;
  bool _isFetchingWifi = false;
  List<StoreWifi> _wifis = [];

  bool _deliveryEnabled = true;
  final _deliveryAllowanceCtrl = TextEditingController();
  bool _giaoHangEnabled = true;
  final _giaoHangAllowanceCtrl = TextEditingController();

  double _radius = 100;
  double? _lat;
  double? _lng;
  List<StoreLocation> _locations = [];
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isFetchingLocation = false;
  bool _isRegeneratingCode = false;
  bool _initialized = false;
  List<DepartmentDefinition> _departments = [];
  bool _deptSelectionEnabled = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _deptNameCtrl.dispose();
    _deptShortCtrl.dispose();
    _wifiNameCtrl.dispose();
    _deliveryAllowanceCtrl.dispose();
    _giaoHangAllowanceCtrl.dispose();
    super.dispose();
  }

  void _initFromStore(StoreModel storeModel) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = storeModel.name;
    _addressCtrl.text = storeModel.address ?? '';
    _networkIP = storeModel.networkIP;
    _wifis = List.from(storeModel.wifis);
    _locations = List.from(storeModel.locations);
    if (_locations.isEmpty &&
        storeModel.latitude != null &&
        storeModel.longitude != null) {
      _locations.add(
        StoreLocation(
          id: 'loc_primary',
          name: 'Vị trí chính',
          latitude: storeModel.latitude!,
          longitude: storeModel.longitude!,
          radiusMeters: storeModel.radiusMeters,
        ),
      );
    }
    _deliveryEnabled = storeModel.deliveryEnabled;
    _deliveryAllowanceCtrl.text =
        (storeModel.deliveryAllowance ?? 0).toString();
    _giaoHangEnabled = storeModel.giaoHangEnabled;
    _giaoHangAllowanceCtrl.text =
        (storeModel.giaoHangAllowance ?? 0).toString();
    _radius = _locations.isNotEmpty
        ? _locations.first.radiusMeters.toDouble()
        : storeModel.radiusMeters.toDouble();
    _lat =
        _locations.isNotEmpty ? _locations.first.latitude : storeModel.latitude;
    _lng = _locations.isNotEmpty
        ? _locations.first.longitude
        : storeModel.longitude;
    _departments = List.from(storeModel.departments);
    _deptSelectionEnabled = storeModel.departmentSelectionEnabled;
  }

  Future<void> _fetchCurrentWifi() async {
    if (mounted) setState(() => _isFetchingWifi = true);
    try {
      final details = await LocationUtils.getCurrentWifiDetails();
      if (details.bssid == null || !LocationUtils.isValidBssid(details.bssid)) {
        throw Exception(
          'Không thể đọc BSSID của WiFi hiện tại. Hãy kiểm tra quyền Vị trí/WiFi và đảm bảo thiết bị đang kết nối WiFi.',
        );
      }

      if (mounted) {
        setState(() {
          _detectedBssid = details.bssid;
          _detectedSsid = details.ssid;
          _detectedLocalIp = details.localIp;
          if (details.ssid != null && details.ssid!.isNotEmpty) {
            _wifiNameCtrl.text = details.ssid!;
          } else {
            _wifiNameCtrl.text = 'WiFi ${_wifis.length + 1}';
          }
        });
        _showSuccess(_detectedSsid != null
            ? 'Đã nhận diện WiFi: $_detectedSsid'
            : 'Đã nhận diện BSSID: $_detectedBssid');
      }
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isFetchingWifi = false);
    }
  }

  Future<void> _fetchLocation() async {
    if (_locations.length >= 5) {
      _showError('Cửa hàng đã đạt tối đa 5 vị trí GPS');
      return;
    }
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Vui lòng bật dịch vụ vị trí');
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          _showError('Ứng dụng cần quyền vị trí');
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        _showError('Vui lòng cấp quyền vị trí trong cài đặt');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        _showAddLocationDialog(pos.latitude, pos.longitude);
      }
    } catch (e) {
      _showError('Không lấy được vị trí: $e');
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  void _showAddLocationDialog(double lat, double lng) {
    final nameCtrl = TextEditingController(
        text: _locations.isEmpty
            ? 'Cơ sở chính'
            : 'Vị trí ${_locations.length + 1}');
    double dialogRadius = 100;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Thêm vị trí GPS',
              style: TextStyle(
                  fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên vị trí *',
                    hintText: 'VD: Cơ sở chính, Kho sản xuất...',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.locateFixed,
                          color: AppColors.success, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tọa độ: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Bán kính chấm công: ${dialogRadius.round()}m',
                  style: const TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Slider(
                  value: dialogRadius,
                  min: 50,
                  max: 500,
                  divisions: 45,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.border,
                  onChanged: (v) => setDialogState(() => dialogRadius = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Huỷ',
                  style: TextStyle(fontFamily: 'BeVietnamPro')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  _showError('Vui lòng nhập tên vị trí');
                  return;
                }
                final newLoc = StoreLocation(
                  id: 'loc_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  latitude: lat,
                  longitude: lng,
                  radiusMeters: dialogRadius.round(),
                );
                setState(() {
                  _locations.add(newLoc);
                  if (_locations.length == 1) {
                    _lat = lat;
                    _lng = lng;
                    _radius = dialogRadius;
                  }
                });
                Navigator.pop(ctx);
                _showSuccess('Đã thêm vị trí: $name');
              },
              child: const Text('Thêm vị trí',
                  style: TextStyle(fontFamily: 'BeVietnamPro')),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditLocationDialog(int index, StoreLocation loc) {
    final nameCtrl = TextEditingController(text: loc.name);
    double dialogRadius = loc.radiusMeters.toDouble();
    double currentLat = loc.latitude;
    double currentLng = loc.longitude;
    bool isUpdatingPos = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Chỉnh sửa vị trí GPS',
              style: TextStyle(
                  fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên vị trí *',
                    hintText: 'VD: Cơ sở chính, Kho sản xuất...',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.locateFixed,
                          color: AppColors.success, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tọa độ: ${currentLat.toStringAsFixed(5)}, ${currentLng.toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: isUpdatingPos
                      ? null
                      : () async {
                          setDialogState(() => isUpdatingPos = true);
                          try {
                            final pos = await Geolocator.getCurrentPosition(
                              locationSettings: const LocationSettings(
                                accuracy: LocationAccuracy.high,
                                timeLimit: Duration(seconds: 15),
                              ),
                            );
                            setDialogState(() {
                              currentLat = pos.latitude;
                              currentLng = pos.longitude;
                              isUpdatingPos = false;
                            });
                            _showSuccess('Đã cập nhật tọa độ GPS mới');
                          } catch (e) {
                            setDialogState(() => isUpdatingPos = false);
                            _showError('Không lấy được vị trí: $e');
                          }
                        },
                  icon: isUpdatingPos
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.refreshCw, size: 16),
                  label: Text(
                    isUpdatingPos
                        ? 'Đang lấy...'
                        : 'Lấy tọa độ vị trí hiện tại',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bán kính chấm công: ${dialogRadius.round()}m',
                  style: const TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Slider(
                  value: dialogRadius,
                  min: 50,
                  max: 500,
                  divisions: 45,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.border,
                  onChanged: (v) => setDialogState(() => dialogRadius = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Huỷ',
                  style: TextStyle(fontFamily: 'BeVietnamPro')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final newName = nameCtrl.text.trim();
                if (newName.isEmpty) {
                  _showError('Vui lòng nhập tên vị trí');
                  return;
                }
                setState(() {
                  _locations[index] = loc.copyWith(
                    name: newName,
                    latitude: currentLat,
                    longitude: currentLng,
                    radiusMeters: dialogRadius.round(),
                  );
                  if (index == 0) {
                    _lat = currentLat;
                    _lng = currentLng;
                    _radius = dialogRadius;
                  }
                });
                Navigator.pop(ctx);
                _showSuccess('Đã cập nhật vị trí: $newName');
              },
              child: const Text('Lưu thay đổi',
                  style: TextStyle(fontFamily: 'BeVietnamPro')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(String storeId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      final primaryLoc = _locations.isNotEmpty ? _locations.first : null;
      await repo.updateStoreSettings(storeId, {
        'name': _nameCtrl.text.trim(),
        'address':
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'networkIP': _networkIP,
        'wifis': _wifis.map((w) => w.toJson()).toList(),
        'deliveryEnabled': _deliveryEnabled,
        'deliveryAllowance':
            num.tryParse(_deliveryAllowanceCtrl.text.trim()) ?? 0,
        'giaoHangEnabled': _giaoHangEnabled,
        'giaoHangAllowance':
            num.tryParse(_giaoHangAllowanceCtrl.text.trim()) ?? 0,
        'locations': _locations.map((l) => l.toJson()).toList(),
        'latitude': primaryLoc?.latitude ?? _lat,
        'longitude': primaryLoc?.longitude ?? _lng,
        'radiusMeters': primaryLoc?.radiusMeters ?? _radius.round(),
        'departments': _departments.map((d) => d.toJson()).toList(),
        'departmentSelectionEnabled': _deptSelectionEnabled,
      });
      _showSuccess('Đã lưu thay đổi');
    } catch (e) {
      _showError('Lưu thất bại: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddDepartmentDialog() {
    _deptNameCtrl.clear();
    _deptShortCtrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Thêm bộ phận',
            style: TextStyle(
                fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _deptNameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Tên bộ phận *', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _deptShortCtrl,
              decoration: const InputDecoration(
                  labelText: 'Tên viết tắt (VD: KD, KT)',
                  border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.characters,
              maxLength: 5,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              final name = _deptNameCtrl.text.trim();
              if (name.isEmpty) return;
              final shortName = _deptShortCtrl.text.trim().toUpperCase();
              final id = name.toLowerCase().replaceAll(' ', '_') +
                  '_' +
                  DateTime.now().millisecondsSinceEpoch.toString();
              setState(() {
                _departments.add(DepartmentDefinition(
                    id: id,
                    name: name,
                    shortName: shortName.isEmpty
                        ? name
                            .substring(0, name.length > 3 ? 3 : name.length)
                            .toUpperCase()
                        : shortName));
              });
              Navigator.pop(ctx);
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerateCode(String storeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tạo mã mới',
            style: TextStyle(
                fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700)),
        content: const Text(
          'Mã cũ sẽ hết hiệu lực. Nhân viên cần dùng mã mới để tham gia. Tiếp tục?',
          style: TextStyle(fontFamily: 'BeVietnamPro'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Hủy', style: TextStyle(fontFamily: 'BeVietnamPro')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Tạo mã mới',
                style: TextStyle(
                    fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRegeneratingCode = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      await repo.regenerateStoreCode(storeId);
      _showSuccess('Đã tạo mã mới');
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isRegeneratingCode = false);
    }
  }

  void _showEditWifiDialog(int index, StoreWifi wifi) {
    final ctrl = TextEditingController(text: wifi.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Đổi tên nhận diện WiFi',
            style: TextStyle(
                fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wifi.ssid.isNotEmpty)
              Text('SSID: ${wifi.ssid}',
                  style: const TextStyle(
                      fontFamily: 'BeVietnamPro',
                      color: AppColors.textSecondary,
                      fontSize: 12)),
            Text(
              wifi.hasValidBssid
                  ? 'BSSID: ${wifi.bssid}'
                  : (wifi.ip != null && wifi.ip!.isNotEmpty
                      ? 'IP Cũ: ${wifi.ip} (Cần cấu hình lại)'
                      : 'Chưa có BSSID'),
              style: TextStyle(
                fontFamily: 'BeVietnamPro',
                color: wifi.hasValidBssid
                    ? AppColors.textSecondary
                    : Colors.amber.shade900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Tên nhận diện WiFi',
                hintText: 'Nhập tên nhận diện...',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Huỷ',
                  style: TextStyle(fontFamily: 'BeVietnamPro'))),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                setState(() {
                  _wifis[index] = wifi.copyWith(name: newName);
                });
                _showSuccess('Đã đổi tên WiFi');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStore(StoreModel store) async {
    // Step 1: First Confirmation Dialog
    final firstConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(LucideIcons.triangleAlert,
                color: AppColors.danger, size: 28),
            SizedBox(width: 8),
            Text(
              'Xóa cửa hàng',
              style: TextStyle(
                fontFamily: 'BeVietnamPro',
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa cửa hàng "${store.name}"?\n\nHành động này không thể hoàn tác. Mọi thành viên sẽ mất quyền truy cập vào cửa hàng này.',
          style: const TextStyle(fontFamily: 'BeVietnamPro', height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Hủy', style: TextStyle(fontFamily: 'BeVietnamPro')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Tiếp tục',
              style: TextStyle(
                  fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (firstConfirmed != true || !mounted) return;

    // Step 2: Second confirmation - Type store name or "XÓA"
    final confirmCtrl = TextEditingController();
    final secondConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final text = confirmCtrl.text.trim();
          final isMatch = text == store.name.trim() ||
              text.toUpperCase() == 'XÓA' ||
              text.toUpperCase() == 'XOA';
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Xác nhận lần cuối',
              style: TextStyle(
                fontFamily: 'BeVietnamPro',
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vui lòng nhập chính xác tên cửa hàng "${store.name}" hoặc gõ "XÓA" để xác nhận:',
                  style:
                      const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: confirmCtrl,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Nhập "${store.name}" hoặc "XÓA"',
                    border: const OutlineInputBorder(),
                    errorText: confirmCtrl.text.isNotEmpty && !isMatch
                        ? 'Tên xác nhận chưa khớp'
                        : null,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy',
                    style: TextStyle(fontFamily: 'BeVietnamPro')),
              ),
              ElevatedButton(
                onPressed: isMatch ? () => Navigator.pop(ctx, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.danger.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Xóa vĩnh viễn',
                  style: TextStyle(
                      fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (secondConfirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final repo = ref.read(storeRepositoryProvider);
      await repo.deleteStore(store.id);

      if (!mounted) return;
      _showSuccess('Đã xóa cửa hàng "${store.name}"');

      // Invalidate providers
      ref.invalidate(userStoresProvider);

      context.go(AppRoutes.splash);
    } catch (e) {
      _showError('Xóa cửa hàng thất bại: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _leaveStore(StoreModel store) async {
    final repo = ref.read(storeRepositoryProvider);
    final currentUserId = CcFirebase.auth.currentUser?.uid ?? '';

    String? successorName;
    bool isAlone = false;

    final nextOwnerId = await repo.findNextOwnerId(store.id, currentUserId);
    if (nextOwnerId != null) {
      final memberDoc = await CcFirebase.firestore
          .collection('stores')
          .doc(store.id)
          .collection('members')
          .doc(nextOwnerId)
          .get();
      successorName = memberDoc.data()?['name'] as String? ?? 'Quản lý 1';
    } else {
      isAlone = true;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.triangleAlert,
                color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Rời cửa hàng',
              style: TextStyle(
                  fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          isAlone
              ? 'Bạn là thành viên duy nhất của "${store.name}".\n\nKhi bạn rời đi, cửa hàng sẽ tự động đóng và không thể hoàn tác. Bạn có chắc chắn muốn rời cửa hàng?'
              : 'Bạn đang là Chủ cửa hàng "${store.name}".\n\nKhi bạn rời đi, quyền Chủ cửa hàng sẽ được TỰ ĐỘNG CHUYỂN GIAO cho: $successorName.\n\nBạn có chắc chắn muốn rời cửa hàng?',
          style: const TextStyle(
              fontFamily: 'BeVietnamPro', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Hủy',
                style: TextStyle(
                    fontFamily: 'BeVietnamPro', color: AppColors.neutral)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Xác nhận rời',
                style: TextStyle(
                    fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeleting = true);
      try {
        await repo.leaveStore(store.id);

        if (!mounted) return;
        _showSuccess('Bạn đã rời khỏi cửa hàng "${store.name}"');

        // Invalidate providers
        ref.invalidate(userStoresProvider);
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStoreProvider);
        ref.invalidate(currentMemberStreamProvider);
        ref.invalidate(currentMemberProvider);
        ref.invalidate(storeMembersProvider);
        ref.invalidate(activeMembersProvider);

        context.go(AppRoutes.splash);
      } catch (e) {
        _showError('Rời cửa hàng thất bại: $e');
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }


  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(currentStoreProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final currentMember = ref.watch(currentMemberProvider);

    return storeAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Lỗi: $e')),
      ),
      data: (store) {
        if (store == null) {
          return const Scaffold(
            body: Center(child: Text('Không tìm thấy cửa hàng')),
          );
        }
        final isOwner =
            store.isOwnerUid(currentUserId) || currentMember?.isOwner == true;
        _initFromStore(store);
        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            title: const Text(
              'Cài đặt cửa hàng',
              style: TextStyle(
                  fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700),
            ),
          ),
          body: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHeader(title: 'Thông tin cơ bản'),
                  const SizedBox(height: 12),
                  const _Label('Tên cửa hàng *'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _nameCtrl,
                    hint: 'Tên cửa hàng',
                    icon: LucideIcons.store,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vui lòng nhập tên'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    controller: _addressCtrl,
                    hint: 'Địa chỉ cửa hàng',
                    icon: LucideIcons.mapPin,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  const _Label('Cấu hình WiFi chấm công (BSSID Access Point)'),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _isFetchingWifi ? null : _fetchCurrentWifi,
                    icon: _isFetchingWifi
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(LucideIcons.wifi),
                    label: Text(
                      _isFetchingWifi
                          ? 'Đang nhận diện WiFi...'
                          : 'Lấy WiFi hiện tại',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      textStyle: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (_detectedBssid != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                LucideIcons.wifi,
                                color: AppColors.success,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _detectedSsid != null
                                      ? 'Đã nhận diện: $_detectedSsid'
                                      : 'Đã nhận diện BSSID Access Point',
                                  style: const TextStyle(
                                    fontFamily: 'BeVietnamPro',
                                    fontSize: 13,
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(LucideIcons.x,
                                    color: AppColors.danger, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => setState(() {
                                  _detectedBssid = null;
                                  _detectedSsid = null;
                                  _detectedLocalIp = null;
                                  _wifiNameCtrl.clear();
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _wifiNameCtrl,
                            decoration: InputDecoration(
                              labelText: 'Tên nhận diện WiFi',
                              hintText: 'VD: WiFi Tầng 1 / Quầy Thu Ngân',
                              prefixIcon:
                                  const Icon(LucideIcons.notebookPen, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                            style: const TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(LucideIcons.fingerprint,
                                        size: 16,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'BSSID (MAC): $_detectedBssid',
                                        style: const TextStyle(
                                          fontFamily: 'BeVietnamPro',
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_detectedLocalIp != null) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(LucideIcons.router,
                                          size: 16,
                                          color: AppColors.textSecondary),
                                      const SizedBox(width: 6),
                                      Flexible(child: Text(
                                        'IP nội bộ: $_detectedLocalIp',
                                        style: const TextStyle(
                                          fontFamily: 'BeVietnamPro',
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (_wifis.length >= 10) {
                                  _showError(
                                      'Đã đạt tối đa 10 điểm WiFi cho phép.');
                                  return;
                                }
                                final normNew = LocationUtils.normalizeBssid(
                                    _detectedBssid!);
                                if (_wifis.any((w) =>
                                    LocationUtils.normalizeBssid(w.bssid) ==
                                    normNew)) {
                                  _showError('WiFi này đã được thêm.');
                                  return;
                                }
                                final nameToSave =
                                    _wifiNameCtrl.text.trim().isNotEmpty
                                        ? _wifiNameCtrl.text.trim()
                                        : (_detectedSsid ??
                                            'WiFi ${_wifis.length + 1}');
                                setState(() {
                                  _wifis.add(StoreWifi(
                                    name: nameToSave,
                                    ssid: _detectedSsid ?? '',
                                    bssid: _detectedBssid!,
                                    createdAt: DateTime.now(),
                                  ));
                                  _detectedBssid = null;
                                  _detectedSsid = null;
                                  _detectedLocalIp = null;
                                  _wifiNameCtrl.clear();
                                });
                                _showSuccess(
                                    'Đã thêm "$nameToSave" vào danh sách');
                              },
                              icon: const Icon(LucideIcons.plus, size: 18),
                              label: const Text(
                                  'Thêm vào danh sách cho phép (Tối đa 10)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Label('Danh sách WiFi cho phép (${_wifis.length}/10)'),
                      if (_wifis.isNotEmpty)
                        Text(
                          '${10 - _wifis.length} vị trí còn lại',
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_wifis.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: const [
                          Icon(LucideIcons.wifiOff,
                              color: AppColors.textSecondary, size: 32),
                          SizedBox(height: 8),
                          Text(
                            'Chưa cấu hình WiFi nào.\nKết nối mạng tại điểm làm việc và nhấn "Lấy WiFi mạng hiện tại" để thêm.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._wifis.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final wifi = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  fontFamily: 'BeVietnamPro',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          wifi.name,
                                          style: const TextStyle(
                                            fontFamily: 'BeVietnamPro',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (!wifi.hasValidBssid)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade100,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Cần cập nhật BSSID',
                                            style: TextStyle(
                                              fontFamily: 'BeVietnamPro',
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  if (wifi.ssid.isNotEmpty)
                                    Text(
                                      'SSID: ${wifi.ssid}',
                                      style: const TextStyle(
                                        fontFamily: 'BeVietnamPro',
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  Text(
                                    wifi.hasValidBssid
                                        ? 'BSSID: ${wifi.bssid}'
                                        : (wifi.ip != null &&
                                                wifi.ip!.isNotEmpty
                                            ? 'IP Cũ: ${wifi.ip} (Không còn dùng)'
                                            : 'Chưa có BSSID'),
                                    style: TextStyle(
                                      fontFamily: 'BeVietnamPro',
                                      color: wifi.hasValidBssid
                                          ? AppColors.textSecondary
                                          : Colors.red.shade700,
                                      fontSize: 12,
                                      fontWeight: wifi.hasValidBssid
                                          ? FontWeight.normal
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.pencil,
                                  color: AppColors.primary, size: 20),
                              tooltip: 'Đổi tên WiFi',
                              onPressed: () => _showEditWifiDialog(idx, wifi),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.trash2,
                                  color: AppColors.danger, size: 20),
                              tooltip: 'Xoá WiFi này',
                              onPressed: () {
                                setState(() => _wifis.removeAt(idx));
                                _showSuccess('Đã xoá WiFi');
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 20),

                  const _SectionHeader(title: 'Vị trí GPS (Tối đa 5 vị trí)'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Label(
                          'Danh sách Vị trí GPS cho phép (${_locations.length}/5)'),
                      if (_locations.isNotEmpty)
                        Text(
                          '${5 - _locations.length} vị trí còn lại',
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_locations.length < 5)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: _isFetchingLocation ? null : _fetchLocation,
                        icon: _isFetchingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary))
                            : const Icon(LucideIcons.mapPinPlus),
                        label: Text(_isFetchingLocation
                            ? 'Đang lấy vị trí GPS...'
                            : '+ Thêm vị trí GPS hiện tại'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  if (_locations.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: const [
                          Icon(LucideIcons.mapPinOff,
                              color: AppColors.textSecondary, size: 32),
                          SizedBox(height: 8),
                          Text(
                            'Chưa cấu hình vị trí GPS nào.\nĐứng tại điểm làm việc và nhấn "+ Thêm vị trí GPS hiện tại" để thiết lập.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._locations.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final loc = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  fontFamily: 'BeVietnamPro',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc.name,
                                    style: const TextStyle(
                                      fontFamily: 'BeVietnamPro',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)} • Bán kính: ${loc.radiusMeters}m',
                                    style: const TextStyle(
                                      fontFamily: 'BeVietnamPro',
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.pencil,
                                  color: AppColors.primary, size: 20),
                              tooltip: 'Sửa tên & bán kính vị trí',
                              onPressed: () =>
                                  _showEditLocationDialog(idx, loc),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.trash2,
                                  color: AppColors.danger, size: 20),
                              tooltip: 'Xoá vị trí này',
                              onPressed: () {
                                setState(() {
                                  _locations.removeAt(idx);
                                  if (_locations.isNotEmpty) {
                                    _lat = _locations.first.latitude;
                                    _lng = _locations.first.longitude;
                                    _radius = _locations.first.radiusMeters
                                        .toDouble();
                                  } else {
                                    _lat = null;
                                    _lng = null;
                                  }
                                });
                                _showSuccess('Đã xoá vị trí');
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 20),

                  const _SectionHeader(title: 'Mã cửa hàng'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                store.code,
                                style: const TextStyle(
                                  fontFamily: 'BeVietnamPro',
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 6,
                                  color: AppColors.neutral,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.copy,
                                  color: AppColors.info),
                              tooltip: 'Sao chép mã',
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: store.code));
                                _showSuccess('Đã sao chép mã: ${store.code}');
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isRegeneratingCode
                                ? null
                                : () => _regenerateCode(store.id),
                            icon: _isRegeneratingCode
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary))
                                : const Icon(LucideIcons.refreshCw),
                            label: const Text('Tạo mã mới'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const _SectionHeader(title: 'Mã QR'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        QrImageView(
                          data: store.code,
                          size: 200,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          store.code,
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => context.push(AppRoutes.qrDisplay),
                            icon: const Icon(LucideIcons.maximize2),
                            label: const Text('Xem mã QR toàn màn hình'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.info,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Shift Settings
                  const _SectionHeader(title: 'Quản lý ca làm'),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => context.push('/shift-settings'),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(LucideIcons.clock,
                                color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cài đặt ca làm',
                                    style: TextStyle(
                                        fontFamily: 'BeVietnamPro',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.neutral)),
                                SizedBox(height: 2),
                                Text('Thêm, sửa, xóa ca và giờ làm',
                                    style: TextStyle(
                                        fontFamily: 'BeVietnamPro',
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          const Icon(LucideIcons.chevronRight,
                              color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Production Tasks Checklist Management
                  InkWell(
                    onTap: () => context.push(AppRoutes.productionTasks),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C7ED6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(LucideIcons.listChecks,
                                color: Color(0xFF1C7ED6), size: 20),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Checklist sản xuất & vận hành',
                                    style: TextStyle(
                                        fontFamily: 'BeVietnamPro',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.neutral)),
                                SizedBox(height: 2),
                                Text(
                                    'Sắp xếp thứ tự và quản lý đầu việc checklist',
                                    style: TextStyle(
                                        fontFamily: 'BeVietnamPro',
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          const Icon(LucideIcons.chevronRight,
                              color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Department Management
                  const _SectionHeader(title: 'Quản lý bộ phận'),
                  const SizedBox(height: 8),
                  const Text(
                    'Định nghĩa các bộ phận để NV/QL chọn khi đăng ký ca làm.',
                    style: TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 12,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  // Toggle bật/tắt chọn bộ phận
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cho phép NV/QL chọn bộ phận',
                          style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      subtitle: Text(
                        _deptSelectionEnabled
                            ? 'Đang bật – NV/QL thấy danh sách bộ phận khi đăng ký ca'
                            : 'Đang tắt – NV/QL không thấy tùy chọn bộ phận',
                        style: const TextStyle(
                            fontFamily: 'BeVietnamPro', fontSize: 12),
                      ),
                      value: _deptSelectionEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) =>
                          setState(() => _deptSelectionEnabled = val),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_departments.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Center(
                        child: Text('Chưa có bộ phận nào. Bấm + để thêm.',
                            style: TextStyle(
                                fontFamily: 'BeVietnamPro',
                                color: AppColors.textSecondary)),
                      ),
                    )
                  else
                    ...List.generate(_departments.length, (i) {
                      final dept = _departments[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(dept.shortName,
                                  style: const TextStyle(
                                      fontFamily: 'BeVietnamPro',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: AppColors.primary)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(dept.name,
                                    style: const TextStyle(
                                        fontFamily: 'BeVietnamPro',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600))),
                            IconButton(
                              icon: const Icon(LucideIcons.trash2,
                                  color: AppColors.danger, size: 20),
                              onPressed: () =>
                                  setState(() => _departments.removeAt(i)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _showAddDepartmentDialog,
                    icon: const Icon(LucideIcons.plus),
                    label: const Text('Thêm bộ phận',
                        style: TextStyle(fontFamily: 'BeVietnamPro')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Cài đặt Giao hàng / Chở hàng
                  const _SectionHeader(title: 'Cài đặt Phụ cấp'),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cho phép đăng ký Chở hàng',
                          style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      subtitle: const Text(
                          'Tích vào lịch để tính phụ cấp chở hàng',
                          style: TextStyle(
                              fontFamily: 'BeVietnamPro', fontSize: 12)),
                      value: _deliveryEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) =>
                          setState(() => _deliveryEnabled = val),
                    ),
                  ),
                  if (_deliveryEnabled) ...[
                    const SizedBox(height: 12),
                    const _Label('Mức phụ cấp Chở hàng (VNĐ)'),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _deliveryAllowanceCtrl,
                      hint: 'VD: 15000',
                      icon: LucideIcons.circleDollarSign,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cho phép đăng ký Giao hàng',
                          style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      subtitle: const Text(
                          'Tích vào lịch để tính phụ cấp giao hàng',
                          style: TextStyle(
                              fontFamily: 'BeVietnamPro', fontSize: 12)),
                      value: _giaoHangEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) =>
                          setState(() => _giaoHangEnabled = val),
                    ),
                  ),
                  if (_giaoHangEnabled) ...[
                    const SizedBox(height: 12),
                    const _Label('Mức phụ cấp Giao hàng (VNĐ)'),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _giaoHangAllowanceCtrl,
                      hint: 'VD: 15000',
                      icon: LucideIcons.circleDollarSign,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Save button

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : () => _save(store.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withOpacity(0.6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : const Text(
                              'Lưu thay đổi',
                              style: TextStyle(
                                  fontFamily: 'BeVietnamPro',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),

                  // Danger Zone (Owner only)
                  if (isOwner) ...[
                    const SizedBox(height: 36),
                    const _SectionHeader(title: 'Vùng nguy hiểm'),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.danger.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(LucideIcons.trash2,
                                  color: AppColors.danger, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Xóa cửa hàng',
                                style: TextStyle(
                                  fontFamily: 'BeVietnamPro',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Thao tác này sẽ xóa cửa hàng và gỡ bỏ tất cả thành viên khỏi cửa hàng. Chỉ Chủ cửa hàng mới có quyền thực hiện.',
                            style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isDeleting
                                  ? null
                                  : () => _leaveStore(store),
                              icon: const Icon(LucideIcons.logOut,
                                  size: 18, color: AppColors.warning),
                              label: const Text(
                                'Rời cửa hàng (Chuyển quyền cho QL1)',
                                style: TextStyle(
                                  fontFamily: 'BeVietnamPro',
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.warning),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isDeleting
                                  ? null
                                  : () => _deleteStore(store),
                              icon: _isDeleting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.danger,
                                      ),
                                    )
                                  : const Icon(LucideIcons.trash2,
                                      size: 18),
                              label: Text(_isDeleting
                                  ? 'Đang xóa...'
                                  : 'Xóa cửa hàng này'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'BeVietnamPro',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.neutral,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'BeVietnamPro',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'BeVietnamPro', color: AppColors.textDisabled),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary)),
      ),
    );
  }
}
