import 'package:flutter/material.dart';

/// [SessionMonitor] wraps [MaterialApp], so it must not use its own [BuildContext]
/// for [Navigator] or [showDialog]. Attach this key to [MaterialApp.navigatorKey].
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
