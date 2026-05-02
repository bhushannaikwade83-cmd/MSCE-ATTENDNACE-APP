# Mandatory GPS Configuration on First Admin Login

## Feature Overview ✅

New admin accounts are required to configure GPS location on their FIRST login before accessing the main app.

---

## Implementation

### Files Modified

1. ✅ `lib/presentation/screens/login_screen.dart`
   - Added `_checkGpsConfigured()` method to verify GPS setup status
   - Added `_navigateBasedOnGpsStatus()` to route correctly based on GPS status
   - Modified all admin login paths to check GPS before home navigation

2. ✅ `lib/presentation/screens/gps_settings_screen.dart`
   - Added `isMandatory` and `fromLogin` parameters
   - Disabled back button when `isMandatory = true`
   - Auto-navigate to home after GPS configuration saved
   - Added warning if user tries to exit mandatory GPS setup

---

## Workflow

### First-Time Admin Login Flow

```
1. Admin enters credentials → Login successful
                    ↓
2. Check GPS Configuration
   ├─ GPS NOT configured → Show GPS Settings Screen (Mandatory)
   │  └─ Back button disabled ❌
   │  └─ Cannot exit without setting GPS
   │  └─ Admin sets latitude/longitude
   │  └─ Saves GPS → Auto-navigates to home ✅
   │
   └─ GPS ALREADY configured → Navigate to Home directly ✅
```

### Returning Admin Login Flow

```
1. Admin enters credentials → Login successful
                    ↓
2. Check GPS Configuration
   └─ GPS already configured → Navigate to Home ✅
      (No GPS setup needed on subsequent logins)
```

---

## GPS Configuration Details

### Storage

**Table:** `gps_settings`
**Fields:**
- `institute_id` - Which institute (ensures data isolation)
- `admin_id` - Which admin (each admin can have own GPS)
- `latitude` - Institute location latitude
- `longitude` - Institute location longitude
- `radius` - Geofence radius (fixed at 30m)
- `is_locked` - Whether admin can change GPS location

### Validation

GPS is considered "configured" when:
- ✅ Latitude is not NULL and not 0.0
- ✅ Longitude is not NULL and not 0.0
- ✅ Both values are valid numbers

### Geofence Radius

- Fixed at **30 meters** (cannot be changed by admin)
- Used for attendance marking location verification
- Prevents marking attendance from outside institute

---

## Code Flow

### 1. Check GPS Configuration
```dart
// File: login_screen.dart
Future<bool> _checkGpsConfigured() async {
  // Get admin's institute ID
  // Query gps_settings table for this admin + institute
  // Verify latitude & longitude are valid
  // Return true if configured, false if missing
}
```

### 2. Route Based on GPS Status
```dart
// File: login_screen.dart
Future<void> _navigateBasedOnGpsStatus() async {
  if (GPS NOT configured) {
    // Redirect to GPS Settings Screen (mandatory)
    Navigator.pushNamedAndRemoveUntil(
      context,
      GpsSettingsScreen.routeName,
      arguments: {'mandatory': true, 'fromLogin': true},
    );
  } else {
    // GPS configured, go to home
    _navigateToHome();
  }
}
```

### 3. GPS Settings Screen (Mandatory Mode)
```dart
// File: gps_settings_screen.dart
class GpsSettingsScreen {
  late bool _isMandatory;
  late bool _fromLogin;
  
  // Back button disabled when mandatory
  PopScope(
    canPop: _isMandatory ? false : true,
  )
  
  // After save, navigate to home
  if (_fromLogin && _isMandatory) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      MainNavigationScreen.routeName,
    );
  }
}
```

---

## User Experience

### For New Admin

1. **Admin registers** → Account created
2. **Admin logs in** → Redirected to GPS setup
3. **GPS Setup Screen:**
   - Can't go back (back button disabled)
   - Enter institute latitude/longitude
   - Radius automatically set to 30m
   - Tap "Save GPS Location"
4. **Success** → Auto-navigates to main app
5. **Future logins** → No GPS setup needed ✅

### For Returning Admin

1. **Admin logs in** → GPS check passes (already configured)
2. **Direct navigation** to main app (no GPS screen)

---

## Security Benefits

✅ Ensures all admins have proper location configured  
✅ Prevents attendance marking from invalid locations  
✅ Geofencing enabled automatically for all admins  
✅ Cannot skip GPS setup on first login  
✅ Per-admin GPS configuration (each admin can have own location)

---

## Testing Checklist

- [ ] New admin logs in for first time
- [ ] GPS settings screen appears (non-skippable)
- [ ] Cannot go back without configuring GPS
- [ ] Enter latitude/longitude → Save
- [ ] Auto-navigates to home after save ✅
- [ ] Re-login with same admin → No GPS screen ✅
- [ ] GPS location used for attendance geofencing ✅
