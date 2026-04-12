# Firestore Auto-Initialization Guide

This app automatically initializes Firestore collections and provides easy index creation.

## 🚀 Automatic Collection Initialization

The app automatically creates all required collections on startup:
- `institutes`
- `users`
- `students`
- `batches`
- `subjects`
- `attendance`
- `year` (for hierarchical attendance)

**No action needed** - collections are created automatically when the app starts.

## 📋 Firestore Indexes Setup

### Option 1: Automatic via Firebase Console (Easiest)

1. When you see an index error, click the link in the error message
2. Firebase Console will open with the index creation dialog
3. Click "Create Index"
4. Wait 2-5 minutes for the index to be ready

### Option 2: Deploy via Firebase CLI (Recommended for Production)

1. **Install Firebase CLI** (if not already installed):
   ```bash
   npm install -g firebase-tools
   ```

2. **Login to Firebase**:
   ```bash
   firebase login
   ```

3. **Initialize Firebase in your project** (if not done):
   ```bash
   firebase init firestore
   ```

4. **Deploy indexes**:
   ```bash
   # On Windows
   scripts\deploy_indexes.bat
   
   # On Mac/Linux
   bash scripts/deploy_indexes.sh
   
   # Or manually
   firebase deploy --only firestore:indexes
   ```

5. **Wait for indexes to be created** (2-5 minutes)
   - Check status: https://console.firebase.google.com/project/_/firestore/indexes

### Option 3: Manual Creation

1. Go to Firebase Console → Firestore → Indexes
2. Click "Create Index"
3. Use these settings:

**Index 1:**
- Collection ID: `inOut` (Collection Group)
- Fields:
  - `instituteCode` (Ascending)

**Index 2:**
- Collection ID: `inOut` (Collection Group)
- Fields:
  - `instituteCode` (Ascending)
  - `date` (Ascending)

**Index 3:**
- Collection ID: `inOut` (Collection Group)
- Fields:
  - `instituteCode` (Ascending)
  - `studentId` (Ascending)

**Index 4:**
- Collection ID: `inOut` (Collection Group)
- Fields:
  - `instituteCode` (Ascending)
  - `date` (Ascending)
  - `type` (Ascending)

**Index 5:**
- Collection ID: `inOut` (Collection Group)
- Fields:
  - `instituteCode` (Ascending)
  - `studentId` (Ascending)
  - `date` (Ascending)

## ✅ Verification

After indexes are created, you should see them in:
- Firebase Console → Firestore → Indexes tab
- Status should be "Enabled" (green)

## 🔄 After Clearing Database

If you clear the database:

1. **Collections**: Will be auto-created on next app startup
2. **Indexes**: Need to be recreated (use Option 1, 2, or 3 above)

## 📝 Files

- `lib/services/firestore_init_service.dart` - Auto-initialization service
- `firestore.indexes.json` - Index definitions for Firebase CLI
- `scripts/deploy_indexes.sh` - Auto-deploy script (Mac/Linux)
- `scripts/deploy_indexes.bat` - Auto-deploy script (Windows)
- `scripts/create_firestore_indexes.js` - Node.js script for index creation

## 🆘 Troubleshooting

**Error: "Index not found"**
- Wait a few more minutes for index to be created
- Check Firebase Console → Firestore → Indexes

**Error: "Permission denied"**
- Make sure you're logged in to Firebase CLI
- Check Firebase project permissions

**Collections not created:**
- Check Firebase Console → Firestore → Data
- Collections are created on first document write

## 💡 Pro Tips

1. **Deploy indexes before production** - Use Firebase CLI to deploy all indexes at once
2. **Monitor index usage** - Check Firebase Console for index performance
3. **Auto-deploy on CI/CD** - Add `firebase deploy --only firestore:indexes` to your deployment pipeline
