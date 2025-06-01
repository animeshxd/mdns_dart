import 'package:mdns_dart/mdns_dart.dart';

import 'dart:io';

/// ESP32 test for the clean mdns_dart package
void main() async {
  print('Testing Clean Package - ESP32 Discovery');
  print('==========================================\n');

  // Find the 'docker0' network interface
  final interfaces = await NetworkInterface.list();
  NetworkInterface? targetInterface;
  for (final iface in interfaces) {
    if (iface.name == 'docker0') {
      targetInterface = iface;
      break;
    }
  }

  if (targetInterface == null) {
    print('docker0 interface not found');
    return;
  }

  print('Using interface: ${targetInterface.addresses.first.address}\n');

  // Discover ESP32 services
  print('Discovering ESP32 services...');
  final results = await MDNSClient.discover(
    '_esp32auth._udp',
    timeout: Duration(seconds: 3),
    networkInterface: targetInterface,
  );

  if (results.isEmpty) {
    print('No ESP32 services found');
  } else {
    print('Found ${results.length} ESP32 service(s):');
    for (final service in results) {
      print('ESP32: ${service.name}');
      print('  Host: ${service.host}');
      print('  IPv4: ${service.addrV4?.address ?? 'none'}');
      print('  IPv6: ${service.addrV6?.address ?? 'none'}');
      print('  Port: ${service.port}');
      print('  Info: ${service.info}');
      if (service.infoFields.isNotEmpty) {
        print('  TXT: ${service.infoFields.join(', ')}');
      }
      print('');
    }
  }

  print('Done.');
}
