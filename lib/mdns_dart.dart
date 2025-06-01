/// A comprehensive mDNS (Multicast DNS) service discovery library for Dart.
///
/// This library provides complete mDNS functionality for service discovery
/// and registration, ported from the proven HashiCorp Go implementation.
///
/// Features:
/// - DNS message format handling with all record types
/// - Service discovery with streaming APIs
/// - Multi-interface network support
/// - IPv4 and IPv6 support
/// - Production-ready performance
library;

// Core library exports
export 'src/dns.dart';
export 'src/zone.dart'; 
export 'src/client.dart';
export 'src/server.dart';
