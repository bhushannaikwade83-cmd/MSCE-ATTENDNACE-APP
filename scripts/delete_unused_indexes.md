# Delete Unused Firestore Indexes

## Analysis of Indexes

Based on code analysis, here are the indexes that are **NOT USED** and should be deleted:

### ❌ UNUSED INDEXES TO DELETE:

1. **Index ID: `CICAgLjRyYIK`**
   - Collection: `inOut` (Collection group)
   - Fields: `instituteCode` (ASC), `date` (ASC), `name_` (DESC)
   - **Reason**: The `name_` field is not used in any query. We only query `instituteCode + date + type`.

2. **Index ID: `CICAgJjmnlgK`**
   - Collection: `inOut` (Collection scope - NOT Collection Group)
   - Fields: `studentId`, `instituteCode`, `name`
   - **Reason**: All our queries use **Collection Group**, not Collection scope. This index is for a different query pattern.

3. **Index ID: `CICAgJjFZMK` (batches)**
   - Collection: `batches` (Collection scope)
   - Fields: `year`, `name`, `_name_`
   - **Reason**: The `_name_` field is auto-added by Firestore but not used in queries. We only need `year + name`.

### ✅ KEEP THESE INDEXES:

1. **Index ID: `CICAgLjy8IAK`**
   - Collection: `inOut` (Collection group)
   - Fields: `instituteCode`, `studentId`, `_name_`
   - **Used by**: `student_photos_screen.dart`, `pdf_export_service.dart`

2. **Index ID: `CICAgJjFvYoK`**
   - Collection: `inOut` (Collection group)
   - Fields: `instituteCode`, `date`, `type`, `_name_`
   - **Used by**: `admin_home_screen.dart`, `quick_stats_widget.dart`

3. **Index ID: `CICAgNjp84oK`**
   - Collection: `inOut` (Collection group)
   - Fields: `instituteCode`, `studentId`, `date`, `_name_`
   - **Used by**: Future queries and optimized reports

## How to Delete Unused Indexes

### Option 1: Via Firebase Console (Easiest)

1. Go to: https://console.firebase.google.com/project/smartattendanceapp-bc2fe/firestore/indexes
2. Find each unused index by Index ID
3. Click the three dots (⋮) on the right
4. Click "Delete"
5. Confirm deletion

### Option 2: Via Firebase CLI

```bash
# Delete specific index by ID
firebase firestore:indexes:delete CICAgLjRyYIK
firebase firestore:indexes:delete CICAgJjmnlgK
firebase firestore:indexes:delete CICAgJjFZMK
```

### Option 3: Update firestore.indexes.json and Deploy

Remove unused indexes from `firestore.indexes.json` and deploy:
```bash
firebase deploy --only firestore:indexes --force
```

## ⚠️ WARNING

- **DO NOT DELETE** indexes that are currently being used
- Wait for indexes to finish building before deleting
- Test your app after deletion to ensure no errors
