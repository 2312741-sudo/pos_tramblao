import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';

class BlaoBatchTimerPreset {
  final String id;
  final String title;
  final String station;
  final String tempSpec;
  final int durationSeconds;
  final String guideline;
  final IconData icon;
  final Color accentColor;

  const BlaoBatchTimerPreset({
    required this.id,
    required this.title,
    required this.station,
    required this.tempSpec,
    required this.durationSeconds,
    required this.guideline,
    required this.icon,
    required this.accentColor,
  });
}

class BlaoSopSectionData {
  final String stationName;
  final String badgeText;
  final IconData icon;
  final Color color;
  final List<String> standards;

  const BlaoSopSectionData({
    required this.stationName,
    required this.badgeText,
    required this.icon,
    required this.color,
    required this.standards,
  });
}

class BlaoStationSopScreen extends StatefulWidget {
  const BlaoStationSopScreen({super.key});

  @override
  State<BlaoStationSopScreen> createState() => _BlaoStationSopScreenState();
}

class _BlaoStationSopScreenState extends State<BlaoStationSopScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _telemetryChannel =
      MethodChannel('com.tramblao.chamcong/station_telemetry');

  late final TabController _tabController;
  Timer? _ticker;

  static const List<BlaoBatchTimerPreset> _presets = [
    BlaoBatchTimerPreset(
      id: 'banh_truyen_thong',
      title: 'Bánh Lăn Nướng Truyền Thống',
      station: 'Quầy Bánh Lăn',
      tempSpec: 'Lò 185°C • 6 phút',
      durationSeconds: 360,
      guideline:
          'Làm nóng khuôn trước 3 phút. Quét lớp bơ mỏng đều 2 mặt, nướng vàng giòn vỏ ngoài, thơm mùi bơ sữa đặc trưng Trạm BLAO.',
      icon: LucideIcons.croissant,
      accentColor: Color(0xFFC77639),
    ),
    BlaoBatchTimerPreset(
      id: 'banh_pho_mai_choco',
      title: 'Bánh Lăn Phô Mai Chảy / Choco Chip',
      station: 'Quầy Bánh Lăn',
      tempSpec: 'Lò 190°C • 7 phút',
      durationSeconds: 420,
      guideline:
          'Định lượng nhân phô mai chảy / choco chip đúng chuẩn 18g/cái. Kiểm tra mép bánh khép kín tránh tràn nhân khi nướng.',
      icon: LucideIcons.flame,
      accentColor: Color(0xFFC91506),
    ),
    BlaoBatchTimerPreset(
      id: 'tra_olong_blao',
      title: 'Ủ Cốt Trà Ô Long Blao Cao Nguyên',
      station: 'Quầy Trà Ô Long',
      tempSpec: 'Nước 92°C • 12 phút',
      durationSeconds: 720,
      guideline:
          'Dùng lá trà Ô Long Bảo Lộc tuyển chọn. Tráng trà nhanh 5 giây bằng nước sôi trước khi ủ. Sau khi lọc bã, sốc nhiệt với đá tinh khiết để giữ hương cốm non.',
      icon: LucideIcons.cupSoda,
      accentColor: Color(0xFF146A65),
    ),
    BlaoBatchTimerPreset(
      id: 'tra_trai_cay_nen',
      title: 'Ủ Nền Trà Nhiệt Đới & Chanh Đào',
      station: 'Quầy Trà Ô Long',
      tempSpec: 'Nước 90°C • 9 phút',
      durationSeconds: 540,
      guideline:
          'Không khuấy mạnh trong lúc ủ để tránh chát. Bảo quản bình giữ nhiệt chuyên dụng và sử dụng trong vòng 4 tiếng.',
      icon: LucideIcons.sparkles,
      accentColor: Color(0xFF1E8E87),
    ),
  ];

  static const List<BlaoSopSectionData> _sopSections = [
    BlaoSopSectionData(
      stationName: '1. Quầy Bánh Lăn Nướng (Baked Roll Station)',
      badgeText: 'Đặc sản Trạm BLAO',
      icon: LucideIcons.croissant,
      color: Color(0xFFC77639),
      standards: [
        'Khởi động lò nướng trước giờ mở ca 15 phút để đạt nhiệt độ ổn định 185°C – 190°C.',
        'Bột bánh lăn pha mới theo mẻ sáng/chiều; bảo quản lạnh ở 4°C khi chưa sử dụng.',
        'Bánh sau khi ra lò đặt lên vỉ thoáng khí 45 giây cho giòn vỏ trước khi cho vào túi giấy Kraft Trạm BLAO.',
        'Thời gian giữ nóng tối đa trong tủ trưng bày là 90 phút; tuyệt đối không phục vụ bánh bị ỉu hoặc quá thời gian quy định.',
      ],
    ),
    BlaoSopSectionData(
      stationName: '2. Quầy Trà Ô Long & Trái Cây Tươi',
      badgeText: 'Chuẩn vị Bảo Lộc',
      icon: LucideIcons.cupSoda,
      color: Color(0xFF146A65),
      standards: [
        'Trái cây tươi (Chanh tươi, Chanh đào, Quýt hoàng kim, Xoài, Đào) phải được sơ chế và dán tem giờ cắt đầu mỗi ca.',
        'Định lượng đường và đá tuân thủ đúng công thức 100% / 70% / 50% / 30% theo phiếu in nhiệt từ POS Trạm BLAO.',
        'Sữa chua (Yaourt) và Bánh Flan vỏ chanh luôn bảo quản ở ngăn mát 2°C – 5°C, kiểm tra bề mặt mịn trước khi xuất quầy.',
        'Thạch dừa và topping phải được thay nước đường bảo quản mỗi ngày và đậy nắp kín sau mỗi lần múc.',
      ],
    ),
    BlaoSopSectionData(
      stationName: '3. Tác Phong Ca Trực & Chấm Công Trạm BLAO',
      badgeText: 'Nội quy nhân sự',
      icon: LucideIcons.shieldCheck,
      color: Color(0xFF143A2F),
      standards: [
        'Nhân viên có mặt trước giờ vào ca 10 phút, mặc đầy đủ đồng phục, tạp dề và mũ/khẩu trang vệ sinh thực phẩm.',
        'Thực hiện Chấm vào ca trên ứng dụng Chấm Công Trạm BLAO khi đã kết nối WiFi nội bộ hoặc đứng trong phạm vi GPS cửa hàng.',
        'Hoàn thành đầy đủ các nhiệm vụ giao việc trong ca (chụp ảnh thực tế tại quầy) trước khi bấm Chấm ra ca.',
        'Bàn giao số lượng phôi bánh, cốt trà tồn cuối ca rõ ràng cho ca kế tiếp.',
      ],
    ),
  ];

  static const List<String> _defaultChecklistItems = [
    'Kiểm tra nhiệt độ lò Bánh Lăn Nướng đạt chuẩn 185°C – 190°C',
    'Ủ mẻ cốt Trà Ô Long Blao đầu ca & dán nhãn thời gian',
    'Kiểm tra độ tươi nguyên liệu trái cây (Chanh, Xoài, Quýt, Đào)',
    'Kiểm tra tủ mát bảo quản Sữa chua, Bánh Flan & Phô mai (2°C – 6°C)',
    'Vệ sinh bề mặt khuôn nướng, kẹp gắp bánh & quầy pha chế',
    'Kiểm tra số lượng túi giấy Kraft, ly nắp & ống hút Trạm BLAO',
    'Chỉnh tề đồng phục, tạp dề, mũ trùm tóc trước khi đón khách',
    'Đồng bộ nhiệm vụ giao việc trong ca trên ứng dụng Chấm Công',
  ];

  final Map<String, int> _remainingSeconds = {};
  final Set<String> _runningTimers = {};
  final Set<int> _checkedIndices = {0, 1, 6};
  Map<String, dynamic>? _deviceTelemetry;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    for (final p in _presets) {
      _remainingSeconds[p.id] = p.durationSeconds;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _loadStationTelemetry();
  }

  Future<void> _loadStationTelemetry() async {
    try {
      final res = await _telemetryChannel
          .invokeMapMethod<String, dynamic>('getStationDeviceSnapshot');
      if (mounted && res != null) {
        setState(() => _deviceTelemetry = res);
      }
    } catch (_) {
      // Fallback on platforms or tests without native channel
    }
  }

  void _onTick() {
    if (_runningTimers.isEmpty) return;
    final completed = <BlaoBatchTimerPreset>[];
    setState(() {
      for (final p in _presets) {
        if (_runningTimers.contains(p.id)) {
          final current = _remainingSeconds[p.id] ?? p.durationSeconds;
          if (current > 1) {
            _remainingSeconds[p.id] = current - 1;
          } else {
            _remainingSeconds[p.id] = 0;
            _runningTimers.remove(p.id);
            completed.add(p);
          }
        }
      }
    });
    for (final donePreset in completed) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryDark,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(LucideIcons.bellRing, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Đã hoàn tất thời gian: ${donePreset.title}!',
                    style: const TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  void _toggleTimer(BlaoBatchTimerPreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_runningTimers.contains(preset.id)) {
        _runningTimers.remove(preset.id);
      } else {
        if ((_remainingSeconds[preset.id] ?? 0) <= 0) {
          _remainingSeconds[preset.id] = preset.durationSeconds;
        }
        _runningTimers.add(preset.id);
      }
    });
  }

  void _resetTimer(BlaoBatchTimerPreset preset) {
    HapticFeedback.lightImpact();
    setState(() {
      _runningTimers.remove(preset.id);
      _remainingSeconds[preset.id] = preset.durationSeconds;
    });
  }

  String _formatMinSec(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sổ Tay & Hẹn Giờ Quầy BLAO',
              style: TextStyle(
                fontFamily: 'BeVietnamPro',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Text(
              'Trạm trà Ô Long • Trạm Bánh Lăn Nướng',
              style: TextStyle(
                fontFamily: 'BeVietnamPro',
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontFamily: 'BeVietnamPro',
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(icon: Icon(LucideIcons.timer, size: 18), text: 'Hẹn giờ mẻ'),
            Tab(icon: Icon(LucideIcons.bookOpenCheck, size: 18), text: 'Chuẩn quầy'),
            Tab(icon: Icon(LucideIcons.clipboardCheck, size: 18), text: 'Tự kiểm tra'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTimersTab(),
          _buildSopStandardsTab(),
          _buildSelfChecklistTab(),
        ],
      ),
    );
  }

  Widget _buildTimersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF143A2F), Color(0xFF1E5645)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.flameKindling, color: AppColors.primary, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bộ Đếm Giờ Chuyên Dụng Trạm BLAO',
                      style: TextStyle(
                        fontFamily: 'BeVietnamPro',
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Đồng bộ thời gian nướng Bánh Lăn và ủ cốt Trà Ô Long chuẩn vị cao nguyên Bảo Lộc ngay trong ca trực.',
                      style: TextStyle(
                        fontFamily: 'BeVietnamPro',
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ..._presets.map((preset) {
          final remaining = _remainingSeconds[preset.id] ?? preset.durationSeconds;
          final isRunning = _runningTimers.contains(preset.id);
          final progress = 1.0 - (remaining / preset.durationSeconds).clamp(0.0, 1.0);

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isRunning ? preset.accentColor : AppColors.border,
                width: isRunning ? 2 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: preset.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(preset.icon, color: preset.accentColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: preset.accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  preset.station,
                                  style: TextStyle(
                                    fontFamily: 'BeVietnamPro',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: preset.accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                preset.tempSpec,
                                style: const TextStyle(
                                  fontFamily: 'BeVietnamPro',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            preset.title,
                            style: const TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.neutral,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatMinSec(remaining),
                      style: TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isRunning ? preset.accentColor : AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  preset.guideline,
                  style: const TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFEDEAE2),
                    valueColor: AlwaysStoppedAnimation<Color>(preset.accentColor),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _toggleTimer(preset),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isRunning ? const Color(0xFFD97706) : AppColors.primaryDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Icon(
                          isRunning ? LucideIcons.pause : LucideIcons.play,
                          size: 16,
                        ),
                        label: Text(
                          isRunning ? 'Tạm dừng' : 'Bắt đầu bấm giờ',
                          style: const TextStyle(
                            fontFamily: 'BeVietnamPro',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _resetTimer(preset),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryDark,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(LucideIcons.rotateCcw, size: 15),
                      label: const Text(
                        'Đặt lại',
                        style: TextStyle(
                          fontFamily: 'BeVietnamPro',
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSopStandardsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        ..._sopSections.map((section) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: section.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(section.icon, color: section.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: section.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              section.badgeText,
                              style: TextStyle(
                                fontFamily: 'BeVietnamPro',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: section.color,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            section.stationName,
                            style: const TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.neutral,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...section.standards.map((line) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(
                            LucideIcons.circleCheck,
                            size: 16,
                            color: section.color,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        if (_deviceTelemetry != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF143A2F),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.cpu, color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Thiết bị trạm: ${_deviceTelemetry!['deviceModel']} (${_deviceTelemetry!['systemName']} ${_deviceTelemetry!['systemVersion']}) • Múi giờ: ${_deviceTelemetry!['timeZoneId']}',
                    style: const TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSelfChecklistTab() {
    final doneCount = _checkedIndices.length;
    final total = _defaultChecklistItems.length;
    final ratio = total > 0 ? doneCount / total : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.cardOutline, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tiến độ sẵn sàng mở quầy BLAO',
                    style: TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.neutral,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$doneCount/$total hạng mục',
                      style: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 9,
                  backgroundColor: const Color(0xFFEDEAE2),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...List.generate(_defaultChecklistItems.length, (index) {
          final isChecked = _checkedIndices.contains(index);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isChecked ? AppColors.success : AppColors.border,
              ),
            ),
            child: CheckboxListTile(
              value: isChecked,
              activeColor: AppColors.success,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                setState(() {
                  if (val == true) {
                    _checkedIndices.add(index);
                  } else {
                    _checkedIndices.remove(index);
                  }
                });
              },
              title: Text(
                _defaultChecklistItems[index],
                style: TextStyle(
                  fontFamily: 'BeVietnamPro',
                  fontSize: 13.5,
                  fontWeight: isChecked ? FontWeight.w700 : FontWeight.w500,
                  color: isChecked ? AppColors.primaryDark : AppColors.neutral,
                  decoration: isChecked ? TextDecoration.lineThrough : null,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          );
        }),
      ],
    );
  }
}
