# Attendance Calculation Debug Guide

## Problem
The attendance widget is showing all students with 0 present days, but the PDF export shows correct mixed attendance values.

## Solution Steps

### Step 1: Run the Type Value Diagnostic

Add this code to a button press or app initialization to see what type values are actually in your database:

```dart
// In your attendance report screen or test file
await AttendanceDebugService.debugUniqueTypeValues(
  instituteCode: 'YOUR_INSTITUTE_CODE',
  startDate: DateTime.now().subtract(Duration(days: 30)),
  endDate: DateTime.now(),
);

// Check the console output - it will show you:
// - All unique type values found
// - How they're being interpreted
// - Whether they match 'entry' or 'exit'
```

### Step 2: Check Status Values

Run this to see what status values are in your database:

```dart
await AttendanceDebugService.debugStatusValues(
  instituteCode: 'YOUR_INSTITUTE_CODE',
  startDate: DateTime.now().subtract(Duration(days: 30)),
  endDate: DateTime.now(),
);

// This shows the 'status' field from the 'additional' JSON column
```

### Step 3: Debug a Specific Student

For detailed record-by-record analysis:

```dart
await AttendanceDebugService.debugStudentAttendance(
  instituteCode: 'YOUR_INSTITUTE_CODE',
  studentId: '001',  // Use the actual student ID
  startDate: DateTime.now().subtract(Duration(days: 30)),
  endDate: DateTime.now(),
);
```

### Step 4: Analyze Entry/Exit Patterns

```dart
final analysis = await AttendanceDebugService.analyzeEntryExit(
  instituteCode: 'YOUR_INSTITUTE_CODE',
  studentId: '001',
  startDate: DateTime.now().subtract(Duration(days: 30)),
  endDate: DateTime.now(),
);

print('Entry/Exit Analysis: $analysis');
```

---

## What to Look For

### Console Output Example - Type Values

If you see something like:
```
=== DEBUG: Unique Type Values ===
Found 2 unique type value(s):
  Raw: entry (Type: String) -> String: "entry" -> Lowercase: "entry"
  Raw: exit (Type: String) -> String: "exit" -> Lowercase: "exit"

=== MATCHING LOGIC TEST ===
Testing type matching:
  "entry" -> lowercase: "entry" -> entry: true, exit: false
  "exit" -> lowercase: "exit" -> entry: false, exit: true
```

✅ **Good** - Your types are correctly being recognized

### If You See Different Values

For example, if the output shows:
```
Raw: In (Type: String) -> String: "In" -> Lowercase: "in" -> entry: false, exit: false
Raw: Out (Type: String) -> String: "Out" -> Lowercase: "out" -> entry: false, exit: false
```

Then the service now handles this! The updated code recognizes:
- 'in' as entry
- 'out' as exit

### If Types Are Numeric

If you see:
```
Raw: 1 (Type: int) -> String: "1" -> Lowercase: "1" -> entry: false, exit: false
Raw: 0 (Type: int) -> String: "0" -> Lowercase: "0" -> entry: false, exit: false
```

The updated code maps:
- `1` → entry
- `0` or `2` → exit

---

## Type Matching Reference

The updated `AttendanceReportService` now recognizes these type values:

**Entry Types:**
- 'entry'
- 'in'
- 'check-in' / 'checkin'
- '1'
- 'enter'

**Exit Types:**
- 'exit'
- 'out'
- 'check-out' / 'checkout'
- '0', '2'
- 'leave'

---

## If It's Still Not Working

If after running the debug commands, types and statuses look correct but attendance still shows 0:

1. Check if `student_id` vs `sr_no` field mapping is correct
   ```dart
   final sid = (data['student_id'] as String?)?.trim() ?? '';
   final sr = (data['sr_no'] as String?)?.trim() ?? '';
   final rollNumber = sid.isNotEmpty ? sid : sr;
   ```
   The service prefers `student_id` and falls back to `sr_no`. Verify your student records have one of these fields filled.

2. Verify the 'additional' JSON field format:
   ```dart
   final add = data['additional'];
   final status = (add is Map ? add['status'] : null)?.toString().toLowerCase();
   ```
   The `additional` column should contain a JSON object with a 'status' key.

3. Check database directly:
   ```sql
   SELECT 
     student_id, sr_no, attendance_date, type, 
     additional->>'status' as status
   FROM attendance_in_out
   WHERE institute_code = 'YOUR_CODE'
   LIMIT 5;
   ```

---

## Performance Note

The debug functions print to console but don't affect app performance. You can leave them in during development and remove before production.
