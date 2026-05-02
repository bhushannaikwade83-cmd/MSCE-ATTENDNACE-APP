# Duplicate Student Records - Identification & Cleanup Guide

## What Are Duplicate Students?

**Duplicates exist when:**
- ✅ Same institute
- ✅ Same student ID (user_id OR sr_no)
- ✅ Same student full name
- ❌ BUT DIFFERENT subjects

### Example:
```
Record 1: Institute 23101 | SR NO 001 | "Bhushan Naikwade" | Subjects: [Math, Physics]
Record 2: Institute 23101 | SR NO 001 | "Bhushan Naikwade" | Subjects: [Chemistry, Biology]
          ↑ DUPLICATES - Same student entered twice with different subjects!
```

## Why Do Duplicates Happen?

1. **Manual data entry errors** - Student registered twice by mistake
2. **Subject updates** - Instead of updating, a new record was created
3. **Migration issues** - Data import created duplicate entries
4. **System bugs** - Registration flow didn't check for existing records
5. **Multiple registrations** - Student registered themselves multiple times

## How to Identify Duplicates

### SQL Query Files Created:

**1. `CHECK_DUPLICATE_STUDENTS.sql`**
- Shows all duplicate groups
- Lists different subject combinations
- Summary by institute

**2. `IDENTIFY_DUPLICATE_TO_DELETE.sql`**
- Shows which records to KEEP
- Shows which records to DELETE
- Generates cleanup statements

## Step-by-Step Identification

### Step 1: Run Check Query
```sql
-- From CHECK_DUPLICATE_STUDENTS.sql - Query #1
-- Shows: student name, institute, how many duplicates, subject variations
```

### Step 2: Review Results
Look for:
- duplicate_count > 1 (means 2+ records for same student)
- different_subject_combinations (shows subject variation)
- subject_variations (list of different subjects)

### Example Result:
```
institute_id        | sr_no | name              | duplicate_count | different_subject_combinations
────────────────────┼───────┼──────────────────┼─────────────────┼────────────────────────────
f47ac10b-58cc-4372  | 001   | Bhushan Naikwade | 2               | 2
f47ac10b-58cc-4372  | 005   | Rahul Sharma     | 3               | 3
```

This shows:
- Bhushan has 2 records with 2 different subject sets
- Rahul has 3 records with 3 different subject sets

### Step 3: See Detailed Duplicate Records
```sql
-- From IDENTIFY_DUPLICATE_TO_DELETE.sql - First query
-- Shows which record to KEEP (newest)
```

### Step 4: Generate Delete Statements
```sql
-- From IDENTIFY_DUPLICATE_TO_DELETE.sql - Last query
-- Shows DELETE statements for duplicate records
```

## Decision: Which to Keep? Which to Delete?

### KEEP Strategy: Newest Record
The system keeps the **newest record** (most recent created_at):

```
Record 1: Created: 2024-01-01 (OLDEST) → DELETE
Record 2: Created: 2024-01-15 (NEWEST) → KEEP ✅
```

### Why Keep Newest?
- ✅ Most recent data
- ✅ Latest subject assignments
- ✅ Most up-to-date face photo
- ✅ Latest face embedding

### DELETE: Older Records
- Delete all older duplicate records
- Keep only the most recent one
- Merge critical data if needed

## Data to Consider Before Deleting

### Check Before Deletion:

| Field | Keep | Delete |
|-------|------|--------|
| face_photo_url | Latest | Older |
| face_embedding | Latest | Older |
| subjects | Latest | Older |
| year | Latest | Older |
| Attendance history | Keep in latest | Goes away |

**⚠️ WARNING:** Deleting a student record will:
- ❌ Delete all attendance records for that student
- ❌ Delete face photos and embeddings
- ❌ Remove from student management

**Safe approach:** Delete ONLY exact duplicates, not different versions

## Running the Cleanup

### Phase 1: Identify (SAFE - Read Only)

```sql
-- Run CHECK_DUPLICATE_STUDENTS.sql
-- This only READS data, no changes
-- Safe to run anytime
```

### Phase 2: Review (SAFE - Read Only)

```sql
-- Run IDENTIFY_DUPLICATE_TO_DELETE.sql
-- Shows which records to keep/delete
-- No changes made
```

### Phase 3: Backup (RECOMMENDED)

```sql
-- Create backup of duplicate records BEFORE deleting
CREATE TABLE students_duplicates_backup AS
SELECT * FROM public.students
WHERE id IN (
  -- List of IDs to delete (from Phase 2 output)
);
```

### Phase 4: Delete (ONE AT A TIME)

```sql
-- Delete ONE duplicate record
DELETE FROM public.students
WHERE id = 'specific-student-id';

-- Wait - Verify student still appears correctly in app
-- Then delete next duplicate
```

### Phase 5: Verify (IMPORTANT)

```sql
-- After each deletion, verify:
SELECT COUNT(*) FROM public.students
WHERE sr_no = '001' AND name = 'Bhushan Naikwade';
-- Should return 1, not 2+
```

## SQL Queries Explained

### Query 1: Find Duplicates by user_id
```sql
SELECT
  institute_id,
  user_id,
  name,
  COUNT(*) as duplicate_count,
  string_agg(DISTINCT subjects::text, ' | ') as subject_variations
FROM public.students
WHERE user_id IS NOT NULL AND user_id::text != ''
GROUP BY institute_id, user_id, name
HAVING COUNT(*) > 1
```

**Purpose:** Find students with same user_id and name (multiple records)

### Query 2: Find Duplicates by sr_no
```sql
SELECT
  institute_id,
  sr_no,
  name,
  COUNT(*) as duplicate_count,
  string_agg(DISTINCT subjects::text, ' | ') as subject_variations
FROM public.students
WHERE sr_no IS NOT NULL AND sr_no::text != ''
GROUP BY institute_id, sr_no, name
HAVING COUNT(*) > 1
```

**Purpose:** Find students with same sr_no and name (multiple records)

### Query 3: Show All Details
```sql
SELECT
  id,
  institute_id,
  sr_no,
  name,
  subjects,
  created_at
FROM public.students
WHERE (institute_id, sr_no, name) IN (
  -- Subquery returns all duplicate groups
)
ORDER BY institute_id, sr_no, name, created_at;
```

**Purpose:** Show all fields for each duplicate record

### Query 4: Keep vs Delete
```sql
ROW_NUMBER() OVER (
  PARTITION BY institute_id, sr_no, name
  ORDER BY created_at DESC
) as rn
```

**Purpose:** Number duplicates (1 = newest/keep, 2+ = older/delete)

## Real-World Example

### Before Cleanup:
```
Institute: 23101 (Prima)
──────────────────────────────────────
Record 1: ID=abc, SR=001, Name="Bhushan Naikwade", Subjects=[Math,Physics], Created=2024-01-01
Record 2: ID=def, SR=001, Name="Bhushan Naikwade", Subjects=[Chemistry], Created=2024-01-15 ← NEWEST
Record 3: ID=ghi, SR=001, Name="Bhushan Naikwade", Subjects=[Biology], Created=2024-01-10
```

### Decision:
- ✅ KEEP: Record 2 (newest - 2024-01-15)
- ❌ DELETE: Record 1 (oldest - 2024-01-01)
- ❌ DELETE: Record 3 (middle - 2024-01-10)

### After Cleanup:
```
Institute: 23101 (Prima)
──────────────────────────────────────
Record 2: ID=def, SR=001, Name="Bhushan Naikwade", Subjects=[Chemistry], Created=2024-01-15 ✅
```

## Warning Signs

⚠️ **High Duplicate Count indicates:**
- Data import issues
- Registration system not checking duplicates
- Manual data entry problems
- Student registering multiple times

## Best Practices After Cleanup

1. **Fix the root cause** - Why were duplicates created?
2. **Add database constraint** - Prevent duplicates
3. **Check registration flow** - Should reject if student exists
4. **Regular audits** - Check for new duplicates monthly
5. **User training** - Educate on proper registration

## Sample Output Format

### Duplicates Found:
```
Institute Code  | Duplicate Groups | Records to Delete
────────────────┼──────────────────┼─────────────────
23101           | 5                | 7
12345           | 2                | 3
67890           | 1                | 2
────────────────┼──────────────────┼─────────────────
TOTAL           | 8                | 12
```

## Affected Features if Duplicates Exist

❌ **Student Search** - May show duplicate results
❌ **Attendance Marking** - Confusion with 2 records
❌ **Face Recognition** - Multiple face embeddings
❌ **Attendance Reports** - Overcounting students
❌ **Performance** - Unnecessary database entries

## Testing After Cleanup

```sql
-- Verify no more duplicates
SELECT
  institute_id,
  sr_no,
  name,
  COUNT(*) as count
FROM public.students
GROUP BY institute_id, sr_no, name
HAVING COUNT(*) > 1;

-- Should return: (No rows)
```

## Support Commands

```sql
-- Count total students
SELECT COUNT(*) FROM public.students;

-- Count duplicates
SELECT COUNT(*) FROM duplicate_groups WHERE rn > 1;

-- List institutes with duplicates
SELECT DISTINCT institute_id FROM duplicate_groups WHERE rn > 1;

-- Check specific student
SELECT * FROM public.students
WHERE sr_no = '001' AND name = 'Bhushan Naikwade';
```

## Files Provided

1. **CHECK_DUPLICATE_STUDENTS.sql** - Identification queries
2. **IDENTIFY_DUPLICATE_TO_DELETE.sql** - Cleanup guidance
3. **DUPLICATE_STUDENTS_IDENTIFICATION_GUIDE.md** - This guide

## Summary

| Step | Action | Risk | Result |
|------|--------|------|--------|
| 1 | Run CHECK_DUPLICATE_STUDENTS.sql | None (read-only) | See all duplicates |
| 2 | Run IDENTIFY_DUPLICATE_TO_DELETE.sql | None (read-only) | Decide keep/delete |
| 3 | Create backup | Low | Safe restore point |
| 4 | Delete old records | Medium | Removes duplicates |
| 5 | Verify results | None (read-only) | Confirm cleanup |

**Status:** Ready to identify and cleanup duplicate student records ✅
