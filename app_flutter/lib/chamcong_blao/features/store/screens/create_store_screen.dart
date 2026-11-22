import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/location_utils.dart';
import '../../auth/providers/auth_notifier.dart';
import '../providers/store_provider.dart';
import '../providers/user_repository.dart';
import '../../../app/router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CreateStoreScreen extends ConsumerStatefulWidget {
  const CreateStoreScreen({super.key});

  @override
  ConsumerState<CreateStoreScreen> createState() => _CreateStoreScreenState();
}

class _CreateStoreScreenState extends ConsumerState<CreateStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _wifiNameCtrl = TextEditingController();
  final _locationNameCtrl = TextEditingController();

  String? _detectedBssid;
  String? _detectedSsid;
  String? _detectedLocalIp;
  bool _isFetchingWifi = false;

  double _radius = 100;
  double? _lat;
  double? _lng;
  bool _isLoading = false;
  bool _isFetchingLocation = false;
  String? _locationLabel;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _wifiNameCtrl.dispose();
    _locationNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentWifi() async {
    setState(() => _isFetchingWifi = true);
    try {
      final details = await LocationUtils.getCurrentWifiDetails();
      if (details.bssid == null || !LocationUtils.isValidBssid(details.bssid)) {
        throw Exception(
          'Không thể đọc BSSID của WiFi hiện tại. Hãy kiểm tra quyền Vị trí/WiFi và đảm bảo thiết bị đang kết nối WiFi.',
        );
      }

      setState(() {
        _detectedBssid = details.bssid;
        _detectedSsid = details.ssid;
        _detectedLocalIp = details.localIp;
        if (details.ssid != null && details.ssid!.isNotEmpty) {
          _wifiNameCtrl.text = details.ssid!;
        } else {
          _wifiNameCtrl.text = 'WiFi Chính';
        }
      });
      _showSuccess(_detectedSsid != null
          ? 'Đã nhận diện WiFi: $_detectedSsid'
          : 'Đã nhận diện BSSID: $_detectedBssid');
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isFetchingWifi = false);
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _fetchLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Vui lòng bật dịch vụ vị trí');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Ứng dụng cần quyền truy cập vị trí');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError('Vui lòng cấp quyền vị trí trong cài đặt');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locationLabel =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      });
    } catch (e) {
      _showError('Không lấy được vị trí: $e');
    } finally {
      setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(storeRepositoryProvider);
      final userRepo = ref.read(userRepositoryProvider);
      final user = ref.read(userProvider).value;
      if (user == null) throw Exception('Chưa đăng nhập');

      final store = await repo.createStore(
        _nameCtrl.text.trim(),
        _addressCtrl.text.trim(),
        '',
        _lat,
        _lng,
        _radius.round(),
        wifiName: _wifiNameCtrl.text.trim().isNotEmpty
            ? _wifiNameCtrl.text.trim()
            : (_detectedSsid ?? 'WiFi Chính'),
        wifiSsid: _detectedSsid,
        wifiBssid: _detectedBssid,
        locationName: _locationNameCtrl.text.trim().isNotEmpty
            ? _locationNameCtrl.text.trim()
            : 'Cơ sở chính',
      );

      await userRepo.updateCurrentStoreId(user.id, store.id);

      ref.invalidate(userStoresProvider);

      if (mounted) context.go(AppRoutes.splash);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Tạo cửa hàng mới',
          style: TextStyle(
            fontFamily: 'BeVietnamPro',
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.logOut, color: Colors.white),
            tooltip: 'Đăng xuất',
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ],
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(LucideIcons.store,
                          color: AppColors.primary, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Điền thông tin cửa hàng của bạn để bắt đầu quản lý chấm công',
                          style: TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Store name
                const _SectionLabel(label: 'Tên cửa hàng *'),
                const SizedBox(height: 8),
                _AppTextField(
                  controller: _nameCtrl,
                  hintText: 'Ví dụ: Trạm xăng Hoàng Minh',
                  prefixIcon: LucideIcons.store,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Vui lòng nhập tên cửa hàng';
                    }
                    if (v.trim().length < 3) {
                      return 'Tên cửa hàng cần ít nhất 3 ký tự';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Address
                const _SectionLabel(label: 'Địa chỉ'),
                const SizedBox(height: 8),
                _AppTextField(
                  controller: _addressCtrl,
                  hintText: 'Ví dụ: 123 Nguyễn Văn Cừ, Quận 5, TP.HCM',
                  prefixIcon: LucideIcons.mapPin,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Network IP
                const _SectionLabel(label: 'Địa chỉ IP Mạng (tùy chọn)'),
                const SizedBox(height: 4),
                const Text(
                  'Nhân viên sẽ chấm công khi kết nối cùng mạng WiFi với IP này',
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
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
                    _isFetchingWifi ? 'Đang nhận diện...' : 'Lấy WiFi hiện tại',
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.wifi,
                              color: AppColors.success,
                              size: 20,
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
                                  color: AppColors.danger, size: 18),
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
                        const SizedBox(height: 8),
                        TextField(
                          controller: _wifiNameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Tên nhận diện WiFi',
                            hintText: 'VD: WiFi Chính / Cửa hàng',
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(LucideIcons.fingerprint,
                                size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'BSSID: $_detectedBssid',
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
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // GPS section
                const _SectionLabel(label: 'Vị trí GPS (tùy chọn)'),
                const SizedBox(height: 4),
                const Text(
                  'Dùng GPS để xác minh nhân viên ở gần cửa hàng',
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isFetchingLocation ? null : _fetchLocation,
                  icon: _isFetchingLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(LucideIcons.locateFixed),
                  label: Text(
                    _isFetchingLocation
                        ? 'Đang lấy vị trí...'
                        : 'Ấn để lấy vị trí hiện tại',
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
                if (_locationLabel != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.circleCheck,
                            color: AppColors.success, size: 16),
                        const SizedBox(width: 8),
                        Flexible(child: Text(
                          'Vị trí: $_locationLabel',
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _locationNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Tên vị trí này (tùy chọn)',
                      hintText: 'VD: Cơ sở chính, Điểm bán 1...',
                      prefixIcon: const Icon(LucideIcons.tag,
                          color: AppColors.primary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ],
                const SizedBox(height: 20),

                // Radius slider
                _SectionLabel(label: 'Bán kính cho phép: ${_radius.round()}m'),
                Slider(
                  value: _radius,
                  min: 50,
                  max: 500,
                  divisions: 45,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.border,
                  label: '${_radius.round()}m',
                  onChanged: (v) => setState(() => _radius = v),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('50m',
                        style: TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                    Text('500m',
                        style: TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 32),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.primary.withOpacity(0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Tạo cửa hàng',
                            style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'BeVietnamPro',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.neutral,
      ),
    );
  }
}

class _AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final int maxLines;
  final String? Function(String?)? validator;

  const _AppTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(
        fontFamily: 'BeVietnamPro',
        fontSize: 15,
        color: AppColors.neutral,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          fontFamily: 'BeVietnamPro',
          color: AppColors.textDisabled,
          fontSize: 14,
        ),
        prefixIcon: Icon(prefixIcon, color: AppColors.textSecondary, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
