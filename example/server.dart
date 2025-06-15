import 'dart:io';
import 'package:mdns_dart/mdns_dart.dart';

/// Simple mDNS server example
void main() async {
  print('Starting mDNS server...');

  // Get local IP
  final interfaces = await NetworkInterface.list();
  InternetAddress? localIP;

  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
        localIP = addr;
        break;
      }
    }
    if (localIP != null) break;
  }

  if (localIP == null) {
    print('Could not find network interface');
    return;
  }

  // Create service
  final service = await MDNSService.create(
    instance: 'Dart Test Server',
    service: '_testservice._tcp',
    port: 9090,
    ips: [localIP],
    txt: ['path=/api'],
  );

  print('Service: ${service.instance} at ${localIP.address}:${service.port}');

  // Start server
  final server = MDNSServer(MDNSServerConfig(zone: service));

  try {
    await server.start();
    print('Server started - advertising service!');

    await Future.delayed(Duration(seconds: 30));
  } finally {
    await server.stop();
    print('Server stopped');
  }
}
