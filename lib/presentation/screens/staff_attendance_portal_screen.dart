import 'package:flutter/material.dart';

import '../../services/session_manager.dart';
import '../../services/geofence_service.dart';
import '../widgets/session_monitor.dart';
import 'login_screen.dart';
import 'student_management_screen.dart';
import 'institute_location_gate_screen.dart';

/// Attendance staff sees the same student experience as admin (student list, search, mark attendance).
/// Uses the same institute GPS fence as admin; resumes re-check institute radius (camera flows skipped).
class StaffAttendancePortalScreen extends StatefulWidget {
  static const routeName = '/staff-attendance-portal';

  const StaffAttendancePortalScreen({super.key});

  static Future<void> signOutToLogin(BuildContext context) async {
    await SessionManager.signOut();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        LoginScreen.routeName,
        (r) => false,
      );
    }
  }

  @override
  State<StaffAttendancePortalScreen> createState() => _StaffAttendancePortalScreenState();
}

class _StaffAttendancePortalScreenState extends State<StaffAttendancePortalScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 550), () async {
        if (!mounted || SessionMonitor.shouldSkipResumeLockForCamera) return;
        final ok = await GeofenceService().hasValidPersonalGpsForCurrentAdmin();
        if (!mounted || !ok) return;
        final gate = await GeofenceService().attendanceLocationGateForCurrentUser();
        if (!mounted || gate['allowed'] == true) return;
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
          InstituteLocationGateScreen.routeName,
          (_) => false,
          arguments: {'resumeRoute': StaffAttendancePortalScreen.routeName},
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: StudentManagementScreen(forAttendanceStaffPortal: true),
    );
  }
}
