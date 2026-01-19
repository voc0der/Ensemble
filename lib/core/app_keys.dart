import 'package:flutter/material.dart';

/// Centralized keys so we can show UI notifications even when a widget context
/// doesn't have an Overlay/Scaffold (fixes "No Overlay widget found").
class AppKeys {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
}
