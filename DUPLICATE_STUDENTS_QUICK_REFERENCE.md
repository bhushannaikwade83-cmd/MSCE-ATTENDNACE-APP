# Duplicate Students - Quick Reference Guide

## What We're Looking For

**Students who registered TWICE:**
```
Student: "Bhushan Naikwade"
Institute: 23101 (Prima)
SR NO: 001

Registration 1: Created 2024-01-01
  Subjects: [Math, Physics]

Registration 2: Created 2024-01-15  ← Same student, different subjects!
  Subjects: [Chemistry, Biology]

Result: 2 DUPLICATE RECORDS for same student
```

## The 8 SQL Queries

### Query 1: Summary View
**Best for:** Quick overview
**Shows:** 
- Institute code
- Student name
- How many times registered
- All subjects across registrations
- Days between registrations

**Example output:**
```
Institute | SR NO | Student Name    | Registrations | All Subjects
23101     | 001   | Bhushan Naikwade | 2            | Chemistry,Math,Physics,Biology
23101     | 005   | Rahul Sharma     | 3            | Science,Biology,Physics
```

### Query 2: Detailed Records
**Best for:** See each registration separately
**Shows:**
- Each registration as separate row
- Subjects for each registration
- Photo status
- Face embedding status
- When registered

**Example output:**
```
Institute | Name              | Record ID  | Subjects              | Registered At | Photo
23101     | Bhushan Naikwade  | abc123     | [Math,Physics]        | 2024-01-01    | NO
23101     | Bhushan Naikwade  | def456     | [Chemistry,Biology]   | 2024-01-15    | YES ← Newer
```

### Query 3: Summary by Institute
**Best for:** Which institutes have duplicates?
**Shows:**
- Institute code
- How many students have duplicates
- Total extra registrations to remove

**Example output:**
```
Institute | Students with Duplicates | Extra Registrations
23101     | 5                        | 7
12345     | 2                        | 2
67890     | 1                        | 1
```

### Query 4: Specific Student Search
**Best for:** Check one student
**How to use:**
```sql
-- Uncomment and change name/institute code
SELECT * FROM public.students
WHERE s.name ILIKE '%bhushan%'
AND s.institute_id = (SELECT id FROM public.institutes WHERE institute_code = '23101')
ORDER BY s.created_at;
```

### Query 5: Data Quality Issues
**Best for:** Find confusing data
**Shows:**
- Students with different subjects across registrations
- Students with different years
- Severity of duplication

### Query 6: Which to KEEP
**Best for:** Decide best record to keep
**Rule:** Keep record with:
- ✅ Photo attached (if available)
- ✅ Otherwise, newest record

**Example output:**
```
Action | Institute | Name              | Record ID | Registered | Photo Status
KEEP   | 23101     | Bhushan Naikwade  | def456    | 2024-01-15 | HAS PHOTO
KEEP   | 23101     | Rahul Sharma      | xyz789    | 2024-01-20 | HAS PHOTO
```

### Query 7: Which to DELETE
**Best for:** Generate deletion list
**Shows:**
- Records to DELETE
- DELETE SQL statement ready to use

**Example output:**
```
Action | Name              | Record ID | Delete Command
DELETE | Bhushan Naikwade  | abc123    | DELETE FROM public.students WHERE id = 'abc123';
DELETE | Rahul Sharma      | old111    | DELETE FROM public.students WHERE id = 'old111';
```

### Query 8: Final Count
**Best for:** See total impact
**Shows:**
- Total students with duplicates
- Total records to delete

## How to Use (Step by Step)

### Step 1: Run Query 1 (Overview)
```
See which students registered twice
```

### Step 2: Run Query 3 (By Institute)
```
Which institutes are affected most?
```

### Step 3: Run Query 2 (Detailed)
```
See each registration separately
For the student you want to clean up
```

### Step 4: Run Query 6 (Keep)
```
Confirm which record to KEEP
```

### Step 5: Run Query 7 (Delete)
```
Get the DELETE statement
Review it carefully
```

### Step 6: Delete One Record
```
Execute ONE DELETE statement
Test in app
Then delete next one
```

### Step 7: Verify with Query 8
```
Check final count
Should show reduction
```

## Decision Logic

### If Student Has:
- **1 registration** → No action needed ✅
- **2+ registrations** → MERGE into best one

### Best Record = Keep:
1. **Has face photo** (if available)
2. **Newest registration** (most recent)
3. **Complete data** (has subjects, year)

### Older Records = Delete:
1. Remove all older duplicates
2. Keep only the best one

## Example Decision

```
Student: Bhushan Naikwade, SR 001, Institute 23101

Record 1: 2024-01-01, Subjects: [Math, Physics], NO PHOTO
Record 2: 2024-01-10, Subjects: [Physics], NO PHOTO
Record 3: 2024-01-15, Subjects: [Chemistry, Biology], HAS PHOTO ← BEST!

Decision:
  KEEP: Record 3 (has photo, newest)
  DELETE: Record 1 and Record 2
```

## Safety Checklist

Before deleting:
- [ ] Backup old records (create_table_duplicates_backup AS...)
- [ ] Verify correct record to keep
- [ ] Check if photo exists
- [ ] Check if face_embedding exists
- [ ] Review attendance history (to avoid loss)
- [ ] Test deletion on one record first

## What Gets Lost When Deleted

⚠️ **Cannot be recovered:**
- ❌ Student record
- ❌ All face photos
- ❌ Face embeddings
- ❌ Attendance history for that record
- ❌ Assignment history

✅ **Kept (in newer record):**
- ✅ Student name
- ✅ SR NO
- ✅ Latest subjects
- ✅ Newer photo/face
- ✅ Attendance on newer record

## Important Notes

### Why Keep Newest?
- Most recent subject assignments
- Latest photo quality
- Latest face embedding
- Newest registration info

### Why Older = Duplicate?
- Student entered twice by mistake
- Old registration + new registration
- Only newest one matters

### Data Merge?
- Don't merge manually
- Keep newest record (it's the real one)
- Delete old ones (they were mistakes)

## Real-World Scenario

```
Scenario: Student Bhushan registered on wrong date, re-registered

2024-01-01: Student fills form (subjects: [Math, Physics])
  ↓ Form submission fails or incomplete
2024-01-15: Student re-registers (subjects: [Chemistry, Biology])
  ↓
Result: 2 records for same student!

Solution:
  Keep: 2024-01-15 record (correct one, has photo)
  Delete: 2024-01-01 record (failed attempt)
```

## Common Issues

### Issue 1: No Photo on Newer Record
**Keep anyway** - It's newer and more correct

### Issue 2: Face Embedding Missing
**Still keep newer** - Photo can be re-captured

### Issue 3: Multiple Records with Different Years
**Keep newest year** - It's the current year

### Issue 4: Uncertainty About Which to Delete
**Always keep newest** - Can't go wrong

## After Cleanup

### Verify:
```sql
SELECT sr_no, name, COUNT(*)
FROM public.students
WHERE institute_id = 'xyz'
GROUP BY sr_no, name
HAVING COUNT(*) > 1;
-- Should return: (No rows)
```

### Check App:
- [ ] Search student - shows only 1 result
- [ ] Mark attendance - works fine
- [ ] Student list - no duplicates
- [ ] Face recognition - works

## Query File Usage

**Run in order:**
1. `Query 1` - Overview
2. `Query 3` - Which institutes affected
3. `Query 2` - See each record
4. `Query 6` - Confirm which to keep
5. `Query 7` - Get delete statements
6. **DELETE ONE AT A TIME**
7. `Query 8` - Verify final count

## Summary

✅ Find students who registered twice
✅ Keep the newest record (with photo if available)
✅ Delete all older duplicates
✅ Verify cleanup worked
✅ Test in app

**File:** `FIND_STUDENTS_REGISTERED_TWICE.sql`
**Status:** Ready to use
