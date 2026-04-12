# Create Single-Field Index for Collection Group

## ⚠️ Important

The query `.collectionGroup('inOut').where('instituteCode', isEqualTo: ...)` **REQUIRES** an index, even though it's a single-field query.

Firebase CLI says "this index is not necessary" but that's incorrect for collection group queries. You need to create it **manually via Firebase Console**.

## 🔧 How to Create the Index

### Step 1: Get the Index Creation Link

When you see the "Firestore index required" error in the app:
1. Click the **"Create Index"** button in the error message
2. This will open Firebase Console with the index pre-configured

### Step 2: Or Create Manually

1. Go to: https://console.firebase.google.com/project/msce-attendace-app/firestore/indexes
2. Click **"Add index"** button (top right)
3. Configure:
   - **Collection ID**: `inOut` (select "Collection group")
   - **Fields to index**:
     - Field: `instituteCode`
     - Order: `Ascending`
4. Click **"Create"**
5. Wait 2-5 minutes for index to build

## ✅ After Index is Created

- Status will show "Enabled" (green checkmark)
- The attendance reports screen will work without errors
- No more "Firestore index required" messages

## 📋 Why This Index is Needed

Collection group queries (`collectionGroup()`) with `where()` clauses **always** require an index, even for single-field equality queries. This is different from regular collection queries where single-field indexes are automatic.

## 🔍 Verify Index Exists

After creating, you should see in Firebase Console:
- Collection Group: `inOut`
- Fields: `instituteCode` (Ascending)
- Status: **Enabled** ✅
