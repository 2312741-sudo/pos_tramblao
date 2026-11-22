import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/store_provider.dart';
import '../providers/user_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class JoinQrScreen extends ConsumerStatefulWidget {
  const JoinQrScreen({super.key});

  @override
  ConsumerState<JoinQrScreen> createState() => _JoinQrScreenState();
}

class _JoinQrScreenState extends ConsumerState<JoinQrScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _processCode(String code) async {
    if (_isProcessing || _hasScanned) return;
    setState(() {
      _isProcessing = true;
      _hasScanned = true;
    });

    await _controller?.stop();

    try {
      final cleanCode = code.trim().toUpperCase();
      final repo = ref.read(storeRepositoryProvider);
      final userRepo = ref.read(userRepositoryProvider);
      final user = ref.read(userProvider).value;
      if (user == null) throw Exception('Chưa đăng nhập');

      final store = await repo.findStoreByCode(cleanCode);
      if (store == null) {
        _showError('Mã QR không hợp lệ hoặc cửa hàng không tồn tại');
        setState(() {
          _isProcessing = false;
          _hasScanned = false;
        });
        await _controller?.start();
        return;
      }

      await repo.joinStore(store.id, user.id);
      await userRepo.updateCurrentStoreId(user.id, store.id);
      
      ref.invalidate(userStoresProvider);

      if (mounted) context.go('/pending-approval');
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
      setState(() {
        _isProcessing = false;
        _hasScanned = false;
      });
      await _controller?.start();
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        title: const Text(
          'Quét mã QR',
          style: TextStyle(
            fontFamily: 'BeVietnamPro',
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.zap),
            onPressed: () => _controller?.toggleTorch(),
            tooltip: 'Đèn flash',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera
          MobileScanner(
            controller: _controller!,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _processCode(raw);
                  break;
                }
              }
            },
          ),

          // Overlay
          _ScanOverlay(),

          // Instructions
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_isProcessing)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  const Icon(
                    LucideIcons.scanQrCode,
                    color: Colors.white54,
                    size: 32,
                  ),
                const SizedBox(height: 16),
                Text(
                  _isProcessing
                      ? 'Đang xử lý...'
                      : 'Hướng camera vào mã QR cửa hàng',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'BeVietnamPro',
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Mã QR sẽ được tự động nhận dạng',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cutoutSize = size.width * 0.7;
    final cutoutTop = (size.height - cutoutSize) / 2 - 60;

    return Stack(
      children: [
        // Semi-transparent overlay
        Positioned.fill(
          child: CustomPaint(
            painter: _OverlayPainter(
              cutoutRect: Rect.fromCenter(
                center: Offset(size.width / 2, cutoutTop + cutoutSize / 2),
                width: cutoutSize,
                height: cutoutSize,
              ),
            ),
          ),
        ),
        // Corner decorations
        Positioned(
          top: cutoutTop,
          left: (size.width - cutoutSize) / 2,
          child: _CornerFrame(size: cutoutSize),
        ),
      ],
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Rect cutoutRect;
  _OverlayPainter({required this.cutoutRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.6);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CornerFrame extends StatelessWidget {
  final double size;
  const _CornerFrame({required this.size});

  @override
  Widget build(BuildContext context) {
    const cornerLen = 24.0;
    const cornerThick = 3.0;
    const cornerColor = AppColors.accent;

    return SizedBox(
      width: size,
      height: size,
      child: const Stack(
        children: [
          // Top-left
          Positioned(
            top: 0,
            left: 0,
            child: _Corner(
                horizontal: true,
                vertical: true,
                len: cornerLen,
                thick: cornerThick,
                color: cornerColor),
          ),
          // Top-right
          Positioned(
            top: 0,
            right: 0,
            child: _Corner(
                horizontal: false,
                vertical: true,
                len: cornerLen,
                thick: cornerThick,
                color: cornerColor),
          ),
          // Bottom-left
          Positioned(
            bottom: 0,
            left: 0,
            child: _Corner(
                horizontal: true,
                vertical: false,
                len: cornerLen,
                thick: cornerThick,
                color: cornerColor),
          ),
          // Bottom-right
          Positioned(
            bottom: 0,
            right: 0,
            child: _Corner(
                horizontal: false,
                vertical: false,
                len: cornerLen,
                thick: cornerThick,
                color: cornerColor),
          ),
        ],
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final bool horizontal;
  final bool vertical;
  final double len;
  final double thick;
  final Color color;

  const _Corner({
    required this.horizontal,
    required this.vertical,
    required this.len,
    required this.thick,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: len,
      height: len,
      child: Stack(
        children: [
          Positioned(
            top: vertical ? 0 : null,
            bottom: vertical ? null : 0,
            left: horizontal ? 0 : null,
            right: horizontal ? null : 0,
            child: Container(
              width: len,
              height: thick,
              color: color,
            ),
          ),
          Positioned(
            top: vertical ? 0 : null,
            bottom: vertical ? null : 0,
            left: horizontal ? 0 : null,
            right: horizontal ? null : 0,
            child: Container(
              width: thick,
              height: len,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
