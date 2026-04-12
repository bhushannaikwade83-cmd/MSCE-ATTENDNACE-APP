import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'config/supabase_env.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'services/locale_service.dart';

// Import your screens...
import 'services/session_manager.dart';
import 'services/theme_service.dart';
import 'presentation/widgets/session_monitor.dart';
import 'presentation/screens/splash_screen.dart';
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
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/main_navigation_screen.dart';
import 'presentation/screens/help_desk_screen.dart';
import 'presentation/screens/biometric_lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('⚠️ Could not load .env: $e');
  }

  await SupabaseEnv.initializeRequired();

  SessionManager.initialize();

  // MobileFaceNet (flutter_litert) is not initialized on iOS/web in FaceRecognitionService
  // (avoids EXC_BAD_ACCESS in DartWorker). Neural matching: use Android.
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
                  title: 'MSCE Attendance App',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: themeService.themeMode,
                  locale: localeService.locale,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  initialRoute: SplashScreen.routeName,
                  routes: {
                    SplashScreen.routeName: (_) => const SplashScreen(),
                    SetupScreen.routeName: (_) => const SetupScreen(),
                    LoginScreen.routeName: (_) => const LoginScreen(),
                    InstituteSearchScreen.routeName: (_) =>
                        const InstituteSearchScreen(),
                    AdminHomeScreen.routeName: (_) => const AdminHomeScreen(),
                    AdminAttendanceScreen.routeName: (_) =>
                        const AdminAttendanceScreen(),
                    AddStudentScreen.routeName: (_) => const AddStudentScreen(),
                    StudentManagementScreen.routeName: (_) =>
                        const StudentManagementScreen(),
                    GpsSettingsScreen.routeName: (_) =>
                        const GpsSettingsScreen(),
                    AttendanceReportsScreen.routeName: (_) =>
                        const AttendanceReportsScreen(),
                    CoderLoginScreen.routeName: (_) => const CoderLoginScreen(),
                    CoderDashboardScreen.routeName: (_) =>
                        const CoderDashboardScreen(),
                    SuperAdminInstituteScreen.routeName: (_) =>
                        const SuperAdminInstituteScreen(),
                    OnboardingScreen.routeName: (_) => const OnboardingScreen(),
                    MainNavigationScreen.routeName: (_) =>
                        const MainNavigationScreen(),
                    HelpDeskScreen.routeName: (_) => const HelpDeskScreen(),
                    BiometricLockScreen.routeName: (_) =>
                        const BiometricLockScreen(),
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
