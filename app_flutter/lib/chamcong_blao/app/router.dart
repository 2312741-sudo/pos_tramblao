import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/welcome_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/profile_setup_screen.dart';
import '../features/store/screens/create_store_screen.dart';
import '../features/store/screens/join_store_screen.dart';
import '../features/store/screens/join_qr_screen.dart';
import '../features/store/screens/pending_approval_screen.dart';
import '../features/store/screens/store_settings_screen.dart';
import '../features/store/screens/shift_settings_screen.dart';
import '../features/store/screens/qr_display_screen.dart';
import '../features/production/screens/production_tasks_screen.dart';
import '../features/attendance/screens/check_in_screen.dart';
import '../features/attendance/screens/active_staff_screen.dart';
import '../features/attendance/screens/attendance_history_screen.dart';
import '../features/attendance/screens/attendance_table_screen.dart';
import '../features/attendance/screens/monthly_attendance_screen.dart';
import '../features/schedule/screens/schedule_register_screen.dart';
import '../features/schedule/screens/schedule_manager_screen.dart';
import '../features/salary/screens/salary_detail_screen.dart';
import '../features/salary/screens/salary_overview_screen.dart';
import '../features/salary/screens/manage_advances_screen.dart';
import '../features/members/screens/members_list_screen.dart';
import '../features/members/screens/member_detail_screen.dart';
import '../features/members/screens/pending_members_screen.dart';
import '../features/auth/screens/profile_settings_screen.dart';
import '../features/auth/screens/about_app_screen.dart';
import '../features/notifications/screens/notifications_screen.dart';
import '../features/dashboard/owner_dashboard.dart';
import '../features/dashboard/manager_dashboard.dart';
import '../features/dashboard/employee_dashboard.dart';
import '../features/task_assignment/screens/task_report_screen.dart';
import '../features/task_assignment/screens/task_management_screen.dart';
import '../features/task_assignment/screens/task_detail_screen.dart';
import '../features/blao_station/blao_station_sop_screen.dart';
import '../models/task_assignment_model.dart';
import '../models/member_model.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../cc_firebase.dart';

// Route path constants
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String profileSetup = '/profile-setup';

  static const String createStore = '/create-store';
  static const String joinStore = '/join-store';
  static const String joinStoreQr = '/join-qr';
  static const String pendingApproval = '/pending-approval';

  static const String ownerDashboard = '/owner-dashboard';
  static const String managerDashboard = '/manager-dashboard';
  static const String employeeDashboard = '/employee-dashboard';

  static const String checkIn = '/check-in';
  static const String activeStaff = '/active-staff';
  static const String attendanceHistory = '/attendance-history';
  static const String attendanceTable = '/attendance-table';
  static const String monthlyAttendance = '/monthly-attendance';

  static const String scheduleRegister = '/schedule';
  static const String scheduleManager = '/schedule-manager';
  static const String salary = '/salary';
  static const String salaryOverview = '/salary-overview';
  static const String manageAdvances = '/manage-advances';
  static const String members = '/members';
  static const String memberDetail = '/member-detail';
  static const String pendingMembers = '/pending-members';
  static const String storeSettings = '/store-settings';
  static const String shiftSettings = '/shift-settings';
  static const String qrDisplay = '/qr-display';
  static const String profileSettings = '/profile-settings';
  static const String aboutApp = '/about-app';
  static const String notifications = '/notifications';
  static const String productionTasks = '/production-tasks';
  static const String taskReport = '/task-report';
  static const String taskManagement = '/task-management';
  static const String taskDetail = '/task-detail';
  static const String blaoStationSop = '/blao-station-sop';
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
          (dynamic _) => notifyListeners(),
        );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: GoRouterRefreshStream(CcFirebase.auth.authStateChanges()),
    redirect: (BuildContext context, GoRouterState state) {
      final currentUser = CcFirebase.auth.currentUser;
      final isAuthenticated = currentUser != null;
      final currentPath = state.matchedLocation;

      // Allow splash to handle its own redirect
      if (currentPath == AppRoutes.splash) return null;

      // Public screens (unauthenticated)
      final publicScreens = [
        AppRoutes.blaoStationSop,
      ];
      final isOnPublicScreen = publicScreens.contains(currentPath);

      // Các màn hình Auth/onboarding độc lập không dùng khi nhúng trong POS
      final embeddedBlockedScreens = [
        AppRoutes.welcome,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.profileSetup,
        AppRoutes.createStore,
        AppRoutes.joinStore,
      ];

      if (!isAuthenticated && !isOnPublicScreen) {
        return AppRoutes.splash;
      }

      if (embeddedBlockedScreens.contains(currentPath)) {
        return AppRoutes.splash;
      }

      return null;
    },
    routes: [
      // ── Splash ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // ── Auth Flow ─────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.welcome,
        name: 'welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        name: 'profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),

      // ── Store Setup ───────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.createStore,
        name: 'create-store',
        builder: (context, state) => const CreateStoreScreen(),
      ),
      GoRoute(
        path: AppRoutes.joinStore,
        name: 'join-store',
        builder: (context, state) => const JoinStoreScreen(),
      ),
      GoRoute(
        path: AppRoutes.joinStoreQr,
        name: 'join-qr',
        builder: (context, state) => const JoinQrScreen(),
      ),
      GoRoute(
        path: AppRoutes.pendingApproval,
        name: 'pending-approval',
        builder: (context, state) => const PendingApprovalScreen(),
      ),

      // ── Dashboards ────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.ownerDashboard,
        name: 'owner-dashboard',
        builder: (context, state) => const OwnerDashboard(),
      ),
      GoRoute(
        path: AppRoutes.managerDashboard,
        name: 'manager-dashboard',
        builder: (context, state) => const ManagerDashboard(),
      ),
      GoRoute(
        path: AppRoutes.employeeDashboard,
        name: 'employee-dashboard',
        builder: (context, state) => const EmployeeDashboard(),
      ),

      // ── Attendance ────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.checkIn,
        name: 'check-in',
        builder: (context, state) => const CheckInScreen(),
      ),
      GoRoute(
        path: AppRoutes.activeStaff,
        name: 'active-staff',
        builder: (context, state) => const ActiveStaffScreen(),
      ),
      GoRoute(
        path: AppRoutes.attendanceHistory,
        name: 'attendance-history',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final userId = extra?['userId'] as String? ?? state.uri.queryParameters['userId'];
          final month = extra?['month'] as String? ?? state.uri.queryParameters['month'];
          return AttendanceHistoryScreen(userId: userId, month: month);
        },
      ),
      GoRoute(
        path: AppRoutes.attendanceTable,
        name: 'attendance-table',
        builder: (context, state) => const AttendanceTableScreen(),
      ),
      GoRoute(
        path: AppRoutes.monthlyAttendance,
        name: 'monthly-attendance',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final memberId = extra?['memberId'] as String? ?? '';
          final memberName = extra?['memberName'] as String? ?? '';
          return MonthlyAttendanceScreen(
              memberId: memberId, memberName: memberName);
        },
      ),

      // ── Schedule ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.scheduleRegister,
        name: 'schedule',
        builder: (context, state) => ScheduleRegisterScreen(
          initialWeekStart: (state.extra as Map<String, dynamic>?)?['weekStart'] as String?),
      ),
      GoRoute(
        path: AppRoutes.scheduleManager,
        name: 'schedule-manager',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final initialWeekIndex = extra?['initialWeekIndex'] as int? ?? 0;
          final weekStart = extra?['weekStart'] as String?;
          return ScheduleManagerScreen(
            initialWeekIndex: initialWeekIndex,
            initialWeekStart: weekStart,
          );
        },
      ),

      // ── Salary ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.salary,
        name: 'salary',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final userId = extra?['userId'] as String? ?? state.uri.queryParameters['userId'];
          final memberName = extra?['memberName'] as String? ?? state.uri.queryParameters['memberName'];
          return SalaryDetailScreen(userId: userId, memberName: memberName);
        },
      ),
      GoRoute(
        path: AppRoutes.salaryOverview,
        name: 'salary-overview',
        builder: (context, state) => const SalaryOverviewScreen(),
      ),
      GoRoute(
        path: AppRoutes.manageAdvances,
        name: 'manage-advances',
        builder: (context, state) => const ManageAdvancesScreen(),
      ),

      // ── Members ───────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.members,
        name: 'members',
        builder: (context, state) => const MembersListScreen(),
      ),
      GoRoute(
        path: AppRoutes.memberDetail,
        name: 'member-detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final userId = extra?['userId'] as String? ?? '';
          return MemberDetailScreen(userId: userId);
        },
      ),
      GoRoute(
        path: AppRoutes.pendingMembers,
        name: 'pending-members',
        builder: (context, state) => const PendingMembersScreen(),
      ),

      // ── Store Settings ────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.storeSettings,
        name: 'store-settings',
        builder: (context, state) => const StoreSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.shiftSettings,
        name: 'shift-settings',
        builder: (context, state) => const ShiftSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.productionTasks,
        name: 'production-tasks',
        builder: (context, state) => const ProductionTasksScreen(),
      ),
      GoRoute(
        path: AppRoutes.qrDisplay,
        name: 'qr-display',
        builder: (context, state) => const QrDisplayScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileSettings,
        name: 'profile-settings',
        builder: (context, state) => const ProfileSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.aboutApp,
        name: 'about-app',
        builder: (context, state) => const AboutAppScreen(),
      ),
      GoRoute(
        path: AppRoutes.blaoStationSop,
        name: 'blao-station-sop',
        builder: (context, state) => const BlaoStationSopScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.taskReport,
        name: 'task-report',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final task = extra?['task'] as AssignedTask?;
          if (task == null) {
            return const Scaffold(
              body: Center(child: Text('Không tìm thấy thông tin công việc')),
            );
          }
          final workDate = extra?['workDate'] as String?;
          final initialSubmission = extra?['initialSubmission'] as TaskSubmission?;
          return TaskReportScreen(
            task: task,
            workDate: workDate,
            initialSubmission: initialSubmission,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.taskManagement,
        name: 'task-management',
        builder: (context, state) => const TaskManagementScreen(),
      ),
      GoRoute(
        path: AppRoutes.taskDetail,
        name: 'task-detail',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is AssignedTask) {
            return TaskDetailScreen(task: extra);
          }
          final params = state.uri.queryParameters;
          final taskId = params['taskId'];
          final storeId = params['storeId'];
          return TaskDetailScreen(taskId: taskId, storeId: storeId);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: const Color(0xFFF8F4EE),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.circleAlert, size: 64, color: Color(0xFFC8102E)),
            const SizedBox(height: 16),
            Text(
              'Không tìm thấy trang',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.error?.message ?? 'Đường dẫn không hợp lệ',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.splash),
              child: const Text('Về trang chủ'),
            ),
          ],
        ),
      ),
    ),
  );
});

// Helper extension for role-based navigation
extension RoleNavigation on BuildContext {
  void navigateToDashboard(UserRole role) {
    switch (role) {
      case UserRole.owner:
        go(AppRoutes.ownerDashboard);
      case UserRole.manager1:
      case UserRole.manager2:
      case UserRole.legacyManager:
        go(AppRoutes.managerDashboard);
      case UserRole.employee:
        go(AppRoutes.employeeDashboard);
    }
  }
}
