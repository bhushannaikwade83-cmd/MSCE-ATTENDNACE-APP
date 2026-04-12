# How to Create the Required Index

## ⚠️ You're Seeing This Warning:
> "this index is not necessary, configure using single field index controls"

## ✅ Solution: Create It Anyway!

**Despite the warning, you should proceed with creating the index.** Here's why:

1. **Collection group queries ALWAYS need explicit indexes** - even for single fields
2. The warning is Firebase's suggestion, but it's not a blocker
3. Your query `.collectionGroup('inOut').where('instituteCode', ...)` **REQUIRES** this index

## 📋 Steps to Create:

### In the Dialog You're Seeing:

1. **Collection ID**: `inOut` ✅ (already set)
2. **Query scope**: `Collection group` ✅ (already set)
3. **Fields to index**:
   - Field 1: `instituteCode` ✅ (already set)
   - Order: `Ascending` ✅ (already set)
4. **Click "Create"** (ignore the warning)

### After Creating:

- Status will show "Building" (⏳)
- Wait **2-5 minutes**
- Status will change to "Enabled" (✅)
- Your app will work without errors!

## 🔍 Alternative: Single Field Tab (If Available)

If you want to follow Firebase's suggestion:

1. Go to Firebase Console → Firestore → Indexes
2. Click **"Single field"** tab
3. Look for `inOut` collection group
4. Enable `instituteCode` with "Collection group" scope
5. Click "Enable"

## ✅ Either Way Works!

Both methods will create the same index. The warning is just Firebase's preference, but **you need the index either way** for collection group queries to work.

## 🎯 Bottom Line

**Click "Create" in the dialog** - the warning won't prevent the index from working!
