# After Merge: SR NO Auto-Renumbering & List Refresh

## Problem 1: App Still Shows Old Records After Merge ❌

**What Happens:**
1. Database: Students merged successfully ✓
2. App: Student list still shows BOTH old records with different SR NOs ✗

**Why:**
- App is caching the student list in memory
- Not refreshing from database after merge
- Shows stale data

---

## Problem 2: SR NO Not Auto-Renumbered After Delete ❌

**What Happens:**
```
Before merge:
SR NO 001, 002, 003

After merge (001 + 002 combined, so 002 deleted):
SR NO 001, 003   ✗ WRONG! Should be 001, 002

Should be:
SR NO 001, 002   ✓ CORRECT!
```

**Expected Behavior:**
```
If SR NO deleted → Auto-renumber remaining sequentially:
Delete 1: [1,2,3] → [2,3] → [1,2] ✓
Delete 2: [1,2,3] → [1,3] → [1,2] ✓
```

---

## Fix 1: Force List Refresh After Merge

### Location: `lib/presentation/screens/student_management_screen.dart`

**Add this function to reload student list:**

```dart
/// Refresh student list from database (call after merge)
Future<void> _refreshStudentList({bool showMessage = true}) async {
  if (instituteId == null) return;
  
  try {
    setState(() {
      isLoading = true;
    });

    // Clear cache and reload from database
    final { data, error } = await _db
        .from('students')
        .select('*')
        .eq('institute_id', instituteId!)
        .order('sr_no')
        .order('name');
    
    if (error != null) throw error;
    
    setState(() {
      students = (data ?? []) as List<Student>;
      isLoading = false;
    });

    if (showMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Student list refreshed - duplicates removed'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    setState(() {
      isLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error refreshing list: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

**Call this function after merge SQL finishes:**

```dart
// After running MERGE_DUPLICATE_STUDENTS_FIXED_FINAL.sql
// In admin portal, add button:

ElevatedButton(
  onPressed: () async {
    // Run merge SQL
    // Then refresh list
    await _refreshStudentList(showMessage: true);
  },
  child: const Text('✅ Merge & Refresh'),
)
```

---

## Fix 2: Auto-Renumber SR NOs After Merge

### Database Solution: Update SR NO Sequentially

Run this SQL AFTER the merge is complete:

```sql
-- ========================================
-- AUTO-RENUMBER SR NOs After Merge
-- ========================================

-- For each institute, renumber SR NO sequentially (1, 2, 3, ...)

WITH institute_students AS (
  SELECT
    s.id,
    s.institute_id,
    s.name,
    s.sr_no,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id
      ORDER BY 
        COALESCE(s.sr_no, '999')::int,
        s.created_at
    ) as new_sr_no
  FROM public.students s
)
UPDATE public.students s
SET sr_no = LPAD(is.new_sr_no::text, 3, '0')
FROM institute_students is
WHERE s.id = is.id
  AND s.sr_no != LPAD(is.new_sr_no::text, 3, '0');

-- Verify renumbering
SELECT
  i.institute_code,
  s.sr_no,
  s.name,
  COUNT(*) as count
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.institute_code, s.sr_no, s.name
ORDER BY i.institute_code, s.sr_no::int;
```

### What This Does:

1. **Partitions** students by institute
2. **Orders** by sr_no (or creation time if null)
3. **Assigns** new sequential numbers (1, 2, 3, ...)
4. **Pads** with zeros (001, 002, 003, ...)
5. **Updates** only if SR NO changed

**Example:**
```
Before:
Institute 11063:
  SR NO 001 - AASHISH (merged, kept)
  SR NO 003 - KALYANI (kept - 002 was deleted)
  SR NO 004 - RAHUL (kept - some 002/003 deleted)

After renumbering:
  SR NO 001 - AASHISH
  SR NO 002 - KALYANI
  SR NO 003 - RAHUL
```

---

## Complete Merge + Refresh Workflow

```
Step 1: Run merge SQL
   ↓
Step 2: Run SR NO renumbering SQL
   ↓
Step 3: Call _refreshStudentList() in app
   ↓
Step 4: Verify in app - shows only merged students with sequential SR NOs
```

---

## Implementation Steps

### Step 1: Execute Merge
```sql
-- Run MERGE_DUPLICATE_STUDENTS_FIXED_FINAL.sql
```

### Step 2: Renumber SR NOs
```sql
-- Run the SQL above
```

### Step 3: Refresh App List
In admin portal, add button or call on page load:
```dart
await _refreshStudentList(showMessage: true);
```

### Step 4: Verify
- ✅ Only merged students shown
- ✅ SR NO sequential (001, 002, 003, ...)
- ✅ No gaps in SR NO sequence
- ✅ No duplicate entries

---

## Testing Checklist

- [ ] Merged students appear as single record
- [ ] Old duplicate records gone
- [ ] SR NO renumbered sequentially
- [ ] No gaps in SR NO (001, 002, 003... not 001, 003, 004)
- [ ] All subjects combined in one record
- [ ] Photo from best record (with face_photo_url)
- [ ] List refreshes immediately after merge

---

## If Manual Renumbering Needed

If you need to manually renumber for just ONE institute:

```sql
-- Renumber students for specific institute only
WITH students_to_renumber AS (
  SELECT
    s.id,
    s.name,
    ROW_NUMBER() OVER (
      ORDER BY s.created_at
    ) as new_sr_no
  FROM public.students s
  WHERE s.institute_id = (
    SELECT id FROM public.institutes WHERE institute_code = '11063'
  )
)
UPDATE public.students s
SET sr_no = LPAD(str.new_sr_no::text, 3, '0')
FROM students_to_renumber str
WHERE s.id = str.id;
```

---

## Summary

**Before Fix:**
- Database: Merged ✓
- App: Still shows old records ✗
- SR NO: Has gaps (001, 003, 005...) ✗

**After Fix:**
- Database: Merged ✓
- App: Shows only merged records ✓
- SR NO: Sequential (001, 002, 003...) ✓
