/// MobileFaceNet output size used by this app (see `mobilefacenet.tflite`).
const int kMobileFaceNetEmbeddingDimensions = 192;

bool _listIsNnEmbedding(dynamic emb) {
  if (emb is! List || emb.length < kMobileFaceNetEmbeddingDimensions) return false;
  return emb.any((v) => v is num && v.toDouble().abs() > 1e-6);
}

/// Validates an in-memory vector before PATCH to Supabase.
bool registrationEmbeddingVectorValid(List<double> embedding) =>
    _listIsNnEmbedding(embedding);

/// Shared rule: student row has a usable neural embedding for attendance.
bool studentHasNonEmptyFaceEmbedding(dynamic faceEmbeddingField) {
  if (faceEmbeddingField is! Map) return false;
  final m = Map<String, dynamic>.from(faceEmbeddingField);
  final emb = m['embedding'];
  if (emb is List && emb.isNotEmpty) return true;
  final templates = m['faceTemplates'];
  if (templates is List) {
    for (final t in templates) {
      if (t is Map) {
        final e = t['embedding'];
        if (e is List && e.isNotEmpty) return true;
      }
    }
  }
  return false;
}

/// Strict gate before/after persistence: detected model vector present and plausible.
bool registrationFaceEmbeddingFieldValid(dynamic faceEmbeddingField) {
  if (faceEmbeddingField is! Map) return false;
  final m = Map<String, dynamic>.from(faceEmbeddingField);
  if (_listIsNnEmbedding(m['embedding'])) return true;
  final templates = m['faceTemplates'];
  if (templates is List) {
    for (final t in templates) {
      if (t is Map) {
        final e = t['embedding'];
        if (_listIsNnEmbedding(e)) return true;
      }
    }
  }
  return false;
}
