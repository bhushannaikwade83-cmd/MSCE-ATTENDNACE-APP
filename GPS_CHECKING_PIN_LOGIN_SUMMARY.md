# GPS Checking During PIN Login - Implementation Summary

## Status: ✅ FULLY IMPLEMENTED

GPS validation is **automatically checked** after every PIN login for attendance staff/instructors.

## How It Works

### PIN Login Flow with GPS Validation

```
User enters Institute Code + PIN
           ↓
    signInAttendanceStaff()
    (validates PIN)
           ↓
    PIN is VALID
           ↓
   attendanceLocationGateForCurrentUser()
   (checks GPS location)
           ↓
   ├─ WITHIN 15m radius → Access granted ✅
   └─ OUTSIDE radius → Show location gate screen ❌
```

### File: `lib/presentation/screens/attendance_staff_login_screen.dart`

**Lines 85-156: Complete flow**

```dart
Future<void> _submit() async {
  // Step 1: Validate PIN
  final res = await _auth.signInAttendanceStaff(
    instituteKey: _instituteCtrl.text.trim(),
    pin: _pinCtrl.text.trim(),
  );
  
  if (res['success'] != true) {
    // PIN validation failed
    return;
  }

  // Step 2: Check GPS location in parallel with caching
  final gateFuture = GeofenceService().attendanceLocationGateForCurrentUser(
    fastFenceSampleForLogin: true,  // Fast sample for login
  );

  // Step 3: Process result
  final gate = done[1] as Map<String, dynamic>;
  
  if (gate['allowed'] != true) {
    // User is OUTSIDE the geofence
    Navigator.pushNamedAndRemoveUntil(
      InstituteLocationGateScreen.routeName,  // Show gate screen
      arguments: {'resumeRoute': StaffAttendancePortalScreen.routeName},
    );
    return;
  }

  // Step 4: GPS is VALID - proceed to staff portal
  Navigator.pushNamedAndRemoveUntil(
    StaffAttendancePortalScreen.routeName,
  );
}
```

## GPS Validation Details

### Service: `lib/services/geofence_service.dart`

**Method:** `attendanceLocationGateForCurrentUser()`

#### What It Checks:

1. **Profile exists** - User profile linked to an institute
2. **Institute has GPS lock** - Admin has locked the geofence
3. **Location permission** - GPS is enabled and accessible
4. **Fake GPS detection** - Rejects mock location apps
5. **Distance calculation** - Checks distance from locked point
6. **Radius validation** - Compares distance against 15-meter radius

#### Geofence Radius:
- **Constant:** `kAttendanceFenceRadiusMeters = 15.0` meters
- **File:** `lib/core/gps_attendance_constants.dart`

### Return Values:

```dart
{
  'allowed': true/false,        // Access granted or blocked
  'message': 'String',          // User message (Hindi + English)
  'distance': 123.45,           // Distance in meters from locked point
  'isLocked': true/false,       // Is geofence locked
  'hasLocation': true/false,    // Does institute have GPS point
  'isWithinRadius': true/false  // Is user within 15m radius
}
```

## User Messages

### When GPS is Valid ✅
- User can access Staff Attendance Portal immediately
- No additional screen shown

### When GPS is Invalid ❌
**Screen:** `InstituteLocationGateScreen`

**Message:**
```
"Out of radius: you are about XXX m from the institute's locked attendance point. 
Move within about 15 m at your institute premises. 
All features are blocked until you are inside the zone."

(With Marathi translation)
```

**Actions:**
- Check location again button
- Sign out button

## Technical Flow Diagram

```
attendance_staff_login_screen.dart
         ↓
    PIN VALIDATION
         ↓
    signInAttendanceStaff() ← auth_service.dart
         ↓ (if success)
    GPS LOCATION CHECK
         ↓
    attendanceLocationGateForCurrentUser() ← geofence_service.dart
         ↓
    checkAdminLocationStatus() ← geofence_service.dart
         ↓
    Geolocator.getCurrentPosition() ← geolocator package
         ↓
    Geolocator.distanceBetween() ← haversine distance calculation
         ↓
    Compare distance against 15m radius
         ↓
    Return 'allowed' true/false
         ↓
    ├─ allowed=true  → Navigate to StaffAttendancePortalScreen
    └─ allowed=false → Navigate to InstituteLocationGateScreen
```

## GPS Detection Features

### Fake GPS Detection ✅
Rejects mock location apps with message:
```
"Cannot unlock: Fake GPS detected. Please turn off Mock Location apps."
```

### Location Services Check ✅
- High accuracy GPS enabled
- Location permissions granted
- GPS working properly

### Distance Calculation ✅
Uses Haversine formula:
```dart
Geolocator.distanceBetween(
  userLat, userLng,
  lockedLat, lockedLng
)
```

## Database Tables Used

1. **gps_settings** - Admin's locked GPS point
   - `latitude`, `longitude` - Locked coordinates
   - `is_locked` - Whether geofence is active
   - `locked_at`, `unlocked_at` - Timestamps

2. **profiles** - User profile
   - `institute_id` - User's institute
   - `role` - User role (admin, attendance_user)

## Configuration

**Geofence Radius:** 15 meters (fixed in `gps_attendance_constants.dart`)

To change radius:
```dart
// In gps_attendance_constants.dart
const double kAttendanceFenceRadiusMeters = 15.0;  // Change this value
```

## Testing GPS Checking

### Scenario 1: Valid Login with GPS Inside Zone
1. Open attendance staff login
2. Enter valid institute code + PIN
3. Device GPS is within 15m of locked point
4. Result: Access granted to staff portal ✅

### Scenario 2: Valid PIN but GPS Outside Zone
1. Open attendance staff login
2. Enter valid institute code + PIN
3. Device GPS is > 15m from locked point
4. Result: Shows location gate screen (message + distance) ❌

### Scenario 3: Fake GPS Detected
1. Mock Location app enabled on Android
2. Try to login with PIN
3. Result: "Fake GPS detected" error ❌

## Production Status

✅ **Fully tested and working**
- GPS validation active after PIN login
- Geofence enforcement working
- Fake GPS detection active
- Distance calculations accurate

## Related Screens

- `attendance_staff_login_screen.dart` - PIN login
- `institute_location_gate_screen.dart` - GPS restriction screen
- `staff_attendance_portal_screen.dart` - Destination after GPS clearance

## Notes

- GPS check happens **after** PIN validation
- GPS is checked on **every** PIN login
- Admin must first lock geofence via GPS Settings
- If geofence not locked, error: "Attendance zone unavailable"
- Student login does NOT require GPS (only staff/instructors)
- Web version skips GPS check (returns allowed=true automatically)
