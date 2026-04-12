# Firestore Rules for Hierarchical Attendance Structure

## ✅ Status
- **Rules added successfully** ✅
- **Ready for deployment** ✅

## Hierarchical Structure

The attendance data is now stored in a hierarchical structure:
```
year/{year}/semester/{semester}/instituteCode/{code}/students/{studentId}/attendance/{date}/inOut/{type}
```

Where:
- `year`: The year (e.g., "2026")
- `semester`: Semester code (e.g., "1-2026" for Jan-Jun 2026)
- `instituteCode`: The institute code (same as instituteId)
- `studentId`: The student document ID
- `date`: Date in format "YYYY-MM-DD"
- `type`: Either "entry" or "exit"

## Security Rules

### Access Control
- **Read**: Authenticated users who belong to the institute OR super admins
- **Write (Create/Update)**: Authenticated users who belong to the institute OR super admins
  - Type must be 'entry' or 'exit'
- **Delete**: Only super admins (for data correction)

### Helper Function
The rules use `belongsToInstituteByCode()` which checks:
1. If user exists in `institutes/{instituteCode}/users/{uid}`
2. If user exists in old structure `users/{uid}` with matching `instituteId` or `instituteCode`

## Indexes

### Current Queries Analysis
After analyzing the code, the following queries are used:

1. **Direct Document Access**: Most queries access documents directly by path - **NO INDEX NEEDED**
2. **Collection Queries**: Getting all documents from a collection - **NO INDEX NEEDED**
3. **Super Admin View**: Uses `orderBy('date', descending: true)` on `inOut` collection

### Required Index (if needed)
If you encounter an error about missing index when using Super Admin view, create this index:

**Collection Group**: `inOut`
**Fields**:
- `date` (Descending)

**Note**: This index may not be needed if the query is scoped to a specific student's attendance collection, as Firestore automatically creates single-field indexes.

## Deployment

### Option 1: Firebase Console (Recommended)
1. Go to: https://console.firebase.google.com
2. Select your project
3. Navigate to **Firestore Database** → **Rules**
4. Copy content from `firestore.rules`
5. Paste and click **Publish**

### Option 2: Firebase CLI
```bash
firebase deploy --only firestore:rules
```

### Option 3: Deploy Indexes (if needed)
```bash
firebase deploy --only firestore:indexes
```

## Testing

After deployment, test the following:
1. ✅ Admin can mark attendance (entry/exit)
2. ✅ Admin can view attendance in Student Management screen
3. ✅ Super Admin can view all attendance in Super Admin view
4. ✅ Students cannot access attendance data
5. ✅ Unauthenticated users cannot access attendance data

## Troubleshooting

If you get permission denied errors:
1. Check that the user is authenticated
2. Check that the user belongs to the institute (exists in `institutes/{instituteCode}/users/{uid}`)
3. Check that `instituteCode` matches the user's institute
4. Verify the rules were deployed correctly
