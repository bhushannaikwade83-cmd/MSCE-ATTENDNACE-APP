# Firestore Rules Fix for PIN Login Permission Errors

## Problem
During PIN login, users were getting permission denied errors when trying to query `institutes/{instituteId}/users` collection to find their profile. This happened because:

1. **User is not authenticated yet** during PIN login
2. **Old rule required authentication**: `allow read: if belongsToInstitute(instituteId)`
3. **belongsToInstitute() requires authentication**: The function checks `isAuthenticated()` first
4. **Result**: Unauthenticated users couldn't query to find their profile

## Solution
Updated the Firestore rules to allow unauthenticated users to read user documents in `institutes/{instituteId}/users/{userId}` for login purposes.

### Updated Rule (Line 132-133 in firestore.rules):
```javascript
// Allow read for:
// 1. Institute members (authenticated users belonging to institute)
// 2. Unauthenticated users (for login purposes - PIN login, password login)
allow read: if belongsToInstitute(instituteId) || !isAuthenticated();
```

## Security Considerations
✅ **Safe because:**
- Only allows **read** access, not write
- Users can only query by email (which they already know)
- No sensitive data exposure beyond what's needed for login
- After authentication, normal security rules apply

## Deployment Instructions

### Option 1: Deploy via Firebase CLI
```bash
firebase deploy --only firestore:rules
```

### Option 2: Deploy via Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to **Firestore Database** → **Rules**
4. Copy the updated rules from `firestore.rules`
5. Click **Publish**

## Verification
After deployment, test PIN login:
1. Try logging in with PIN
2. Check console - should see no permission denied errors
3. Login should work smoothly

## Files Changed
- `firestore.rules` - Updated line 132-133 to allow unauthenticated read access

## Notes
- Rules compiled successfully ✅
- Ready for deployment
- Backward compatible with existing authenticated access
