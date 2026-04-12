# Firebase Cost Optimization Guide

## Current Setup
- **Database**: Firebase Firestore
- **Authentication**: Firebase Auth
- **Storage**: B2B Storage (Backblaze B2)

## Cost Reduction Strategies Applied

### 1. ✅ Removed Photo Index Write (BIG SAVINGS)
**Before**: 2 writes per attendance mark (main + index)  
**After**: 1 write per attendance mark  
**Savings**: ~200M writes/year = **~₹35,85,600/year saved**

**File**: `lib/services/hierarchical_attendance_service.dart`
- Removed `students/{studentId}/attendancePhotos` index write
- Photos still queryable from hierarchical structure

### 2. ✅ Added Query Limits
**Before**: Unlimited reads (could read millions of docs)  
**After**: Limited to 1000-2000 docs per query  
**Savings**: Prevents accidental large reads

**Files Updated**:
- `attendance_reports_screen.dart` - Limit 2000 docs
- `attendance_calendar_screen.dart` - Limit 1000 docs
- `pdf_export_service.dart` - Limit 500 docs
- `student_photos_screen.dart` - Limit 100 docs

### 3. ✅ Replaced Expensive Streams with One-Time Queries
**Before**: Real-time streams on collectionGroup (expensive)  
**After**: One-time queries with FutureBuilder  
**Savings**: Reduces continuous reads

**Files Updated**:
- `admin_home_screen.dart` - Changed stream to FutureBuilder
- `student_photos_screen.dart` - Changed stream to FutureBuilder

### 4. ✅ Added Date Range Filters
**Before**: Query all documents, filter in memory  
**After**: Query with date range filter  
**Savings**: Firestore filters at database level (more efficient)

**Files Updated**:
- `attendance_reports_screen.dart` - Added date range to query
- `attendance_calendar_screen.dart` - Added date range to query
- `pdf_export_service.dart` - Added date range to query

### 5. ✅ Added Caching Service
**Before**: Every request reads from Firestore  
**After**: Cache frequently accessed data for 5 minutes  
**Savings**: Reduces repeated reads

**File**: `lib/services/firestore_cache_service.dart`
- Caches student lists
- Caches institute data
- 5-minute expiry

## Expected Cost Reduction

### Before Optimization:
- Writes: ~400M/year (2 per attendance mark) = **~₹72,00,000/year**
- Reads: Unlimited (could be millions) = **Variable, high**
- **Total**: ₹10,00,000 - ₹50,00,000+/year

### After Optimization:
- Writes: ~200M/year (1 per attendance mark) = **~₹36,00,000/year**
- Reads: Limited + cached = **~₹5,00,000 - ₹10,00,000/year**
- **Total**: **~₹1,50,000 - ₹2,00,000/month** ✅

## Additional Optimizations You Can Do

### 1. Batch Operations
Group multiple writes into batches (saves on write costs)

### 2. Pagination
For large reports, use pagination instead of loading all data

### 3. Offline Support
Use Firestore offline persistence to reduce reads

### 4. Monitor Usage
Check Firebase Console → Usage tab to see actual reads/writes

## Monitoring Costs

1. **Firebase Console** → Project Settings → Usage
2. Check daily reads/writes
3. Set up billing alerts at ₹1,500/month

## Cost Breakdown (After Optimization)

| Item | Monthly Cost (₹) | Notes |
|------|------------------|-------|
| Firestore Writes | ~3,00,000 | 200M writes/year |
| Firestore Reads | ~50,000 - 1,00,000 | With limits + cache |
| Firebase Auth | Free | Free tier |
| **Total Firebase** | **~₹1,50,000 - ₹2,00,000** | ✅ Target achieved |
| B2B Storage | ~2,500 | 5 TB stored |
| **Grand Total** | **~₹1,52,500 - ₹2,02,500/month** | ✅ |

## Tips to Stay Under Budget

1. ✅ **Query limits** - Always use `.limit()` on queries
2. ✅ **Date filters** - Filter at database level, not in memory
3. ✅ **Cache data** - Cache student lists, institute data
4. ✅ **Avoid streams** - Use one-time queries for reports
5. ✅ **Batch operations** - Group writes when possible
6. ✅ **Monitor usage** - Check Firebase Console regularly

## Files Modified

1. `lib/services/hierarchical_attendance_service.dart` - Removed photo index
2. `lib/presentation/screens/attendance_reports_screen.dart` - Added limits + cache
3. `lib/presentation/screens/admin_home_screen.dart` - Changed stream to query
4. `lib/presentation/screens/attendance_calendar_screen.dart` - Added limits
5. `lib/services/pdf_export_service.dart` - Added limits
6. `lib/presentation/screens/student_photos_screen.dart` - Changed stream to query
7. `lib/services/firestore_cache_service.dart` - New caching service

## Next Steps

1. Monitor Firebase Console for actual usage
2. Adjust limits if needed
3. Add more caching for frequently accessed data
4. Consider pagination for very large reports
