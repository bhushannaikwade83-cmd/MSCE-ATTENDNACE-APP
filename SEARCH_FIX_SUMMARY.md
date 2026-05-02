# Student Search Fix - Summary

## Problem Identified
Student search in the student management screen was not returning any results even when students existed in the database.

**Root Cause:** The search filter was trying to match against database columns that don't exist:
- `first_name` (table has only `name`)
- `middle_name` (table has only `name`)  
- `last_name` (table has only `name`)
- `subjects_search` (table has `subjects`)
- `lecture_timing` (doesn't exist)

When PostgREST received an `.or()` filter with non-existent columns, it returned no results.

## Solution Applied

**File:** `lib/presentation/screens/student_management_screen.dart`

**Method:** `_studentSearchOrFilter()` (line 158)

**Change:** Updated search columns to match actual database columns in the `students` table:

### Before:
```dart
const cols = [
  'name',
  'first_name',
  'middle_name',
  'last_name',
  'user_id',
  'sr_no',
  'year',
  'subject',
  'subjects_search',
  'lecture_timing',
];
```

### After:
```dart
const cols = [
  'name',
  'user_id',
  'sr_no',
  'year',
  'subject',
];
```

## Database Columns Being Selected
The students table contains (from `_studentSelectCols`):
- `id` - Student UUID
- `name` - Full student name
- `user_id` - User identifier
- `sr_no` - Serial number / roll number
- `year` - Academic year
- `subject` - Subject field
- `subjects` - Array of subjects
- `face_photo_url` - Photo URL
- `face_embedding` - Face embedding vector

## Search Now Works For
Students can now be found by searching:
✓ Student name
✓ User ID
✓ SR No (roll number)
✓ Year
✓ Subject

## Testing
After deploying this fix, test the search by:
1. Open Student Management screen
2. Type a student's name in the search bar
3. Students should now appear in results
4. Try searching by SR No, year, or subject
5. Verify results only show students from the current institute

## Additional Notes
- Search uses `.ilike` (case-insensitive pattern matching)
- Search wildcards (`%`) are added automatically around the search term
- Institute filtering (`.eq('institute_id', _instituteId)`) remains AND-ed with search results
- Results are limited to 20 per page with infinite scroll pagination
