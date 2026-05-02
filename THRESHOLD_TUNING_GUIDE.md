# Face Matching Threshold Tuning Guide

## What is a Threshold?

A **threshold** is a cutoff score (0.0 to 1.0) that determines if two faces are "the same person" or "different people."

**Cosine Similarity Score:**
- `1.0` = Identical faces (exact same embedding)
- `0.8` = Very similar (same person, good lighting)
- `0.6` = Somewhat similar (same person, different angle/lighting)
- `0.4` = Slightly similar (different people, but similar features)
- `0.0` = Completely different faces

## Current Thresholds

| Threshold | Value | Purpose |
|-----------|-------|---------|
| **Duplicate Detection** | 0.60 | Blocks students already registered |
| **Attendance Verification** | 0.50 | Recognizes student during attendance |
| **Face Confidence** | 0.50 | Minimum confidence face is real |

## The Problem You're Identifying

**If threshold is TOO HIGH (0.70+):**
- ❌ Genuine students get blocked: "Face already registered!"
- ❌ Student registered with good lighting can't register with poor lighting
- ❌ Same student with glasses/without glasses gets rejected

**If threshold is TOO LOW (0.40-):**
- ❌ Different students get matched as same person
- ❌ Student A's face opens Student B's attendance
- ❌ Duplicates: Same person registers 3 times

## How to Test & Tune

### Phase 1: Register Multiple Students (Test Data)

1. Register Student A (good lighting)
2. Register Student B (different person)
3. Register Student A again with:
   - ✅ Different angle (turn head left/right)
   - ✅ Different lighting (brighter/darker)
   - ✅ With glasses (if no glasses in first photo)
   - ✅ Without glasses (if glasses in first photo)

### Phase 2: Observe Results

**Expected behavior with 0.60 threshold:**

```
Student A + Student A (same lighting) → 0.95 similarity ✅ BLOCKED (correct)
Student A + Student A (different angle) → 0.72 similarity ✅ BLOCKED (correct)
Student A + Student A (bad lighting) → 0.65 similarity ✅ BLOCKED (correct)
Student A + Student B → 0.35 similarity ✅ ALLOWED (correct)
```

**If you see:**
- Student A can't re-register even with different angle → Threshold too HIGH
- Student A's face matches Student B's face → Threshold too LOW

### Phase 3: Adjust

If blocking too many genuine variations:
```dart
// In lib/core/face_matching_thresholds.dart

// Current (too strict)
static const double DUPLICATE_DETECTION_THRESHOLD = 0.60;

// More lenient (allow more variation)
static const double DUPLICATE_DETECTION_THRESHOLD = 0.55;
```

If allowing too many duplicates:
```dart
// Current (too lenient)
static const double DUPLICATE_DETECTION_THRESHOLD = 0.60;

// More strict (block more variation)
static const double DUPLICATE_DETECTION_THRESHOLD = 0.65;
```

## Recommended Starting Values

Based on typical AI face recognition systems:

| Scenario | Duplicate Threshold | Verification Threshold |
|----------|-------------------|----------------------|
| **Conservative** (avoid blocking genuine) | 0.55 | 0.45 |
| **Balanced** (our default) | 0.60 | 0.50 |
| **Strict** (avoid duplicates) | 0.65 | 0.55 |

## Real-World Testing Strategy

### Week 1: Register 20-30 students
- Use naturally varying lighting/angles
- Use typical student appearance (some with glasses, different hairstyles)

### Week 2: Monitor Issues
Count:
- ❌ "Already registered" errors (threshold too high?)
- ❌ Students marked with wrong face in attendance (threshold too low?)

### Week 3: Adjust & Re-test
- If too many "already registered" → Lower threshold by 0.05
- If wrong faces matching → Raise threshold by 0.05

### Week 4: Lock in Final Value
- Document your optimal threshold
- Use it in production

## Safety Valve: Manual Override

If unsure, always:
1. **Allow registration** (better to have slightly more duplicates than block genuine students)
2. **Manual review later** (admin can see and merge duplicate accounts)
3. **Attendance can be corrected** (wrong attendance can be fixed in records)

## Debugging Threshold Issues

Add this to your code to see actual similarity scores:

```dart
// In add_student_screen.dart, when saving face
final similarity = calculateCosineSimilarity(newEmbedding, existingEmbedding);
print('📊 Similarity: ${(similarity * 100).toStringAsFixed(1)}%');
print('   Threshold: ${(FaceMatchingThresholds.DUPLICATE_DETECTION_THRESHOLD * 100).toStringAsFixed(1)}%');
print('   Result: ${similarity >= FaceMatchingThresholds.DUPLICATE_DETECTION_THRESHOLD ? 'BLOCKED' : 'ALLOWED'}');
```

## Summary

| Goal | Action |
|------|--------|
| Block fewer genuine students | Lower threshold to 0.55 |
| Block more duplicates | Raise threshold to 0.65 |
| Better attendance recognition | Lower verification to 0.45 |
| Stricter attendance matching | Raise verification to 0.55 |
| See actual scores | Add debug logging |
| Test thoroughly | Register 20+ students with variations |

---

**Start with 0.60/0.50, test, adjust by 0.05 increments based on issues.**
