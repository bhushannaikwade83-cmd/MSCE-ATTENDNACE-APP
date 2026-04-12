import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../services/auth_service.dart';
import '../../services/offline_service.dart';
import '../../services/error_handler.dart';
import '../../services/theme_service.dart';
import '../../services/session_manager.dart';
import '../../core/theme/app_theme.dart';
import '../screens/login_screen.dart';
import 'batch_management_screen.dart';
import 'student_management_screen.dart';
import 'attendance_reports_screen.dart';
import 'attendance_calendar_screen.dart';
import 'attendance_trend_screen.dart';
import 'help_desk_screen.dart';
import '../widgets/quick_stats_widget.dart';
import '../../services/batch_service.dart';

class AdminHomeScreen extends StatefulWidget {
  static const routeName = '/admin-home';
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final BatchService _batchService = BatchService();
  String? _instituteId;
  bool _isLoadingInstitute = true;
  Map<String, dynamic>? _instituteTiming;
  
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  
  String get _todayDateId => DateTime.now().toString().split(' ')[0];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _loadInstituteId();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload timing when screen becomes visible again
    if (_instituteId != null && _instituteTiming == null) {
      _loadInstituteTiming(_instituteId!);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingInstitute = false);
        if (mounted) await _loadDashboardStats();
        return;
      }

      final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      final instituteId = row?['institute_id'] as String?;
      if (instituteId != null && instituteId.isNotEmpty) {
        setState(() {
          _instituteId = instituteId;
        });
        _loadInstituteTiming(instituteId);
      }
      setState(() => _isLoadingInstitute = false);
    } catch (e) {
      setState(() => _isLoadingInstitute = false);
      if (kDebugMode) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'loadInstituteId', appType: 'admin');
        debugPrint('Error loading institute: ${errorResult['error']}');
      }
    }
    if (mounted) await _loadDashboardStats();
  }

  Future<void> _loadInstituteTiming(String instituteId) async {
    try {
      final timing = await _batchService.getInstituteTiming(instituteId);
      if (mounted) {
        setState(() {
          _instituteTiming = timing;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading institute timing: $e');
      }
    }
  }

  // Dashboard counters – loaded once on init, refreshed only when user pulls-to-refresh.
  String? _profileName;
  int _studentCount = 0;
  int _todayAttendanceCount = 0;
  bool _statsLoading = true;

  Future<void> _loadDashboardStats() async {
    if (!mounted) return;
    setState(() => _statsLoading = true);
    try {
      final u = appDb.auth.currentUser;
      if (u == null) {
        if (mounted) {
          setState(() {
            _profileName = null;
            _studentCount = 0;
            _todayAttendanceCount = 0;
            _statsLoading = false;
          });
        }
        return;
      }

      final profileRow =
          await appDb.from('profiles').select('name').eq('id', u.id).maybeSingle();
      final name = profileRow?['name'] as String?;

      int sc = 0;
      int att = 0;
      final iid = _instituteId;
      if (iid != null && iid.isNotEmpty) {
        final studentRes = await appDb
            .from('students')
            .select('id')
            .eq('institute_id', iid)
            .count(CountOption.exact);
        sc = studentRes.count;

        final code = await instituteCodeForId(iid);
        final attRes = await appDb
            .from('attendance_in_out')
            .select('id')
            .eq('institute_code', code)
            .eq('attendance_date', _todayDateId)
            .count(CountOption.exact);
        att = attRes.count;
      }

      if (!mounted) return;
      setState(() {
        _profileName = name;
        _studentCount = sc;
        _todayAttendanceCount = att;
        _statsLoading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Dashboard stats error: $e');
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Prevent back button from exiting app - admin home is main screen
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
        body: SafeArea(
          top: false,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildProfileGovCard(isDark),
                            SizedBox(height: 16.h),
                            // Date and Clock Times
                            _buildDateAndClockTimes(isDark),
                            SizedBox(height: 20.h),
                            
                            // Institute Timing Card
                            if (_instituteTiming != null)
                              _buildInstituteTimingCard(isDark),
                            if (_instituteTiming != null)
                              SizedBox(height: 20.h),
                            
                            // Enhanced Quick Stats Widget (Today's Stats)
                            if (_instituteId != null)
                              QuickStatsWidget(
                                instituteId: _instituteId!,
                              ),
                            SizedBox(height: 20.h),
                            
                            // Quick Actions
                            _buildQuickActions(isDark),
                            SizedBox(height: 20.h),
                            
                            SizedBox(height: 24.h),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernAppBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.dashboard_rounded, color: Colors.white, size: 24.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  'Attendance Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: Responsive.fontSize(context, 20).sp,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              FutureBuilder<int>(
                future: OfflineService.getPendingCount(),
                builder: (context, snapshot) {
                  final pendingCount = snapshot.data ?? 0;
                  if (pendingCount > 0) {
                    return Stack(
                      children: [
                        IconButton(
                          icon: Icon(Icons.cloud_off, color: Colors.white, size: 24.sp),
                          onPressed: () async {
                            if (_instituteId != null) {
                              await OfflineService.syncPendingAttendance(_instituteId!);
                              setState(() {});
                            }
                          },
                          tooltip: '$pendingCount pending sync',
                        ),
                        Positioned(
                          right: 8.w,
                          top: 8.h,
                          child: Container(
                            padding: EdgeInsets.all(4.w),
                            decoration: const BoxDecoration(
                              color: AppTheme.accentRed,
                              shape: BoxShape.circle,
                            ),
                            constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.h),
                            child: Text(
                              '$pendingCount',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return SizedBox.shrink();
                },
              ),
              IconButton(
                icon: Icon(Icons.help_outline, color: Colors.white, size: 24.sp),
                onPressed: () {
                  Navigator.pushNamed(context, HelpDeskScreen.routeName);
                },
                tooltip: 'Help & Instructions',
              ),
              Consumer<ThemeService>(
                builder: (context, themeService, _) {
                  return IconButton(
                    icon: Icon(
                      themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                      color: Colors.white,
                      size: 24.sp,
                    ),
                    onPressed: () => themeService.toggleTheme(),
                    tooltip: themeService.isDarkMode ? 'Light Mode' : 'Dark Mode',
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.logout, color: Colors.white, size: 24.sp),
                onPressed: () async {
                  await SessionManager.signOut();
                  if (!mounted) return;
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    LoginScreen.routeName,
                    (route) => false,
                  );
                },
                tooltip: 'Logout',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(24.r),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5.w),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20.r,
                spreadRadius: 5.r,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Row(
                children: [
                  Container(
                    width: 60.w,
                    height: 60.h,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(15.r),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 30.sp),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, Admin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Responsive.fontSize(context, 24).sp,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Manage attendance & students',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14.sp,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildCalendarButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_instituteId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendanceCalendarScreen(
                    instituteId: _instituteId!,
                  ),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'View Attendance Calendar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrendButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_instituteId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendanceTrendScreen(
                    instituteId: _instituteId!,
                  ),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.show_chart, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'View Attendance Trend',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildManagementCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> items,
  }) {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...items,
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.7), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: child,
        ),
      ),
    );
  }

  Widget _buildProfileGovCard(bool isDark) {
    final avatar = Responsive.pctShortestSide(context, 0.12).clamp(44.0, 56.0);
    return GovElevatedCard(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      child: Row(
        children: [
          Container(
            width: avatar,
            height: avatar,
            decoration: BoxDecoration(
              color: AppTheme.accentSaffron.withValues(alpha: 0.25),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accentSaffron.withValues(alpha: 0.5)),
            ),
            child: Icon(Icons.person, color: AppTheme.primaryBlue, size: avatar * 0.55),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mr ${_profileName ?? 'Admin'}',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.textDark,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Best wishes for your day!',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                    fontSize: 13.sp,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          FutureBuilder<int>(
            future: OfflineService.getPendingCount(),
            builder: (context, snapshot) {
              final pendingCount = snapshot.data ?? 0;
              if (pendingCount <= 0) return const SizedBox.shrink();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.cloud_off, color: AppTheme.primaryBlue, size: 22.sp),
                    onPressed: () async {
                      if (_instituteId != null) {
                        await OfflineService.syncPendingAttendance(_instituteId!);
                        if (mounted) setState(() {});
                      }
                    },
                    tooltip: '$pendingCount pending sync',
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: EdgeInsets.all(4.w),
                      decoration: const BoxDecoration(
                        color: AppTheme.accentRed,
                        shape: BoxShape.circle,
                      ),
                      constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.h),
                      child: Text(
                        '$pendingCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.help_outline, color: AppTheme.primaryBlue, size: 22.sp),
            onPressed: () {
              Navigator.pushNamed(context, HelpDeskScreen.routeName);
            },
            tooltip: 'Help & Instructions',
          ),
          Consumer<ThemeService>(
            builder: (context, themeService, _) {
              return IconButton(
                icon: Icon(
                  themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: AppTheme.primaryBlue,
                  size: 22.sp,
                ),
                onPressed: () => themeService.toggleTheme(),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: AppTheme.primaryBlue, size: 22.sp),
            onPressed: () async {
              await SessionManager.signOut();
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(
                LoginScreen.routeName,
                (route) => false,
              );
            },
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  Widget _buildDateAndClockTimes(bool isDark) {
    final now = DateTime.now();
    final currentDate = DateFormat('d MMM, yyyy').format(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                currentDate,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            SizedBox(width: 8.w),
            // Total Students Count (from _loadDashboardStats, not polling)
            Flexible(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people, color: Colors.white, size: 16.sp),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        '$_studentCount Students',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16.h),
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                'Pending Sync',
                Icons.cloud_off,
                AppTheme.accentOrange,
                isDark,
                _buildPendingSyncContent,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: _buildInfoCard(
                "Today's Attendance",
                Icons.check_circle,
                AppTheme.primaryGreen,
                isDark,
                _buildTodayAttendanceContent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    String title,
    IconData icon,
    Color color,
    bool isDark,
    Widget Function() contentBuilder,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: contentBuilder(),
    );
  }

  Widget _buildPendingSyncContent() {
    return FutureBuilder<int>(
      future: OfflineService.getPendingCount(),
      builder: (context, snapshot) {
        final pendingCount = snapshot.data ?? 0;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        
        return GestureDetector(
          onTap: pendingCount > 0
              ? () async {
                  if (_instituteId != null) {
                    await OfflineService.syncPendingAttendance(_instituteId!);
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 12),
                              Text('Pending records synced successfully!'),
                            ],
                          ),
                          backgroundColor: AppTheme.primaryGreen,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    }
                  }
                }
              : null,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.cloud_off,
                  color: AppTheme.accentOrange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending Sync',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '$pendingCount records',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                    if (pendingCount > 0)
                      Text(
                        'Tap to sync',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.accentOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTodayAttendanceContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.check_circle,
            color: AppTheme.primaryGreen,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Attendance",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                '$_todayAttendanceCount marked',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildInstituteTimingCard(bool isDark) {
    if (_instituteTiming == null) return const SizedBox.shrink();
    
    final openTime = _instituteTiming!['openTime'] as TimeOfDay;
    final closeTime = _instituteTiming!['closeTime'] as TimeOfDay;
    final duration = _instituteTiming!['durationMinutes'] as int? ?? 60;
    
    final openTimeStr = '${openTime.hour.toString().padLeft(2, '0')}:${openTime.minute.toString().padLeft(2, '0')}';
    final closeTimeStr = '${closeTime.hour.toString().padLeft(2, '0')}:${closeTime.minute.toString().padLeft(2, '0')}';
    
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withValues(alpha: 0.1),
            AppTheme.primaryBlueDark.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              Icons.schedule_rounded,
              color: AppTheme.primaryBlue,
              size: 28.sp,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Institute Batch Timing',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppTheme.textDark.withValues(alpha: 0.7),
                  ),
                ),
                SizedBox(height: 4.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 2.h),
                      child: Icon(
                        Icons.access_time,
                        size: 16.sp,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8.w,
                        runSpacing: 6.h,
                        children: [
                          Text(
                            '$openTimeStr - $closeTimeStr',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.textDark,
                            ),
                          ),
                          if (duration == 120)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: AppTheme.accentOrange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                'Late Admission',
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accentOrange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  duration == 120 
                      ? '120 minutes per batch (2 hours)'
                      : '60 minutes per batch (1 hour)',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isDark ? Colors.white60 : AppTheme.textDark.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 18).sp,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    'Calendar',
                    Icons.calendar_today,
                    AppTheme.primaryGreen,
                    () {
                      if (_instituteId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceCalendarScreen(
                              instituteId: _instituteId!,
                            ),
                          ),
                        );
                      }
                    },
                    isDark,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildActionCard(
                    'Batches',
                    Icons.group_work_rounded,
                    AppTheme.primaryBlue,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BatchManagementScreen(),
                      ),
                    ),
                    isDark,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    'Trends',
                    Icons.show_chart,
                    AppTheme.accentOrange,
                    () {
                      if (_instituteId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceTrendScreen(
                              instituteId: _instituteId!,
                            ),
                          ),
                        );
                      }
                    },
                    isDark,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildActionCard(
                    'Reports',
                    Icons.bar_chart,
                    AppTheme.accentGreen,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AttendanceReportsScreen()),
                    ),
                    isDark,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            // Logout Button - Full Width
            _buildLogoutButton(isDark),
          ],
        );
      },
    );
  }

  Widget _buildLogoutButton(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.accentRed,
                AppTheme.accentRed.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentRed.withValues(alpha: 0.3),
                blurRadius: 12.r,
                offset: Offset(0, 4.h),
              ),
            ],
          ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            // Show confirmation dialog
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20.r),
                ),
                title: Row(
                  children: [
                    Icon(Icons.logout, color: AppTheme.accentRed, size: 28.sp),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        'Confirm Logout',
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 20).sp,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'Are you sure you want to logout?',
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: AppTheme.textDark,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    ),
                    child: Text('Logout', style: TextStyle(fontSize: 14.sp)),
                  ),
                ],
              ),
            );

            if (shouldLogout == true && mounted) {
              await SessionManager.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                  (route) => false,
                );
              }
            }
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, color: Colors.white, size: 24.sp),
                SizedBox(width: 12.w),
                Flexible(
                  child: Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: Responsive.fontSize(context, 18).sp,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      );
      },
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10.r,
                  offset: Offset(0, 2.h),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(icon, color: color, size: 20.sp),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeaturesGrid(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'All Features',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                // FeaturesGridScreen is not implemented yet
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(
                //     builder: (_) => FeaturesGridScreen(instituteId: _instituteId),
                //   ),
                // );
              },
              child: const Text(
                'View All',
                style: TextStyle(color: AppTheme.primaryBlue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
          children: [
            _buildFeatureGridCard(
              title: 'Batches',
              icon: Icons.group_work_rounded,
              color: AppTheme.primaryBlue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BatchManagementScreen()),
              ),
              isDark: isDark,
            ),
            _buildFeatureGridCard(
              title: 'Students',
              icon: Icons.school,
              color: AppTheme.primaryGreen,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StudentManagementScreen()),
              ),
              isDark: isDark,
            ),
            _buildFeatureGridCard(
              title: 'Reports',
              icon: Icons.bar_chart,
              color: AppTheme.accentOrange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AttendanceReportsScreen()),
              ),
              isDark: isDark,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureGridCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
