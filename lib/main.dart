import 'package:flutter/material.dart';
import 'core/root_navigator.dart';
import 'core/theme/app_theme.dart';
import 'config/apply_network_overrides_stub.dart'
    if (dart.library.io) 'config/apply_network_overrides_io.dart';
import 'config/supabase_env.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'services/locale_service.dart';
import 'core/utils/responsive.dart';

// Import your screens...
import 'services/session_manager.dart';
import 'services/theme_service.dart';
import 'presentation/widgets/session_monitor.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/app_permissions_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/setup_screen.dart';
import 'presentation/screens/admin_home_screen.dart';
import 'presentation/screens/admin_attendance_screen.dart';
import 'presentation/screens/add_student_screen.dart';
import 'presentation/screens/student_management_screen.dart';
import 'presentation/screens/gps_settings_screen.dart';
import 'presentation/screens/attendance_reports_screen.dart';
import 'presentation/screens/institute_search_screen.dart';
import 'presentation/screens/coder_login_screen.dart';
import 'presentation/screens/coder_dashboard_screen.dart';
import 'presentation/screens/super_admin_institute_screen.dart';
import 'presentation/screens/institute_admin_registration_screen.dart';
import 'presentation/screens/institute_location_gate_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/main_navigation_screen.dart';
import 'presentation/screens/staff_attendance_portal_screen.dart';
import 'presentation/screens/attendance_staff_login_screen.dart';
import 'presentation/screens/help_desk_screen.dart';
import 'presentation/screens/biometric_lock_screen.dart';
import 'presentation/screens/security_dashboard_screen.dart';
import 'services/face_recognition_service.dart';
import 'services/institute_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wi‑Fi: prefer IPv4 + skip auto-proxy before any cloud calls (REST, auth, Realtime WS).
  applySupabaseNetworkOverrides();

  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('⚠️ Could not load .env: $e');
  }

  await SupabaseEnv.initializeRequired();

  SessionManager.initialize();

  // Warm up TFLite on startup so failures (missing asset, device GPU) show once — not only after submit.
  // Face still needs internet to *save* embedding to Supabase when you add a student.
  try {
    await FaceRecognitionService.initialize();
  } catch (e, st) {
    debugPrint('⚠️ Face model (MobileFaceNet) failed to load: $e');
    debugPrint('$st');
  }

  try {
    await InstituteNotificationService.initialize();
  } catch (e, st) {
    debugPrint('⚠️ Local notifications failed to initialize: $e');
    debugPrint('$st');
  }

  runApp(const SmartAttendanceApp());
}

class SmartAttendanceApp extends StatelessWidget {
  const SmartAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => LocaleService()),
      ],
      child: Consumer2<ThemeService, LocaleService>(
        builder: (context, themeService, localeService, _) {
          return ScreenUtilInit(
            designSize: const Size(375, 812),
            minTextAdapt: true,
            splitScreenMode: true,
            builder: (_, child) {
              return SessionMonitor(
                child: MaterialApp(
                  navigatorKey: rootNavigatorKey,
                  title: 'MSCE Attendance App',
                  debugShowCheckedModeBanner: false,
                  builder: (context, child) {
                    final mediaQuery = MediaQuery.of(context);
                    return MediaQuery(
                      data: mediaQuery.copyWith(
                        textScaler: Responsive.appTextScaler(context),
                      ),
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: themeService.themeMode,
                  locale: localeService.locale,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  initialRoute: SplashScreen.routeName,
                  routes: {
                    SplashScreen.routeName: (_) => const SplashScreen(),
                    AppPermissionsScreen.routeName: (_) =>
                        const AppPermissionsScreen(),
                    SetupScreen.routeName: (_) => const SetupScreen(),
                    // Government / IRCTC-style login only (captcha, OTP, PIN). No glass "modern" login route.
                    LoginScreen.routeName: (_) => const LoginScreen(),
                    InstituteSearchScreen.routeName: (_) =>
                        const InstituteSearchScreen(),
                    AdminHomeScreen.routeName: (_) => const AdminHomeScreen(),
                    AdminAttendanceScreen.routeName: (_) =>
                        const AdminAttendanceScreen(),
                    AddStudentScreen.routeName: (_) => const AddStudentScreen(),
                    StudentManagementScreen.routeName: (_) =>
                        const StudentManagementScreen(),
                    GpsSettingsScreen.routeName: (context) {
                      final args = ModalRoute.of(context)?.settings.arguments;
                      final routeArgs = args is Map ? args : const {};
                      return GpsSettingsScreen(
                        isMandatory: routeArgs['mandatory'] == true,
                        fromLogin: routeArgs['fromLogin'] == true,
                      );
                    },
                    AttendanceReportsScreen.routeName: (_) =>
                        const AttendanceReportsScreen(),
                    CoderLoginScreen.routeName: (_) => const CoderLoginScreen(),
                    CoderDashboardScreen.routeName: (_) =>
                        const CoderDashboardScreen(),
                    SuperAdminInstituteScreen.routeName: (_) =>
                        const SuperAdminInstituteScreen(),
                    InstituteAdminRegistrationScreen.routeName: (_) =>
                        const InstituteAdminRegistrationScreen(),
                    OnboardingScreen.routeName: (_) => const OnboardingScreen(),
                    InstituteLocationGateScreen.routeName: (context) {
                      final args = ModalRoute.of(context)?.settings.arguments;
                      return InstituteLocationGateScreen.fromArgs(args);
                    },
                    MainNavigationScreen.routeName: (_) =>
                        const MainNavigationScreen(),
                    StaffAttendancePortalScreen.routeName: (_) =>
                        const StaffAttendancePortalScreen(),
                    AttendanceStaffLoginScreen.routeName: (_) =>
                        const AttendanceStaffLoginScreen(),
                    HelpDeskScreen.routeName: (_) => const HelpDeskScreen(),
                    BiometricLockScreen.routeName: (_) =>
                        const BiometricLockScreen(),
                    SecurityDashboardScreen.routeName: (_) =>
                        const SecurityDashboardScreen(),
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
