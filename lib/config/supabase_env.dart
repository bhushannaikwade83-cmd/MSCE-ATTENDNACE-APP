import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network_policy.dart';
import 'supabase_http_client_stub.dart'
    if (dart.library.io) 'supabase_http_client_io.dart';

/// Supabase — add to `.env`:
/// ```
/// SUPABASE_URL=https://xxxx.supabase.co
/// SUPABASE_ANON_KEY=sb_publishable_... or anon JWT
/// SUPABASE_SERVICE_ROLE_KEY=...   optional: service_role secret for `scripts/import_institutes_csv.py` only (never ship in the app)
/// ADMIN_PORTAL_URL=https://...   (optional; React admin portal for approvals / institutes)
/// ```
class SupabaseEnv {
  static bool get isConfigured {
    final u = dotenv.env['SUPABASE_URL']?.trim();
    final k = dotenv.env['SUPABASE_ANON_KEY']?.trim();
    return u != null && u.isNotEmpty && k != null && k.isNotEmpty;
  }

  static String get url {
    final v = dotenv.env['SUPABASE_URL']?.trim();
    if (v == null || v.isEmpty) {
      throw StateError('SUPABASE_URL missing in .env');
    }
    return NetworkPolicy.parseTrustedApiUrl(v, name: 'SUPABASE_URL').toString();
  }

  static String get anonKey {
    final v = dotenv.env['SUPABASE_ANON_KEY']?.trim();
    if (v == null || v.isEmpty) {
      throw StateError('SUPABASE_ANON_KEY missing in .env');
    }
    return v;
  }

  /// Call after [dotenv.load]. Required for the app (Firebase removed).
  static Future<void> initializeRequired() async {
    if (!isConfigured) {
      // Allow app boot for UI testing when .env isn't set up yet.
      if (kDebugMode) {
        debugPrint(
          '⚠️ Supabase not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to .env to enable backend features.',
        );
      }
      return;
    }
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      // Prefer IPv4 on dart:io — reduces "no internet on Wi‑Fi" when IPv6 is broken.
      httpClient: createSupabaseHttpClient(),
    );
    if (kDebugMode) debugPrint('✅ Supabase initialized');
  }
}
