import 'package:mdns_dart/mdns_dart.dart';
import 'dart:io';

/// Integration test for the clean mdns_dart package
void main() async {
  print('Testing Clean mDNS Dart Package');
  print('==================================\n');

  // Find the 'enp37s0' network interface
  final interfaces = await NetworkInterface.list();
  NetworkInterface? targetInterface;
  for (final iface in interfaces) {
    if (iface.name == 'enp37s0') {
      targetInterface = iface;
      break;
    }
  }

  if (targetInterface == null) {
    print('enp37s0 interface not found');
    return;
  }

  print('Using interface: ${targetInterface.addresses.first.address}\n');

  // Discover HTTP services
  print('Discovering HTTP services...');
  final results = await MDNSClient.discover(
    '_http._tcp',
    timeout: Duration(seconds: 3),
    networkInterface: targetInterface,
  );

  if (results.isEmpty) {
    print('No HTTP services found');
  } else {
    print('Found ${results.length} HTTP service(s):');
    for (final service in results) {
      print('Service: ${service.name}');
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
