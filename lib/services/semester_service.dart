/// Semester Service
/// Handles predefined semesters:
/// - Semester 1: January to June
/// - Semester 2: July to December
/// Year is auto-detected from device date
class SemesterService {

  /// Get current year from device date
  int getCurrentYear() {
    return DateTime.now().year;
  }

  /// Get current semester based on current month
  /// Returns 1 for Jan-Jun, 2 for Jul-Dec
  int getCurrentSemester() {
    final month = DateTime.now().month;
    return month >= 1 && month <= 6 ? 1 : 2;
  }

  /// Get semester name with year
  /// Format: "Semester 1 - Jan to Jun 2026"
  String getSemesterName(int semester, int year) {
    if (semester == 1) {
      return 'Semester 1 - Jan to Jun $year';
    } else {
      return 'Semester 2 - Jul to Dec $year';
    }
  }

  /// Get semester code
  /// Format: "1-2026" or "2-2026"
  String getSemesterCode(int semester, int year) {
    return '$semester-$year';
  }

  /// Get all available semesters for a given year
  List<Map<String, dynamic>> getAvailableSemesters(int year) {
    return [
      {
        'semester': 1,
        'year': year,
        'name': getSemesterName(1, year),
        'code': getSemesterCode(1, year),
        'startMonth': 1,
        'endMonth': 6,
        'startDate': DateTime(year, 1, 1),
        'endDate': DateTime(year, 6, 30),
      },
      {
        'semester': 2,
        'year': year,
        'name': getSemesterName(2, year),
        'code': getSemesterCode(2, year),
        'startMonth': 7,
        'endMonth': 12,
        'startDate': DateTime(year, 7, 1),
        'endDate': DateTime(year, 12, 31),
      },
    ];
  }

  /// Get semesters for current year and next year
  List<Map<String, dynamic>> getSemestersForSelection() {
    final currentYear = getCurrentYear();
    final nextYear = currentYear + 1;
    
    final semesters = <Map<String, dynamic>>[];
    
    // Current year semesters
    semesters.addAll(getAvailableSemesters(currentYear));
    
    // Next year semesters
    semesters.addAll(getAvailableSemesters(nextYear));
    
    return semesters;
  }

  /// Check if a date falls within a semester
  bool isDateInSemester(DateTime date, int semester, int year) {
    if (semester == 1) {
      return date.year == year && date.month >= 1 && date.month <= 6;
    } else {
      return date.year == year && date.month >= 7 && date.month <= 12;
    }
  }

  /// Get semester for a given date
  Map<String, dynamic>? getSemesterForDate(DateTime date) {
    final year = date.year;
    final month = date.month;
    
    int semester;
    if (month >= 1 && month <= 6) {
      semester = 1;
    } else {
      semester = 2;
    }
    
    return {
      'semester': semester,
      'year': year,
      'name': getSemesterName(semester, year),
      'code': getSemesterCode(semester, year),
    };
  }
}
