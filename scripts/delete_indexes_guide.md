# Quick Guide: Delete Unused Indexes

## 🎯 3 Indexes to Delete

Go to: **https://console.firebase.google.com/project/smartattendanceapp-bc2fe/firestore/indexes**

### Delete These:

1. **Row 3** - `inOut` Collection Group
   - Fields: `instituteCode` (↑), `date` (↑), `name_` (↓)
   - **Why**: `name_` field not used

2. **Row 4** - `inOut` Collection (NOT Collection Group)
   - Fields: `studentId`, `instituteCode`, `name`
   - **Why**: We use Collection Group, not Collection scope

3. **Row 1** - `batches` Collection
   - Fields: `year`, `name`, `_name_`
   - **Why**: `_name_` not needed, Firestore handles `year + name` automatically

### Keep These (3 indexes):

- ✅ `inOut` CG: `instituteCode`, `studentId`
- ✅ `inOut` CG: `instituteCode`, `date`, `type`
- ✅ `inOut` CG: `instituteCode`, `studentId`, `date`

## Steps:

1. Click **three dots (⋮)** on right side of each unused index
2. Click **"Delete"**
3. Confirm deletion
4. Done! ✅
