import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/share_utils.dart';
import '../providers/store_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class QrDisplayScreen extends ConsumerWidget {
  const QrDisplayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(currentStoreProvider);

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
          'Mã QR cửa hàng',
          style: TextStyle(
              fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700),
        ),
      ),
      body: storeAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (store) {
          if (store == null) {
            return const Center(
                child: Text('Không tìm thấy cửa hàng'));
          }
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),

                  // Store name
                  Text(
                    store.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'BeVietnamPro',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.neutral,
                    ),
                  ),
                  if (store.address != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      store.address!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'BeVietnamPro',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),

                  // QR Code card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        QrImageView(
                          data: store.code,
                          size: MediaQuery.of(context).size.width * 0.6,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppColors.neutral,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppColors.neutral,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Code display
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            store.code,
                            style: const TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                              color: AppColors.neutral,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Instructions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.info.withOpacity(0.2)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.info,
                            color: AppColors.info, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Cho nhân viên quét mã này để tham gia cửa hàng. Mỗi nhân viên sẽ cần được bạn duyệt trước khi có thể chấm công.',
                            style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 13,
                              color: AppColors.info,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: store.code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đã sao chép mã'),
                                backgroundColor: AppColors.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.copy, size: 18),
                          label: const Text('Sao chép mã'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.neutral,
                            side:
                                const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontFamily: 'BeVietnamPro',
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ShareUtils.shareText(
                              'Tham gia cửa hàng "${store.name}" với mã: ${store.code}\n\nTải ứng dụng Chấm Công Trạm BLAO để tham gia!',
                              subject: 'Mời tham gia ${store.name}',
                              context: context,
                            );
                          },
                          icon: const Icon(LucideIcons.share2, size: 18),
                          label: const Text('Chia sẻ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontFamily: 'BeVietnamPro',
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
