# GPS Validation Fix - Entry & Exit Photos

## Current Issue
- GPS radius check happens only ONCE at the start of attendance marking (`_checkGPSRadius()`)
- Does NOT re-validate GPS when actual entry or exit photos are submitted
- Students/admin can move outside radius AFTER initial check and still mark attendance ❌

## What Should Happen
1. **Entry Photo** → Validate GPS is within radius BEFORE saving entry photo
2. **Exit Photo** → Validate GPS is within radius BEFORE saving exit photo
3. If location is OUTSIDE radius → **BLOCK attendance** ❌

## Current Code Location
File: `lib/presentation/screens/admin_attendance_screen.dart`

**Current Flow:**
```
Line 739: _checkGPSRadius() called ONCE when marking starts
         ↓
         If GPS is within radius, allow marking
         ↓
Line 118: saveAttendance() saves the photo
         (NO GPS re-check here ❌)
```

## Fix Implementation

### Step 1: Modify `_checkGPSRadius()` to be reusable

Add return value to include GPS check result before EVERY photo save:

```dart
/// Check GPS radius before marking attendance
/// Returns: {
///   'isValid': bool,
///   'distance': double?,
///   'message': String
/// }
Future<Map<String, dynamic>> _validateGPSBeforePhoto({
  bool showUserMessages = true,
  String photoType = 'entry'  // 'entry' or 'exit'
}) async {
  if (kIsWeb) return {'isValid': true};
  
  if (kDebugMode) {
    return {'isValid': true};
  }
  
  try {
    final configRow = await _db
        .from('gps_settings')
        .select()
        .eq('institute_id', instituteId!)
        .eq('admin_id', await _gpsSettingsAdminId() ?? '')
        .maybeSingle();

    if (configRow == null) {
      return {
        'isValid': false,
        'message': '❌ Location not verified. Go to GPS Settings first.'
      };
    }

    final latitude = (configRow['latitude'] as num?)?.toDouble();
    final longitude = (configRow['longitude'] as num?)?.toDouble();
    final isLocked = configRow['is_locked'] == true;

    if (latitude == null || longitude == null || !isLocked) {
      return {
        'isValid': false,
        'message': '❌ Location not locked. Please lock in GPS Settings.'
      };
    }

    // Get current position
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    if (position.isMocked) {
      return {
        'isValid': false,
        'message': '❌ Fake GPS detected. Turn off Mock Location.'
      };
    }

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      latitude,
      longitude,
    );

    final radius = kAttendanceFenceRadiusMeters;

    if (distance > radius) {
      if (showUserMessages && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ [$photoType Photo] Out of radius!\n'
              'You are ${distance.toStringAsFixed(0)}m away.\n'
              'Must be within ${radius.toStringAsFixed(0)}m to mark attendance.'
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return {
        'isValid': false,
        'distance': distance,
        'message': 'Out of ${radius.toStringAsFixed(0)}m radius'
      };
    }

    return {
      'isValid': true,
      'distance': distance,
      'message': '✅ Within radius - attendance can be marked'
    };
  } catch (e) {
    return {
      'isValid': false,
      'message': '❌ GPS check failed: ${e.toString()}'
    };
  }
}
```

### Step 2: Call GPS validation BEFORE saving Entry Photo

Before calling `saveAttendance()` for entry, add:

```dart
// BEFORE Line 118 (before saveAttendance call)
// Validate GPS for ENTRY photo
final gpsCheck = await _validateGPSBeforePhoto(
  showUserMessages: true,
  photoType: 'ENTRY'
);

if (!gpsCheck['isValid'] as bool) {
  // Block attendance - outside radius
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(gpsCheck['message'] as String),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
      ),
    );
  }
  return; // Don't save attendance
}

// GPS is valid - proceed with saving
await HierarchicalAttendanceService().saveAttendance(
  // ... existing parameters
);
```

### Step 3: Call GPS validation BEFORE saving Exit Photo

When exit photo is being submitted, add same check:

```dart
// Validate GPS for EXIT photo
final gpsCheck = await _validateGPSBeforePhoto(
  showUserMessages: true,
  photoType: 'EXIT'
);

if (!gpsCheck['isValid'] as bool) {
  // Block exit - outside radius
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '❌ Cannot mark EXIT. You moved ${(gpsCheck['distance'] as double?)?.toStringAsFixed(0) ?? '?'}m away.\n'
          'Must be within ${kAttendanceFenceRadiusMeters.toStringAsFixed(0)}m to mark exit.'
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
      ),
    );
  }
  return; // Don't save exit
}

// GPS is valid - proceed with saving exit
await HierarchicalAttendanceService().saveAttendance(
  // ... existing parameters for exit
);
```

## Configuration

Current radius: **15 meters** (from `gps_attendance_constants.dart`)

```dart
const double kAttendanceFenceRadiusMeters = 15.0;
```

To change radius, edit `/lib/core/gps_attendance_constants.dart`

## Testing Checklist

- [ ] Entry photo: GPS valid → ✅ attendance marked
- [ ] Entry photo: GPS outside radius → ❌ attendance blocked  
- [ ] Exit photo: GPS valid → ✅ exit marked
- [ ] Exit photo: GPS outside radius → ❌ exit blocked
- [ ] Both entry & exit message shows distance + radius
- [ ] Fake GPS detected → ❌ attendance blocked
- [ ] Mock location apps detected → ❌ blocked with message

## Error Messages

✅ **Within Radius:**
```
✅ Within radius - attendance can be marked
```

❌ **Outside Radius (Entry):**
```
❌ [ENTRY Photo] Out of radius!
You are 25m away.
Must be within 15m to mark attendance.
```

❌ **Outside Radius (Exit):**
```
❌ Cannot mark EXIT. You moved 18m away.
Must be within 15m to mark exit.
```

❌ **Fake GPS:**
```
❌ Fake GPS detected. Turn off Mock Location.
```

---

## Summary

**Before Fix:**
- GPS checked once at start → Can move away before photos → ❌

**After Fix:**
- GPS checked before EACH photo (entry + exit) → Prevents attendance from outside radius → ✅
