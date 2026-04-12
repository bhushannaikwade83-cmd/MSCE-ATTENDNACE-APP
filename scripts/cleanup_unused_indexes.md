# Cleanup Unused Firestore Indexes

## Analysis Results

Based on code analysis, here are the indexes that should be **DELETED**:

### ❌ DELETE THESE INDEXES:

1. **Index ID: `CICAgLjRyYIK`**
   - **Collection**: `inOut` (Collection group)
   - **Fields**: `instituteCode` (ASC), `date` (ASC), `name_` (DESC)
   - **Reason**: The `name_` field is NOT used in any query. We only query `instituteCode + date + type`.

2. **Index ID: `CICAgJjmnlgK`**
   - **Collection**: `inOut` (Collection scope - NOT Collection Group)
   - **Fields**: `studentId`, `instituteCode`, `name`
   - **Reason**: All our queries use **Collection Group**, not Collection scope. This index is for a different query pattern that we don't use.

3. **Index ID: `CICAgJjFZMK`**
   - **Collection**: `batches` (Collection scope)
   - **Fields**: `year`, `name`, `_name_`
   - **Reason**: The `_name_` field is auto-added by Firestore but NOT used in queries. We only need `year + name`.

### ✅ KEEP THESE INDEXES:

1. **Index ID: `CICAgLjy8IAK`** ✅
   - **Collection**: `inOut` (Collection group)
   - **Fields**: `instituteCode`, `studentId`, `_name_`
   - **Used by**: `student_photos_screen.dart`, `pdf_export_service.dart`

2. **Index ID: `CICAgJjFvYoK`** ✅
   - **Collection**: `inOut` (Collection group)
   - **Fields**: `instituteCode`, `date`, `type`, `_name_`
   - **Used by**: `admin_home_screen.dart`, `quick_stats_widget.dart`

3. **Index ID: `CICAgNjp84oK`** ✅
   - **Collection**: `inOut` (Collection group)
   - **Fields**: `instituteCode`, `studentId`, `date`, `_name_`
   - **Used by**: Future optimized queries and reports

## How to Delete

### Method 1: Firebase Console (Recommended)

1. Go to: https://console.firebase.google.com/project/smartattendanceapp-bc2fe/firestore/indexes
2. Find each unused index by looking at the "Fields indexed" column
3. Click the **three dots (⋮)** on the right side of each row
4. Click **"Delete"**
5. Confirm deletion

**Indexes to delete:**
- Row 3: `inOut` - `instituteCode, date, name_` (descending)
- Row 4: `inOut` Collection - `studentId, instituteCode, name`
- Row 1: `batches` - `year, name, _name_`

### Method 2: Update firestore.indexes.json

The current `firestore.indexes.json` only contains the indexes we need. Deploy it with `--force` to remove unused ones:

```bash
firebase deploy --only firestore:indexes --force
```

⚠️ **Warning**: This will delete ALL indexes not in the file. Make sure `firestore.indexes.json` has all the indexes you want to keep.

## Verification

After deletion, verify:
1. App still works without index errors
2. All queries execute successfully
3. No new index errors appear
