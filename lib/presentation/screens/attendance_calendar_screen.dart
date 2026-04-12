import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';

/// Attendance Calendar Screen - Shows monthly calendar with attendance
class AttendanceCalendarScreen extends StatefulWidget {
  final String instituteId;
  final String? batchId;
  final String? rollNumber;

  const AttendanceCalendarScreen({
    super.key,
    required this.instituteId,
    this.batchId,
    this.rollNumber,
  });

  @override
  State<AttendanceCalendarScreen> createState() =>
      _AttendanceCalendarScreenState();
}

class _AttendanceCalendarScreenState extends State<AttendanceCalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDate = DateTime.now();
  Map<String, int> _attendanceMap = {}; // date -> count

  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  Future<void> _loadAttendanceData() async {
    final startOfMonth = DateTime(_focusedDate.year, _focusedDate.month, 1);
    final endOfMonth = DateTime(_focusedDate.year, _focusedDate.month + 1, 0);
    final startStr = DateFormat('yyyy-MM-dd').format(startOfMonth);
    final endStr = DateFormat('yyyy-MM-dd').format(endOfMonth);

    final code = await instituteCodeForId(widget.instituteId);
    final List<dynamic> rows;
    if (widget.rollNumber != null && widget.rollNumber!.isNotEmpty) {
      rows = await appDb
          .from('attendance_in_out')
          .select('attendance_date')
          .eq('institute_code', code)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr)
          .eq('sr_no', widget.rollNumber!);
    } else {
      rows = await appDb
          .from('attendance_in_out')
          .select('attendance_date')
          .eq('institute_code', code)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr);
    }
    final Map<String, int> tempMap = {};

    for (final r in rows) {
      final date = r['attendance_date']?.toString();
      if (date != null) {
        tempMap[date] = (tempMap[date] ?? 0) + 1;
      }
    }

    setState(() {
      _attendanceMap = tempMap;
    });
  }

  Future<int> _countForDate(String dateStr) async {
    final code = await instituteCodeForId(widget.instituteId);
    final List<dynamic> rows;
    if (widget.rollNumber != null && widget.rollNumber!.isNotEmpty) {
      rows = await appDb
          .from('attendance_in_out')
          .select('id')
          .eq('institute_code', code)
          .eq('attendance_date', dateStr)
          .eq('sr_no', widget.rollNumber!);
    } else {
      rows = await appDb
          .from('attendance_in_out')
          .select('id')
          .eq('institute_code', code)
          .eq('attendance_date', dateStr);
    }
    return rows.length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () {
              setState(() {
                _focusedDate = DateTime(
                  _focusedDate.year,
                  _focusedDate.month - 1,
                );
                _loadAttendanceData();
              });
            },
          ),
          Text(
            DateFormat('MMMM yyyy').format(_focusedDate),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: () {
              setState(() {
                _focusedDate = DateTime(
                  _focusedDate.year,
                  _focusedDate.month + 1,
                );
                _loadAttendanceData();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Calendar Grid
          Expanded(child: _buildCalendarGrid(isDark)),
          // Selected Date Info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade300,
                ),
              ),
            ),
            child: _buildDateInfo(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(bool isDark) {
    final firstDay = DateTime(_focusedDate.year, _focusedDate.month, 1);
    final lastDay = DateTime(_focusedDate.year, _focusedDate.month + 1, 0);
    final firstDayOfWeek = firstDay.weekday;
    final daysInMonth = lastDay.day;

    // Weekday headers
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Weekday headers
          Row(
            children: weekdays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : AppTheme.textGray,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Calendar days
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: firstDayOfWeek - 1 + daysInMonth,
              itemBuilder: (context, index) {
                if (index < firstDayOfWeek - 1) {
                  return const SizedBox.shrink();
                }

                final day = index - firstDayOfWeek + 2;
                final date = DateTime(
                  _focusedDate.year,
                  _focusedDate.month,
                  day,
                );
                final dateStr = DateFormat('yyyy-MM-dd').format(date);
                final hasAttendance = _attendanceMap.containsKey(dateStr);
                final isSelected =
                    _selectedDate.year == date.year &&
                    _selectedDate.month == date.month &&
                    _selectedDate.day == date.day;
                final isToday =
                    date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryBlue
                          : isToday
                          ? AppTheme.primaryBlue.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isToday
                            ? AppTheme.primaryBlue
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected || isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : isDark
                                ? Colors.white
                                : AppTheme.textDark,
                          ),
                        ),
                        if (hasAttendance)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateInfo(bool isDark) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final hasAttendance = _attendanceMap.containsKey(dateStr);

    return FutureBuilder<int>(
      future: _countForDate(dateStr),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasAttendance ? Icons.check_circle : Icons.cancel,
                  color: hasAttendance
                      ? AppTheme.primaryGreen
                      : AppTheme.accentRed,
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              hasAttendance
                  ? '$count attendance record${count > 1 ? 's' : ''} marked'
                  : 'No attendance marked',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppTheme.textGray,
              ),
            ),
          ],
        );
      },
    );
  }
}
