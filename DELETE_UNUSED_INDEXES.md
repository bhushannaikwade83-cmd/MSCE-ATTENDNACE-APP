# Delete Unused Firestore Indexes

## 📋 Summary

Based on code analysis, **3 indexes are NOT USED** and should be deleted:

### ❌ DELETE THESE INDEXES:

1. **Index ID: `CICAgLjRyYIK`**
   - **Collection**: `inOut` (Collection group)
   - **Fields**: `instituteCode` (ASC), `date` (ASC), `name_` (DESC)
   - **Why**: The `name_` field is NOT used in any query. We only query `instituteCode + date + type`.

2. **Index ID: `CICAgJjmnlgK`**
   - **Collection**: `inOut` (Collection scope - NOT Collection Group)
   - **Fields**: `studentId`, `instituteCode`, `name`
   - **Why**: All our queries use **Collection Group**, not Collection scope. This index is for a different query pattern.

3. **Index ID: `CICAgJjFZMK`**
   - **Collection**: `batches` (Collection scope)
   - **Fields**: `year`, `name`, `_name_`
   - **Why**: The `_name_` field is auto-added by Firestore but NOT used in queries. We only need `year + name` (which Firestore handles automatically).

### ✅ KEEP THESE INDEXES:

1. **Index ID: `CICAgLjy8IAK`** ✅
   - `inOut` Collection Group: `instituteCode`, `studentId`
   - Used by: `student_photos_screen.dart`, `pdf_export_service.dart`

2. **Index ID: `CICAgJjFvYoK`** ✅
   - `inOut` Collection Group: `instituteCode`, `date`, `type`
   - Used by: `admin_home_screen.dart`, `quick_stats_widget.dart`

3. **Index ID: `CICAgNjp84oK`** ✅
   - `inOut` Collection Group: `instituteCode`, `studentId`, `date`
   - Used by: Future optimized queries

## 🗑️ How to Delete

### Method 1: Firebase Console (Easiest)

1. **Open Firebase Console**:
   - Go to: https://console.firebase.google.com/project/smartattendanceapp-bc2fe/firestore/indexes

2. **Find and Delete Each Unused Index**:
   
   **Index 1: `CICAgLjRyYIK`**
   - Look for: `inOut` Collection Group with fields `instituteCode, date, name_` (note the descending `name_`)
   - Click the **three dots (⋮)** on the right
   - Click **"Delete"**
   - Confirm deletion

   **Index 2: `CICAgJjmnlgK`**
   - Look for: `inOut` Collection (NOT Collection Group) with fields `studentId, instituteCode, name`
   - Click the **three dots (⋮)** on the right
   - Click **"Delete"**
   - Confirm deletion

   **Index 3: `CICAgJjFZMK`**
   - Look for: `batches` Collection with fields `year, name, _name_`
   - Click the **three dots (⋮)** on the right
   - Click **"Delete"**
   - Confirm deletion

3. **Wait for Deletion** (usually instant)

### Method 2: Firebase CLI (Advanced)

Firebase CLI doesn't support direct index deletion. Use Method 1 (Console) instead.

## ✅ Verification

After deletion:
1. ✅ App should work without errors
2. ✅ All queries should execute successfully
3. ✅ No new index errors should appear

## 📝 Notes

- The `_name_` field in indexes is auto-added by Firestore for internal use
- Collection scope vs Collection Group: We use Collection Group for `inOut` queries
- The `batches` index with `_name_` is not needed - Firestore handles `year + name` automatically
