# Entry/Exit Photos Not Showing - Troubleshooting Guide

## Problem
Students mark attendance (entry and exit), but photos are not displaying in the Student Records view.

---

## How Entry/Exit Photos Should Work

### 1. Photo Capture Flow
```
Student marks ENTRY
├─ Camera captures photo
├─ Photo uploaded to Storage
├─ Photo URL received
├─ Saved to attendance_in_out table:
│  └─ photo_url = "https://storage.../photo.jpg"
│  └─ type = "entry"
└─ Record created in DB

Student marks EXIT
├─ Camera captures photo  
├─ Photo uploaded to Storage
├─ Photo URL received
├─ Saved to attendance_in_out table (NEW record):
│  └─ photo_url = "https://storage.../photo2.jpg"
│  └─ type = "exit"
└─ Record created in DB
```

### 2. Photo Display Flow in Student Records
```
Load today's attendance data
├─ Query attendance_in_out table
├─ Group by student_id
├─ For each record:
│  ├─ If type == "exit": store in payload['exitPhoto']
│  └─ If type == "entry": store in payload['entryPhoto']
├─ Display thumbnails
│  ├─ Entry photo (green border)
│  └─ Exit photo (orange border)
└─ Show camera icon if no photo
```

---

## Files Involved

### Photo Storage
**File:** `lib/services/inline_student_attendance_service.dart`
- **Lines 758-766:** Upload photo using `StorageService`
- **Lines 789, 844:** Store `photo_url` in database
- **Lines 911-944:** Sync to `attendance_in_out` table

### Photo Display
**File:** `lib/presentation/screens/student_management_screen.dart`
- **Lines 246-252:** Query attendance_in_out for today's records
- **Lines 256-285:** Loop through records and populate payload
- **Lines 679-689:** Extract photo URLs from payload
- **Lines 1028-1042:** Display thumbnails via `_buildAttendanceThumb()`

---

## Common Issues & Fixes

### Issue 1: Photos Not Uploaded to Storage
**Symptom:** photoUrl is empty/null in database

**Check:** `StorageService.uploadAttendancePhoto()` 
- Is photo being captured correctly?
- Is storage service returning valid URL?
- Are there storage permission errors?

**Fix:**
- Check StorageService logs
- Verify storage bucket exists and has write permissions
- Ensure StorageService returns valid URL in response

---

### Issue 2: Photos Stored But Not Queried Correctly
**Symptom:** Photos in database but not showing in UI

**Check:** `_loadTodayAttendancePayloads()` query
```dart
final rows = await appDb
    .from('attendance_in_out')
    .select('student_id,sr_no,type,photo_url,created_at,additional')
    .eq('institute_code', code)
    .eq('attendance_date', today)
    .eq('student_id', studentId)  // ← This filter!
    .order('created_at', ascending: false);
```

**Verify:**
- ✅ Is institute_code matching?
- ✅ Is attendance_date today's date (YYYY-MM-DD format)?
- ✅ Is student_id correct?
- ✅ Are photo records being returned?

**Quick Test SQL:**
```sql
SELECT student_id, sr_no, type, photo_url, attendance_date, created_at
FROM attendance_in_out
WHERE institute_code = 'YOUR_CODE'
  AND attendance_date = '2026-04-22'
  AND student_id = 'STUDENT_ID'
ORDER BY created_at DESC;
```

If records exist but photo_url is empty:
- Photos weren't uploaded properly
- Storage service failed silently
- Photo URL wasn't stored in database

---

### Issue 3: Photo Display Logic Error
**Symptom:** Photos in database but logic not extracting them

**Current Logic (lines 256-285):**
```dart
for (final raw in rows) {
  final type = (row['type']?.toString() ?? '').toLowerCase();
  final photoUrl = (row['photo_url'] ?? '').toString().trim();
  
  if (type == 'exit') {
    if (payload['exitPhoto'] == null && photoUrl.isNotEmpty) {
      payload['exitPhoto'] = photoUrl;
    }
  } else {
    if (payload['entryPhoto'] == null && photoUrl.isNotEmpty) {
      payload['entryPhoto'] = photoUrl;
    }
  }
}
```

**Possible Issues:**
1. `type` is not exactly 'exit' (has extra spaces/case issues)
   - Fix: Add `.trim()` and `.toLowerCase()`

2. `photoUrl` is empty string or null
   - Fix: Verify photo was uploaded and URL stored

3. Payload already has photos (first condition fails)
   - This is intentional - takes first occurrence

---

### Issue 4: SecureNetworkImage Not Loading Photos
**Symptom:** Photo URLs exist but images show as broken

**Check:** `_buildAttendanceThumb()` (lines 716-778)
```dart
imageUrl != null && imageUrl.isNotEmpty
    ? SecureNetworkImage(
        imageUrl: imageUrl,
        storagePath: null,
        ...
      )
    : ColoredBox(
        child: Icon(Icons.photo_camera_outlined, ...)
      )
```

**Verify:**
- ✅ imageUrl is not null and not empty
- ✅ URL is valid and accessible
- ✅ URL is publicly readable
- ✅ Network connectivity is working

**Test:**
- Can you access the photo URL directly in browser?
- Is the URL format correct?
- Does storage service return absolute URLs?

---

## Debugging Steps

### Step 1: Check Database
```sql
-- Check if photos are being stored
SELECT 
  COUNT(*) as total_records,
  COUNT(DISTINCT student_id) as students,
  COUNT(photo_url) as records_with_photos,
  COUNT(CASE WHEN type='entry' THEN 1 END) as entry_records,
  COUNT(CASE WHEN type='exit' THEN 1 END) as exit_records
FROM attendance_in_out
WHERE institute_code = 'YOUR_CODE'
  AND attendance_date = '2026-04-22';

-- Check if photo URLs are valid
SELECT student_id, sr_no, type, photo_url
FROM attendance_in_out
WHERE institute_code = 'YOUR_CODE'
  AND attendance_date = '2026-04-22'
  AND photo_url IS NOT NULL
LIMIT 5;
```

### Step 2: Check Storage Service
- Add debug logging to `StorageService.uploadAttendancePhoto()`
- Verify URL is returned and is not empty
- Check if URL is accessible externally

### Step 3: Check Query Results
- Add debug logging to `_loadTodayAttendancePayloads()`
- Print what's returned from database query
- Check if rows contain photo_url

### Step 4: Check Display Logic
- Verify payload has `entryPhoto` and `exitPhoto` keys
- Check if URLs are empty or null
- Trace through `_entryPhotoUrl()` and `_exitPhotoUrl()` methods

---

## Testing Checklist

- [ ] Mark entry attendance with good lighting
  - Wait 5 seconds for upload
  - Go back to Student Records
  - Entry photo thumbnail should show

- [ ] Mark exit attendance  
  - Go back to Student Records
  - Both entry and exit photos should show

- [ ] Check database directly
  - Verify records in attendance_in_out
  - Verify photo_url has valid URL

- [ ] Test with different students
  - Photos should not mix (each student sees only their photos)
  - All students should be able to see their photos

- [ ] Check storage access
  - Try opening photo URL in browser
  - Verify it loads the image

---

## If Still Not Working

Check these files in order:
1. **StorageService** - Is photo upload returning valid URL?
2. **HierarchicalAttendanceService.saveAttendance()** - Is photo_url being stored?
3. **student_management_screen.dart - `_loadTodayAttendancePayloads()`** - Is query returning photos?
4. **student_management_screen.dart - display logic** - Is payload being populated correctly?
5. **SecureNetworkImage** - Is widget trying to load the URL?

Add `debugPrint()` at each step to trace the photo data flow.

