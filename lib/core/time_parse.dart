/// Parse timestamps from Supabase (ISO string), JSON, or DateTime.
DateTime? parseAnyTimestamp(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
