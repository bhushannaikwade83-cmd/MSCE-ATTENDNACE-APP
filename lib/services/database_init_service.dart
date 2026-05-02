import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Verifies Supabase connectivity at startup (replaces FirestoreInitService).
///
/// Schema changes belong in `supabase/migrations` — not in the client. The old
/// AutoSchemaInit RPC path added latency on first login by scanning many columns.
class DatabaseInitService {
  static bool _initialized = false;

  /// Runs once per app launch to ensure DB is reachable before writes.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await initializeAll();
    _initialized = true;
  }

  static Future<void> initializeAll() async {
    try {
      await Supabase.instance.client.from('institutes').select('id').limit(1);
      if (kDebugMode) debugPrint('✅ Database (Supabase) reachable');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Database init: $e');
    }
  }
}
