library;

import 'dart:io';

/// Helper function to set the multicast interface
extension RawDatagramSocketExtensions on RawDatagramSocket {
  void setMulticastInterface(NetworkInterface iface) {
    final level = address.type == InternetAddressType.IPv4
        ? RawSocketOption.levelIPv4
        : RawSocketOption.levelIPv6;
    final option = address.type == InternetAddressType.IPv4
        ? RawSocketOption.IPv4MulticastInterface
        : RawSocketOption.IPv6MulticastInterface;

    iface.addresses
        .where((addr) => addr.type == address.type)
        .forEach(
          (addr) =>
              setRawOption(RawSocketOption(level, option, addr.rawAddress)),
        );
  }
}
