import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';

/// Quick Stats Widget - Shows today's attendance statistics
class QuickStatsWidget extends StatefulWidget {
  final String instituteId;
  final String? batchId;

  const QuickStatsWidget({
    super.key,
    required this.instituteId,
    this.batchId,
  });

  @override
  State<QuickStatsWidget> createState() => _QuickStatsWidgetState();
}

class _QuickStatsWidgetState extends State<QuickStatsWidget> {
  Timer? _timer;
  int _presentCount = 0;
  int _totalStudents = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final code = await instituteCodeForId(widget.instituteId);
      final attRows = await appDb
          .from('attendance_in_out')
          .select('id')
          .eq('institute_code', code)
          .eq('attendance_date', today);

      List<dynamic> studRows;
      if (widget.batchId != null && widget.batchId!.isNotEmpty) {
        studRows = await appDb
            .from('students')
            .select('id')
            .eq('institute_id', widget.instituteId)
            .eq('batch_id', widget.batchId!);
      } else {
        studRows = await appDb.from('students').select('id').eq('institute_id', widget.instituteId);
      }

      if (mounted) {
        setState(() {
          _presentCount = attRows.length;
          _totalStudents = studRows.length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      final h = Responsive.pctHeight(context, 0.14).clamp(96.0, 160.0);
      return SizedBox(
        height: h,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final presentCount = _presentCount;
    final totalStudents = _totalStudents;
    final absentCount = totalStudents > presentCount ? totalStudents - presentCount : 0;
    final attendanceRate = totalStudents > 0 ? (presentCount / totalStudents * 100) : 0.0;

    return Container(
      padding: EdgeInsets.all(Responsive.pctWidth(context, 0.05).clamp(14.0, 28.0)),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : AppTheme.primaryBlue.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.today,
                color: AppTheme.primaryBlue,
                size: Responsive.pctShortestSide(context, 0.06).clamp(20.0, 28.0),
              ),
              SizedBox(width: Responsive.pctWidth(context, 0.02).clamp(6.0, 12.0)),
              Expanded(
                child: Text(
                  'Today\'s Stats',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  'Present',
                  presentCount,
                  AppTheme.primaryGreen,
                  Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Absent',
                  absentCount,
                  AppTheme.accentRed,
                  Icons.cancel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Total',
                  totalStudents,
                  AppTheme.primaryBlue,
                  Icons.people,
                ),
              ),
            ],
          ),
          if (totalStudents > 0) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Attendance Rate',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white.withValues(alpha: 0.7) : AppTheme.textGray,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${attendanceRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: attendanceRate / 100,
                minHeight: 6,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppTheme.primaryBlue.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    int value,
    Color color,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white.withValues(alpha: 0.7) : AppTheme.textGray,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
