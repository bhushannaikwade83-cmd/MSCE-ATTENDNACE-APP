/// Face matching thresholds for registration and attendance
/// Cosine similarity ranges from 0.0 to 1.0
/// Higher = more similar faces

class FaceMatchingThresholds {
  /// Threshold for duplicate registration detection
  /// 0.60-0.70: Strict - blocks most duplicates, but some genuine variations allowed
  /// 0.70-0.80: Very strict - blocks more variations, risk of false positives
  /// Start conservative (0.60) and increase if getting too many false positives
  static const double DUPLICATE_DETECTION_THRESHOLD = 0.60;

  /// Threshold for attendance face verification
  /// 0.50-0.60: Lenient - accepts face with lighting/angle changes
  /// 0.40-0.50: Very lenient - accepts almost any variation of the face
  /// Start at 0.50 for good balance
  static const double ATTENDANCE_VERIFICATION_THRESHOLD = 0.50;

  /// Minimum confidence for face detection itself
  /// 0.5 = 50% confidence the detected face is a real face (vs noise)
  static const double MINIMUM_FACE_CONFIDENCE = 0.5;

  /// Print thresholds for debugging
  static void printThresholds() {
    print('''
╔════════════════════════════════════════════════════════════════╗
║         FACE MATCHING THRESHOLDS (Cosine Similarity)           ║
╠════════════════════════════════════════════════════════════════╣
║ DUPLICATE DETECTION: $DUPLICATE_DETECTION_THRESHOLD (${(DUPLICATE_DETECTION_THRESHOLD * 100).toStringAsFixed(0)}% similar)
║ ATTENDANCE VERIFICATION: $ATTENDANCE_VERIFICATION_THRESHOLD (${(ATTENDANCE_VERIFICATION_THRESHOLD * 100).toStringAsFixed(0)}% similar)
║ FACE CONFIDENCE: $MINIMUM_FACE_CONFIDENCE (${(MINIMUM_FACE_CONFIDENCE * 100).toStringAsFixed(0)}%)
╚════════════════════════════════════════════════════════════════╝

HOW TO TUNE:
✅ DUPLICATE THRESHOLD TOO HIGH (blocking genuine students)?
   → Lower from 0.60 to 0.55 (allow more variation)
   → Students can re-register with different lighting/angle

✅ TOO MANY DUPLICATES REGISTERED (same person multiple times)?
   → Raise from 0.60 to 0.65 (block more variations)
   → Fewer false registrations

✅ ATTENDANCE NOT RECOGNIZING STUDENT?
   → Lower verification threshold from 0.50 to 0.45
   → More lenient with lighting/pose changes

✅ ATTENDANCE RECOGNIZING WRONG STUDENT?
   → Raise verification threshold from 0.50 to 0.55
   → More strict matching
    ''');
  }

  /// Calculate similarity percentage for user display
  static String similarityPercentage(double similarity) {
    return '${(similarity * 100).toStringAsFixed(1)}%';
  }

  /// Check if two faces are too similar (duplicate)
  static bool isDuplicate(double similarity) {
    return similarity >= DUPLICATE_DETECTION_THRESHOLD;
  }

  /// Check if face matches for attendance
  static bool isMatch(double similarity) {
    return similarity >= ATTENDANCE_VERIFICATION_THRESHOLD;
  }
}
