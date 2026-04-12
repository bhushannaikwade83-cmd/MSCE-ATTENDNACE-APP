# App Architecture

## Current Setup

### Database: Firebase Firestore
- ✅ Stores all attendance records
- ✅ Stores student data
- ✅ Stores institute data
- ✅ Real-time updates with streams
- ✅ Hierarchical structure for efficient queries

### Authentication: Firebase Auth
- ✅ User login/logout
- ✅ Role-based access (admin, student, etc.)
- ✅ Secure token management

### Storage: B2B Storage (Backblaze B2)
- ✅ Photo storage (attendance photos)
- ✅ Thumbnail generation
- ✅ Cost-effective storage
- ✅ Auto-delete after 6 months

## Architecture Overview

```
┌─────────────────┐
│  Flutter App    │
│  (Mobile/Web)   │
└────────┬────────┘
         │
         ├─────────────────┐
         │                 │
         ▼                 ▼
┌─────────────────┐  ┌──────────────┐
│  Firebase       │  │  B2B Storage │
│  - Firestore    │  │  (Backblaze) │
│  - Auth         │  │  - Photos    │
└─────────────────┘  └──────────────┘
```

## Services

### Firebase Services
- `HierarchicalAttendanceService` - Attendance operations
- `BatchService` - Batch management
- `StudentService` - Student operations
- `InstituteStatusService` - Daily status (open/close/holiday)

### Storage Services
- `B2BStorageService` - Photo upload/download to Backblaze B2
- `StorageService` - Wrapper for B2B storage

## Data Flow

### Marking Attendance:
1. User takes photo in Flutter app
2. Photo uploaded to **B2B Storage** (Backblaze B2)
3. Photo URL saved to **Firebase Firestore**
4. Attendance record created in **Firebase Firestore**

### Viewing Photos:
1. App requests photo from **B2B Storage**
2. B2B returns signed URL (valid for 5 minutes)
3. App displays photo using URL

### Reports:
1. App queries **Firebase Firestore** for attendance data
2. App fetches photos from **B2B Storage** as needed
3. Data displayed in app

## Cost Breakdown

- **Firebase Firestore**: Pay per read/write (scales with usage)
- **Firebase Auth**: Free tier available
- **B2B Storage**: ~₹500/TB-month = ~₹30,000/year for 5 TB

## Benefits

✅ **Firebase**: Fast, real-time, managed database  
✅ **B2B Storage**: Cheap photo storage (10x cheaper than Firebase Storage)  
✅ **No Backend Server**: Direct client-to-service communication  
✅ **Scalable**: Handles 4 lakh students efficiently

## File Structure

```
lib/
├── services/
│   ├── hierarchical_attendance_service.dart  # Firebase attendance
│   ├── b2b_storage_service.dart              # B2B photo storage
│   ├── storage_service.dart                  # Storage wrapper
│   └── ... (other Firebase services)
└── presentation/
    └── screens/                              # All app screens
```

## Configuration

### B2B Storage Config
- File: `lib/config/b2b_storage_config.dart`
- Contains: Bucket name, credentials, endpoints

### Firebase Config
- File: `lib/firebase_options.dart` (auto-generated)
- Contains: Firebase project credentials

## Maintenance

### Photo Cleanup
- Photos auto-delete after 6 months
- Handled by B2B Storage lifecycle policies or manual cleanup

### Database Optimization
- Firebase indexes configured for fast queries
- Hierarchical structure for efficient data access
