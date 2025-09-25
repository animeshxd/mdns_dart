import 'dart:io';
import 'package:mdns_dart/mdns_dart.dart';

/// mDNS client with specific network interface
void main() async {
  print('Discovering services on docker0 interface...');

  // Find the 'docker0' network interface
  final interfaces = await NetworkInterface.list();
  final targetInterface =
      interfaces.where((i) => i.name == 'docker0').firstOrNull;

  if (targetInterface == null) {
    print('docker0 interface not found');
    return;
  }

  // Discover ESP32 services
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
}
