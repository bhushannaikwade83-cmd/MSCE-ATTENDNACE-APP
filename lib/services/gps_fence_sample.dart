import 'package:geolocator/geolocator.dart';

import '../core/gps_attendance_constants.dart';

/// Result of comparing the device position to a locked fence point.
class GpsFenceSampleResult {
  const GpsFenceSampleResult({
    required this.isWithinFence,
    required this.bestDistanceMeters,
    required this.accuracyUsedForMessage,
    this.mockedDetected = false,
    this.errorMessage,
  });

  final bool isWithinFence;
  /// Smallest distance to the fence center across successful samples (meters).
  final double bestDistanceMeters;
  /// Reported accuracy (meters) for the sample that produced [bestDistanceMeters], when known.
  final double accuracyUsedForMessage;
  final bool mockedDetected;
  final String? errorMessage;
}

/// Takes several GPS readings (indoor fixes often jump hundreds of meters between samples).
/// Passes if **any** sample lies within [radiusMeters] + a **clamped** accuracy buffer.
Future<GpsFenceSampleResult> samplePositionAgainstFence({
  required double fenceLat,
  required double fenceLng,
  double radiusMeters = kAttendanceFenceRadiusMeters,
  int maxSamples = 7,
  Duration delayBetweenSamples = const Duration(milliseconds: 1200),
  int firstSampleTimeoutSeconds = 16,
  int laterSampleTimeoutSeconds = 12,
  bool tryRecentLastKnownFirst = false,
  Duration lastKnownMaxAge = const Duration(minutes: 3),
}) async {
  // Pre-checks: fail fast with clear actionable messages.
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return const GpsFenceSampleResult(
      isWithinFence: false,
      bestDistanceMeters: 0,
      accuracyUsedForMessage: 0,
      errorMessage: 'Location services are OFF. Please enable GPS and try again.',
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever ||
      permission == LocationPermission.denied) {
    return const GpsFenceSampleResult(
      isWithinFence: false,
      bestDistanceMeters: 0,
      accuracyUsedForMessage: 0,
      errorMessage:
          'Location permission is required. Allow location access, then try again.',
    );
  }

  if (tryRecentLastKnownFirst) {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && !last.isMocked) {
        final age = DateTime.now().difference(last.timestamp);
        if (!age.isNegative && age <= lastKnownMaxAge) {
          final d = Geolocator.distanceBetween(
            last.latitude,
            last.longitude,
            fenceLat,
            fenceLng,
          );
          final rawAcc = last.accuracy > 0 ? last.accuracy : 35.0;
          final clampedAcc = rawAcc.clamp(12.0, 100.0);
          final effectiveRadius = radiusMeters + clampedAcc;
          if (d <= effectiveRadius) {
            return GpsFenceSampleResult(
              isWithinFence: true,
              bestDistanceMeters: d,
              accuracyUsedForMessage: last.accuracy > 0 ? last.accuracy : clampedAcc,
            );
          }
        }
      }
    } catch (_) {}
  }

  double bestDistance = double.infinity;
  double? bestAccuracy;

  for (var i = 0; i < maxSamples; i++) {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          // `high` is more stable indoors than forcing `best` every time.
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(
            seconds: i == 0 ? firstSampleTimeoutSeconds : laterSampleTimeoutSeconds,
          ),
        ),
      );

      if (position.isMocked) {
        return const GpsFenceSampleResult(
          isWithinFence: false,
          bestDistanceMeters: 0,
          accuracyUsedForMessage: 0,
          mockedDetected: true,
        );
      }

      final d = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        fenceLat,
        fenceLng,
      );

      if (d < bestDistance) {
        bestDistance = d;
        bestAccuracy = position.accuracy > 0 ? position.accuracy : null;
      }

      final rawAcc = position.accuracy > 0 ? position.accuracy : 35.0;
      // OS accuracy is often optimistic indoors; floor + cap keep checks usable without opening huge holes.
      final clampedAcc = rawAcc.clamp(12.0, 100.0);
      final effectiveRadius = radiusMeters + clampedAcc;

      if (d <= effectiveRadius) {
        return GpsFenceSampleResult(
          isWithinFence: true,
          bestDistanceMeters: d,
          accuracyUsedForMessage: position.accuracy > 0 ? position.accuracy : clampedAcc,
        );
      }
    } catch (_) {
      // Try another sample after a short wait.
    }

    if (i < maxSamples - 1) {
      await Future<void>.delayed(delayBetweenSamples);
    }
  }

  if (bestDistance == double.infinity) {
    // Indoor fallback: use last known position when live GPS cannot stabilize.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final d = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          fenceLat,
          fenceLng,
        );
        final rawAcc = last.accuracy > 0 ? last.accuracy : 45.0;
        final clampedAcc = rawAcc.clamp(18.0, 120.0);
        final effectiveRadius = radiusMeters + clampedAcc;
        if (d <= effectiveRadius) {
          return GpsFenceSampleResult(
            isWithinFence: true,
            bestDistanceMeters: d,
            accuracyUsedForMessage:
                last.accuracy > 0 ? last.accuracy : clampedAcc,
          );
        }
        return GpsFenceSampleResult(
          isWithinFence: false,
          bestDistanceMeters: d,
          accuracyUsedForMessage:
              last.accuracy > 0 ? last.accuracy : clampedAcc,
        );
      }
    } catch (_) {
      // fall through to user-facing message
    }

    return const GpsFenceSampleResult(
      isWithinFence: false,
      bestDistanceMeters: 0,
      accuracyUsedForMessage: 0,
      errorMessage:
          'Could not get a stable GPS reading inside classroom. Move near a window/open area for 10-15 seconds, then try again.',
    );
  }

  return GpsFenceSampleResult(
    isWithinFence: false,
    bestDistanceMeters: bestDistance,
    accuracyUsedForMessage: bestAccuracy ?? 0,
  );
}
