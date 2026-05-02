# CRITICAL FIX: Wrong Student Photos in Attendance Display

## Issue

**Different student's photos are showing in attendance records**

Example from screenshot:
- Student "Adiba Isak Mulla" (SR NO: 014) displays her profile photo
- But the Entry photo shows a DIFFERENT person
- This is a critical data integrity issue

---

## Root Cause

The query fetching attendance photos is NOT properly filtering by `student_id`.

### Current Query (BROKEN)
```sql
SELECT * FROM attendance_in_out
WHERE institute_code = 'xyz'
  AND attendance_date = '2026-04-22'
-- MISSING: AND student_id = 'specific_student_id'
-- RESULT: Returns ALL students' photos for that date
-- Then displays wrong photo for each student
```

### Correct Query (MUST BE)
```sql
SELECT * FROM attendance_in_out
WHERE institute_code = 'xyz'
  AND attendance_date = '2026-04-22'
  AND student_id = 'specific_student_id'    -- ✅ CRITICAL
  AND type = 'entry'                         -- ✅ Get ENTRY photo
-- RESULT: Only this student's ENTRY photo for today
```

---

## Where to Fix

### Files That Need Checking

1. **Attendance Display Screen** (Shows student records)
   - Check: `attendance_screen.dart`
   - Check: `teacher_attendance_screen.dart`
   - Check: `admin_home_screen.dart`

2. **Photo Fetching Service**
   - Check: `hierarchical_attendance_service.dart`
   - Check: `student_validation_service.dart`

3. **Database Queries**
   - Look for: `FROM attendance_in_out SELECT`
   - Add: `.eq('student_id', studentId)` filter

---

## The Fix

### Pattern 1: Fetching Attendance for ONE Student

**BEFORE (WRONG):**
```dart
final rows = await appDb
    .from('attendance_in_out')
    .select('*')
    .eq('institute_code', code)
    .eq('attendance_date', date);
    // Missing student_id filter!
    
for (final row in rows) {
  // This loops through ALL students
  // Wrong photo displayed!
}
```

**AFTER (CORRECT):**
```dart
final entryPhoto = await appDb
    .from('attendance_in_out')
    .select('photo_url, photoUrl')
    .eq('institute_code', code)
    .eq('attendance_date', date)
    .eq('student_id', studentId)        // ✅ FIX: Add this
    .eq('type', 'entry')                // ✅ FIX: Only entry
    .order('created_at', ascending: false)
    .limit(1)
    .maybeSingle();
```

---

## Critical Filters

### Every photo fetch MUST have:

```dart
// 1. Filter by specific student
.eq('student_id', studentId)

// 2. Filter by specific date
.eq('attendance_date', dateString)

// 3. Filter by photo type (entry/exit)
.eq('type', 'entry')  // or 'exit'

// 4. Get latest if multiple
.order('created_at', ascending: false)
.limit(1)

// 5. Get just one record
.maybeSingle()
```

---

## Complete Fix for Attendance Display

### Function to Fetch Student's Entry Photo
```dart
Future<String?> _getStudentEntryPhoto(String studentId, String attendanceDate, String instituteCode) async {
  try {
    final row = await appDb
        .from('attendance_in_out')
        .select('photo_url, photoUrl, additional')
        .eq('student_id', studentId)           // ✅ SPECIFIC STUDENT
        .eq('attendance_date', attendanceDate) // ✅ TODAY ONLY
        .eq('institute_code', instituteCode)   // ✅ THIS INSTITUTE
        .eq('type', 'entry')                   // ✅ ENTRY PHOTO
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    
    if (row == null) return null;
    
    // Try different column names
    String? photoUrl = row['photo_url'] as String?;
    photoUrl ??= row['photoUrl'] as String?;
    
    // Check additional data
    if (photoUrl == null && row['additional'] is Map) {
      final add = row['additional'] as Map;
      photoUrl = add['photoUrl'] as String?;
    }
    
    return photoUrl;
  } catch (e) {
    debugPrint('❌ Error fetching entry photo: $e');
    return null;
  }
}

Future<String?> _getStudentExitPhoto(String studentId, String attendanceDate, String instituteCode) async {
  try {
    final row = await appDb
        .from('attendance_in_out')
        .select('photo_url, photoUrl, additional')
        .eq('student_id', studentId)           // ✅ SPECIFIC STUDENT
        .eq('attendance_date', attendanceDate) // ✅ TODAY ONLY
        .eq('institute_code', instituteCode)   // ✅ THIS INSTITUTE
        .eq('type', 'exit')                    // ✅ EXIT PHOTO
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    
    if (row == null) return null;
    
    // Try different column names
    String? photoUrl = row['photo_url'] as String?;
    photoUrl ??= row['photoUrl'] as String?;
    
    // Check additional data
    if (photoUrl == null && row['additional'] is Map) {
      final add = row['additional'] as Map;
      photoUrl = add['photoUrl'] as String?;
    }
    
    return photoUrl;
  } catch (e) {
    debugPrint('❌ Error fetching exit photo: $e');
    return null;
  }
}
```

---

## Usage in UI

### When Building Student Record Card:
```dart
Widget _buildStudentCard(Map<String, dynamic> student) {
  final studentId = student['id'] as String;
  final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  
  return FutureBuilder<String?>(
    future: _getStudentEntryPhoto(
      studentId,
      todayDate,
      instituteCode,
    ),
    builder: (context, snapshot) {
      final entryPhotoUrl = snapshot.data;
      
      return Column(
        children: [
          // Student profile photo
          if (student['photo'] != null)
            Image.network(student['photo']),
          
          // ENTRY photo
          if (entryPhotoUrl != null)
            Image.network(entryPhotoUrl)
          else
            Icon(Icons.camera_alt, size: 100),
          
          // EXIT photo
          FutureBuilder<String?>(
            future: _getStudentExitPhoto(
              studentId,
              todayDate,
              instituteCode,
            ),
            builder: (context, snapshot) {
              final exitPhotoUrl = snapshot.data;
              return exitPhotoUrl != null
                  ? Image.network(exitPhotoUrl)
                  : Icon(Icons.camera_alt, size: 100);
            },
          ),
        ],
      );
    },
  );
}
```

---

## Verification Checklist

After applying the fix:

- [ ] Each student shows their OWN profile photo (top-left)
- [ ] Each student's ENTRY photo is of that student only
- [ ] Each student's EXIT photo is of that student only
- [ ] No cross-student photo mixing
- [ ] Photos update when new attendance marked
- [ ] Different dates show different/no photos
- [ ] Empty states show camera icon (no photo yet)

---

## Data Integrity Check SQL

To verify data is correct in database:

```sql
-- Check if each student has correct entry/exit photos

SELECT 
  student_id,
  sr_no,
  attendance_date,
  type,
  photo_url,
  photoUrl,
  COUNT(*) as count
FROM attendance_in_out
WHERE attendance_date = '2026-04-22'
  AND institute_code = 'INSTITUTE_CODE'
GROUP BY student_id, type
ORDER BY student_id, type;
```

If you see:
- Student A has Student B's photo → **DATA CORRUPTION**
- Same student has multiple entry photos on same day → **NEEDS CLEANUP**
- NULL photos when marked → **SYNC ISSUE**

---

## Prevention (For Future)

Always use this checklist when fetching photos:

```
[ ] Filtering by student_id? YES/NO
[ ] Filtering by attendance_date? YES/NO
[ ] Filtering by type (entry/exit)? YES/NO
[ ] Getting latest record (.limit(1))? YES/NO
[ ] Using .maybeSingle() not .select()? YES/NO
```

If ANY is NO, the query is BROKEN.

---

## Summary

**BROKEN:** `SELECT * FROM attendance_in_out WHERE date = X`
**FIXED:** `SELECT * FROM attendance_in_out WHERE student_id = Y AND date = X AND type = entry LIMIT 1`

The critical addition is:
- `.eq('student_id', specificStudentId)` ← **MUST HAVE**
- `.eq('type', 'entry')` ← **MUST HAVE**
- `.limit(1)` ← **MUST HAVE**

---

## Questions?

1. **Which screen shows the wrong photos?**
   - Tell me the exact screen name/route
   - I can pinpoint the exact broken query

2. **Are entry/exit photos swapped?**
   - Or completely wrong students?
   - Helps narrow down the issue

3. **When did this start?**
   - After registration?
   - After attendance marking?
   - After app update?

---

## Next Steps

1. Identify the exact screen showing wrong photos
2. Find the query that fetches attendance records
3. Add `.eq('student_id', studentId)` filter
4. Test with multiple students on same day
5. Verify each student sees only their photos

This is a critical data integrity issue. Fix immediately before more data gets corrupted.
