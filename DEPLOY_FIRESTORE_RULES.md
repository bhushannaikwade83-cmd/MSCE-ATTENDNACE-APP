# Deploy Firestore Rules to Fix Permission Denied Error

## ⚠️ Current Issue
The hierarchical attendance structure is getting `PERMISSION_DENIED` errors when trying to save attendance.

## ✅ Solution
The Firestore rules have been updated to allow authenticated admins to write attendance. **You need to deploy these rules to Firestore.**

## 📋 Deployment Steps

### Option 1: Firebase Console (Easiest)
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to **Firestore Database** → **Rules** tab
4. Copy the contents of `firestore.rules` file
5. Paste into the rules editor
6. Click **Publish**

### Option 2: Firebase CLI
```bash
# Install Firebase CLI if not installed
npm install -g firebase-tools

# Login to Firebase
firebase login

# Deploy rules
firebase deploy --only firestore:rules
```

## 🔍 What Changed

The rules now allow:
- ✅ Any authenticated admin to read/write attendance in hierarchical structure
- ✅ Users in `institutes/{instituteCode}/users/{uid}` 
- ✅ Users in old `users/{uid}` structure with `role == 'admin'`
- ✅ Super admins (platform admins)

## 🧪 Testing After Deployment

After deploying, try marking attendance again. The permission error should be resolved.

## 📝 Note

If you still get permission errors after deployment:
1. Check that the user document exists in `users/{uid}` collection
2. Verify the user has `role == 'admin'` in their document
3. Check Firebase Console → Firestore → Rules for any syntax errors
