import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../store/providers/store_provider.dart';
import 'schedule_manager_screen.dart';
import 'schedule_palette.dart';
import 'schedule_register_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class EmployeeScheduleTab extends ConsumerStatefulWidget {
  const EmployeeScheduleTab({super.key});

  @override
  ConsumerState<EmployeeScheduleTab> createState() =>
      _EmployeeScheduleTabState();
}

class _EmployeeScheduleTabState extends ConsumerState<EmployeeScheduleTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SchedulePalette.forRole(ref.watch(currentMemberProvider)?.role);
    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        // Theme chung đặt màu chữ/icon AppBar cố định → phải ghi rõ để nền màu dùng chữ trắng
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        title: Text(
          'Lịch làm việc',
          style: GoogleFonts.merriweather(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: palette.accent,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white,
              labelStyle: GoogleFonts.beVietnamPro(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              unselectedLabelStyle: GoogleFonts.beVietnamPro(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              tabs: const [
                Tab(
                  icon: Icon(LucideIcons.calendarCog, size: 18),
                  text: 'Đăng ký lịch làm',
                ),
                Tab(
                  icon: Icon(LucideIcons.store, size: 18),
                  text: 'Lịch cửa hàng',
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ScheduleRegisterScreen(showAppBar: false),
          ScheduleManagerScreen(showAppBar: false),
        ],
      ),
    );
  }
}
