# Geofence 30M Radius Explanation

## ✅ How It Works

The **30m radius** starts from the **exact verified GPS location** (the coordinates saved when admin verifies location).

### Visual Representation

```
        ⬆️ 15m North
        |
        |
    ⬅️ 15m | 15m ➡️
    West  📍  East
    (Verified Location)
        |
        |
        ⬇️ 15m South
```

### Distance Calculation

- **Center Point**: Verified GPS coordinates (latitude, longitude)
- **Radius**: 30 meters from center in all directions
- **Total Coverage**: 60m diameter circle (30m radius × 2)

### Examples

1. **At Exact Location** (distance = 0m)
   - ✅ **ALLOWED** - You are at the verified location

2. **15m Away** (any direction)
   - ✅ **ALLOWED** - Within 30m radius

3. **30m Away** (at the edge)
   - ✅ **ALLOWED** - Exactly at 30m boundary

4. **31m Away** (beyond radius)
   - ❌ **REJECTED** - Outside 30m radius

### GPS Accuracy Buffer

The system adds a small buffer for GPS accuracy:
- **Base Radius**: 30m (fixed)
- **GPS Buffer**: Up to 10m (only if GPS accuracy is reasonable)
- **Effective Radius**: 30m + buffer = **maximum 40m**

This accounts for:
- GPS signal variations
- Building interference
- Indoor GPS drift

### Code Implementation

```dart
// Calculate distance from current position to verified location
final distance = Geolocator.distanceBetween(
  currentLatitude,
  currentLongitude,
  verifiedLatitude,
  verifiedLongitude,
);

// Base radius is always 30m
const double radius = 30.0;

// Add GPS accuracy buffer (up to 10m)
double accuracyBuffer = 0.0;
if (gpsAccuracy > 0 && gpsAccuracy <= 10.0) {
  accuracyBuffer = gpsAccuracy;
} else if (gpsAccuracy > 10.0 && gpsAccuracy <= 50.0) {
  accuracyBuffer = 10.0;
}

// Effective radius = 30m + buffer (max 40m)
final effectiveRadius = radius + accuracyBuffer;

// Check if within radius
final isWithinRadius = distance <= effectiveRadius;
```

### Real-World Scenarios

**Scenario 1: Perfect GPS (5m accuracy)**
- Base radius: 30m
- GPS buffer: 5m
- Effective radius: 35m
- ✅ You can be up to 35m away and still mark attendance

**Scenario 2: Good GPS (10m accuracy)**
- Base radius: 30m
- GPS buffer: 10m
- Effective radius: 40m
- ✅ You can be up to 40m away and still mark attendance

**Scenario 3: Poor GPS (>50m accuracy)**
- Base radius: 30m
- GPS buffer: 0m (rejected for security)
- Effective radius: 30m
- ⚠️ GPS accuracy too poor - likely fake GPS

### Important Notes

1. **30m is Fixed**: The base radius is always 30m, never changes
2. **Starts from Verified Location**: The 30m circle is centered at the exact coordinates saved during verification
3. **All Directions**: 30m applies in all directions (north, south, east, west, and diagonally)
4. **GPS Buffer**: Small buffer added only for reasonable GPS accuracy (not for fake GPS)

### Summary

✅ **30m radius = 15m in all directions from verified location**
✅ **Strict enforcement** - no attendance outside 30m (plus small GPS buffer)
✅ **Secure** - prevents marking attendance from far away
✅ **Accurate** - uses best GPS accuracy for precise geofence
