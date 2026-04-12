import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/enhanced_animations.dart';
import 'student_management_screen.dart';
import 'help_desk_screen.dart';
import 'add_student_screen.dart';
import 'attendance_reports_screen.dart';
import 'batch_management_screen.dart';
import 'gps_settings_screen.dart';
import 'attendance_calendar_screen.dart';
import 'attendance_trend_screen.dart';

/// Features Grid Screen - Displays all features in a grid layout
/// Similar to the reference design with square buttons
class FeaturesGridScreen extends StatefulWidget {
  final String? instituteId;
  
  const FeaturesGridScreen({
    super.key,
    this.instituteId,
  });

  @override
  State<FeaturesGridScreen> createState() => _FeaturesGridScreenState();
}

class _FeaturesGridScreenState extends State<FeaturesGridScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white, size: 24.sp),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Features',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: Responsive.fontSize(context, 20).sp,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: Responsive.padding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grid of Features with Staggered Animations
                GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Responsive.gridColumns(context),
                    mainAxisSpacing: Responsive.pctWidth(context, 0.04).clamp(10.0, 20.0),
                    crossAxisSpacing: Responsive.pctWidth(context, 0.04).clamp(10.0, 20.0),
                    childAspectRatio: 1.0,
                  ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 8,
              itemBuilder: (context, index) {
                final features = [
                  {'title': 'Help Desk', 'icon': Icons.support_agent, 'color': AppTheme.primaryBlue, 'screen': const HelpDeskScreen()},
                  {'title': 'Students', 'icon': Icons.school, 'color': AppTheme.primaryGreen, 'screen': const StudentManagementScreen()},
                  {'title': 'Reports', 'icon': Icons.bar_chart, 'color': AppTheme.accentOrange, 'screen': const AttendanceReportsScreen()},
                  {'title': 'Calendar', 'icon': Icons.calendar_today, 'color': AppTheme.primaryBlue, 'screen': widget.instituteId != null ? AttendanceCalendarScreen(instituteId: widget.instituteId!) : null},
                  {'title': 'Batches', 'icon': Icons.groups, 'color': AppTheme.primaryGreen, 'screen': const BatchManagementScreen()},
                  {'title': 'Settings', 'icon': Icons.settings, 'color': AppTheme.accentOrange, 'screen': const GpsSettingsScreen()},
                  {'title': 'Trends', 'icon': Icons.show_chart, 'color': AppTheme.primaryBlue, 'screen': widget.instituteId != null ? AttendanceTrendScreen(instituteId: widget.instituteId!) : null},
                  {'title': 'Add Student', 'icon': Icons.person_add, 'color': AppTheme.primaryGreen, 'screen': const AddStudentScreen()},
                ];
                
                final feature = features[index];
                return _buildFeatureCard(
                  title: feature['title'] as String,
                  icon: feature['icon'] as IconData,
                  color: feature['color'] as Color,
                  onTap: () {
                    final screen = feature['screen'];
                    if (screen != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => screen as Widget),
                      );
                    }
                  },
                  isDark: isDark,
                ).stagger(index: index);
              },
            ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12.r,
                  offset: Offset(0, 4.h),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(Responsive.pctShortestSide(context, 0.04).clamp(12.0, 24.0)),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: Responsive.pctShortestSide(context, 0.09).clamp(28.0, 44.0),
                  ),
                ),
                SizedBox(height: Responsive.pctHeight(context, 0.012).clamp(8.0, 20.0)),
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: Responsive.pctWidth(context, 0.02)),
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 14).sp,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
