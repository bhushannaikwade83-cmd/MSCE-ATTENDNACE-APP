# Enable Single Field Index for Collection Group

## ⚠️ Problem
Firebase is **blocking** the composite index creation and saying to use "single field index controls" instead.

## ✅ Solution: Use Single Field Index Tab

### Step 1: Go to Single Field Indexes

1. In Firebase Console, go to: **Firestore → Indexes**
2. Click the **"Single field"** tab (at the top, next to "Composite")
3. You should see a list of collections and fields

### Step 2: Find or Add `inOut` Collection Group

1. Look for `inOut` in the list
2. If you see it:
   - Check if `instituteCode` field is listed
   - Check the "Query scope" column - it should show "Collection group"
   - If it's disabled or missing, click **"Enable"** or **"Add index"**

3. If you DON'T see `inOut`:
   - Click **"Add index"** button (top right)
   - Select:
     - **Collection ID**: `inOut`
     - **Query scope**: `Collection group` (IMPORTANT!)
     - **Field**: `instituteCode`
     - **Order**: `Ascending`
   - Click **"Create"**

### Step 3: Enable Collection Group Scope

**CRITICAL**: Make sure the query scope is set to **"Collection group"**, not just "Collection"!

- Collection scope = only for that specific collection path
- **Collection group scope** = for all collections with that ID across all paths (what you need!)

### Step 4: Wait for Build

- Status will show "Building" (⏳)
- Wait 2-5 minutes
- Status will change to "Enabled" (✅)

## 🔍 Visual Guide

In the Single Field tab, you should see:
```
Collection ID | Field        | Query scope        | Status
inOut         | instituteCode| Collection group   | Enabled ✅
```

## ⚠️ If Single Field Tab Doesn't Work

If you can't find the option in Single Field tab:

1. Try creating it via the **composite index** tab anyway
2. Or use Firebase CLI with fieldOverrides (advanced)

## 📋 Why This Happens

Firebase wants you to use single-field indexes for simple queries instead of composite indexes. But for collection groups, you must explicitly enable it with the correct scope.
