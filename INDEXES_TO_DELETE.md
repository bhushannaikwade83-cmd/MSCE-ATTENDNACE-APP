# 🗑️ Delete These 3 Unused Indexes

## Quick Reference

**Firebase Console**: https://console.firebase.google.com/project/smartattendanceapp-bc2fe/firestore/indexes

---

## ❌ DELETE THESE 3 INDEXES:

### 1. Index: `CICAgLjRyYIK`
- **Collection**: `inOut` (Collection group)
- **Fields**: `instituteCode` ↑, `date` ↑, `name_` ↓
- **Why Delete**: The `name_` field is NOT used in any query

### 2. Index: `CICAgJjmnlgK`  
- **Collection**: `inOut` (Collection scope - NOT Collection Group)
- **Fields**: `studentId`, `instituteCode`, `name`
- **Why Delete**: All queries use Collection Group, not Collection scope

### 3. Index: `CICAgJjFZMK`
- **Collection**: `batches` (Collection scope)
- **Fields**: `year`, `name`, `_name_`
- **Why Delete**: `_name_` is auto-added but not queried. Firestore handles `year + name` automatically.

---

## ✅ KEEP THESE 3 INDEXES:

1. `CICAgLjy8IAK` - `inOut` CG: `instituteCode`, `studentId`
2. `CICAgJjFvYoK` - `inOut` CG: `instituteCode`, `date`, `type`  
3. `CICAgNjp84oK` - `inOut` CG: `instituteCode`, `studentId`, `date`

---

## 📝 How to Delete:

1. Open Firebase Console link above
2. Find each index by looking at "Fields indexed" column
3. Click **three dots (⋮)** on the right
4. Click **"Delete"**
5. Confirm deletion

**Done!** ✅
