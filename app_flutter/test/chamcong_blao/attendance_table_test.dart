import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tram_flutter/chamcong_blao/features/attendance/screens/attendance_table_screen.dart';

void main() {
  testWidgets('AttendanceTableScreen check widgets', (WidgetTester tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      print('FLUTTER ERROR: ${details.exception}');
    };
    
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AttendanceTableScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    
    final appbars = find.byType(AppBar);
    print('AppBars found: ${appbars.evaluate().length}');
    
    final columns = find.byType(Column);
    print('Columns found: ${columns.evaluate().length}');
    
    final containers = find.byType(Container);
    print('Containers found: ${containers.evaluate().length}');
    
    // Dump tree
    debugDumpApp();
  });
}
