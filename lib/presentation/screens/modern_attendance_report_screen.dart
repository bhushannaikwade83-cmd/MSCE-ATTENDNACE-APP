import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';

/// Modern Attendance Report Screen with Charts
class ModernAttendanceReportScreen extends StatefulWidget {
  final String instituteId;
  final String? rollNumber;

  const ModernAttendanceReportScreen({
    super.key,
    required this.instituteId,
    this.rollNumber,
  });

  @override
  State<ModernAttendanceReportScreen> createState() => _ModernAttendanceReportScreenState();
}

class _ModernAttendanceReportScreenState extends State<ModernAttendanceReportScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Attendance Report',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.description, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Donut Chart
            _buildDonutChart(),
            
            const SizedBox(height: 24),
            
            // Summary Statistics Grid
            _buildSummaryGrid(),
            
            const SizedBox(height: 24),
            
            // Daily Report Bar Chart
            _buildDailyReportChart(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(2), // Search selected
    );
  }

  Widget _buildDonutChart() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Overview',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: DonutChartPainter(),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '46',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final items = [
      {'label': 'Working Days', 'color': AppTheme.primaryBlue, 'value': '21'},
      {'label': 'On Time', 'color': AppTheme.primaryGreen, 'value': '18'},
      {'label': 'Late', 'color': AppTheme.accentRed, 'value': '2'},
      {'label': 'Absent', 'color': Colors.black, 'value': '0'},
      {'label': 'Left Timely', 'color': AppTheme.accentYellow, 'value': '4'},
      {'label': 'On Leave', 'color': Colors.purple, 'value': '1'},
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: item['color'] as Color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${item['value']} ${item['label']}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSummaryGrid() {
    final stats = [
      {'label': '21 Working Days', 'icon': Icons.calendar_today, 'color': AppTheme.primaryBlue},
      {'label': '18 On Time', 'icon': Icons.check_circle, 'color': AppTheme.primaryGreen},
      {'label': '2 Late', 'icon': Icons.access_time, 'color': AppTheme.accentRed},
      {'label': '21 Absent', 'icon': Icons.cancel, 'color': Colors.black},
      {'label': '21 Left Timely', 'icon': Icons.exit_to_app, 'color': AppTheme.accentYellow},
      {'label': '21 On leave', 'icon': Icons.event_busy, 'color': Colors.purple},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (stat['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  stat['icon'] as IconData,
                  color: stat['color'] as Color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  stat['label'] as String,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDailyReportChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Report',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: CustomPaint(
              painter: BarChartPainter(),
              child: Padding(
                padding: const EdgeInsets.only(left: 40, right: 20, bottom: 30),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(7, (index) {
                          final heights = [0.3, 0.6, 0.7, 1.0, 0.7, 0.5, 0.3];
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue,
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                      ),
                                      height: double.infinity,
                                      child: FractionallySizedBox(
                                        heightFactor: heights[index],
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryBlue,
                                            borderRadius: const BorderRadius.vertical(
                                              top: Radius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ['S', 'M', 'T', 'W', 'T', 'F', 'S'][index],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0h', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('3h', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('6h', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('8h', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(int selectedIndex) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, selectedIndex == 0),
              _buildNavItem(Icons.help_outline, selectedIndex == 1),
              _buildNavItem(Icons.search, selectedIndex == 2, isLarge: true),
              _buildNavItem(Icons.notifications_outlined, selectedIndex == 3),
              _buildNavItem(Icons.person_outline, selectedIndex == 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isSelected, {bool isLarge = false}) {
    return Container(
      width: isLarge ? 50 : 40,
      height: isLarge ? 50 : 40,
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade600,
        size: isLarge ? 28 : 24,
      ),
    );
  }
}

/// Custom Painter for Donut Chart
class DonutChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final data = [
      {'value': 21, 'color': AppTheme.primaryBlue},
      {'value': 18, 'color': AppTheme.primaryGreen},
      {'value': 2, 'color': AppTheme.accentRed},
      {'value': 0, 'color': Colors.black},
      {'value': 4, 'color': AppTheme.accentYellow},
      {'value': 1, 'color': Colors.purple},
    ];

    final total = data.fold<double>(0, (sum, item) => sum + (item['value'] as int).toDouble());
    double startAngle = -math.pi / 2;

    for (var item in data) {
      final value = item['value'] as int;
      final sweepAngle = (value / total) * 2 * math.pi;
      
      final paint = Paint()
        ..color = item['color'] as Color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom Painter for Bar Chart
class BarChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid lines
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
