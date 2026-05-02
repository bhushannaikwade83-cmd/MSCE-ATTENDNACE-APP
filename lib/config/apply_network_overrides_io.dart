import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;

/// Call from [main] before [Supabase.initialize] (and before any HTTP).
///
/// Applies to **every** [HttpClient] in the process — REST, auth, storage uploads,
/// and **WebSocket** upgrades (Supabase Realtime). Typical fix when:
/// - Wi‑Fi advertises broken IPv6; mobile data is IPv4-only → “works on data only”.
/// - Misconfigured WPAD / proxy on Wi‑Fi breaks HTTPS to cloud.
void applySupabaseNetworkOverrides() {
  HttpOverrides.global = _SupabaseFriendlyHttpOverrides();
}

Future<InternetAddress> _resolveHostPreferIpv4(String hostname) async {
  List<InternetAddress> all;
  try {
    all = await InternetAddress.lookup(hostname)
        .timeout(const Duration(seconds: 18));
  } on TimeoutException {
    throw SocketException('DNS timeout for $hostname');
  }
  if (all.isEmpty) {
    throw SocketException('Failed host lookup: $hostname');
  }
  final v4 = [for (final a in all) if (a.type == InternetAddressType.IPv4) a];
  if (v4.isNotEmpty) {
    return v4.first;
  }
  return all.first;
}

final class _SupabaseFriendlyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 28)
      ..idleTimeout = const Duration(seconds: 90)
      ..findProxy = (Uri uri) => 'DIRECT';

    client.connectionFactory = (uri, host, port) async {
      final hostname = uri.host;
      final p = uri.hasPort
          ? uri.port
          : (uri.isScheme('https') || uri.isScheme('wss') ? 443 : 80);

      if (kReleaseMode && uri.isScheme('http')) {
        throw StateError(
          'Cleartext HTTP blocked in release: $uri. Use HTTPS for APIs so traffic cannot be trivially read or modified.',
        );
      }

      final addr = await _resolveHostPreferIpv4(hostname);

      if (uri.isScheme('https') || uri.isScheme('wss')) {
        final tcpTask = await Socket.startConnect(addr, p);
        return ConnectionTask.fromSocket(
          tcpTask.socket.then(
            (socket) => SecureSocket.secure(socket, host: hostname),
          ),
          tcpTask.cancel,
        );
      }

      return Socket.startConnect(addr, p);
    };

    return client;
  }
}
