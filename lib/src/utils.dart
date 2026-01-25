library;

import 'dart:io';

extension RawDatagramSocketExtensions on RawDatagramSocket {
  /// Helper function to set the multicast interface.
  ///
  /// Throws a [OSError] on failure.
  void setMulticastInterface(NetworkInterface iface) {
    final level = address.type == InternetAddressType.IPv4
        ? RawSocketOption.levelIPv4
        : RawSocketOption.levelIPv6;
    final option = address.type == InternetAddressType.IPv4
        ? RawSocketOption.IPv4MulticastInterface
        : RawSocketOption.IPv6MulticastInterface;

    iface.addresses.where((addr) => addr.type == address.type).forEach(
          (addr) =>
              setRawOption(RawSocketOption(level, option, addr.rawAddress)),
        );
  }
}

/// Trims leading and trailing dots from a domain name.
String trimDot(String s) {
  return s.replaceAll(RegExp(r'^\.+|\.+$'), '');
}

/// Validates if a string is a valid Fully Qualified Domain Name (FQDN).
///
/// An FQDN must:
/// - Be non-empty.
/// - End with a dot.
/// - Contain valid labels (alphanumeric, hyphens, max 63 chars).
bool isValidFQDN(String s) {
  if (s.isEmpty) return false;
  if (!s.endsWith('.')) return false;

  // Basic validation - could be more comprehensive
  final labels = s.substring(0, s.length - 1).split('.');
  if (labels.isEmpty) return false;

  for (final label in labels) {
    if (label.isEmpty) return false;
    if (label.length > 63) return false;
    if (!RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(label)) {
      return false;
    }
  }

  return true;
}
