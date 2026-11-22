import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

class ChamCongTramApp extends ConsumerWidget {
  const ChamCongTramApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Chấm Công Trạm BLAO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.tramTheme,
      routerConfig: router,
      locale: const Locale('vi', 'VN'),
      supportedLocales: const [
        Locale('vi', 'VN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Tự động ẩn bàn phím trên toàn bộ ứng dụng khi chạm ra ngoài hoặc cuộn màn hình
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              if (notification.dragDetails != null) {
                FocusManager.instance.primaryFocus?.unfocus();
              }
              return false;
            },
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
