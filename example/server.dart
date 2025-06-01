import 'dart:io';

import 'package:mdns_dart/mdns_dart.dart';

/// Test mDNS service advertising and discovery
void main() async {
  print('mDNS Service Advertising Demo');
  print('================================\n');

  // Get local IP addresses
  final interfaces = await NetworkInterface.list();
  InternetAddress? localIP;
  
  for (final interface in interfaces) {
    if (interface.name == 'enp37s0' || interface.name == 'wlan0') {
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          localIP = addr;
          break;
        }
      }
      if (localIP != null) break;
    }
  }
  
  if (localIP == null) {
    print('Could not find suitable network interface');
    return;
  }
  
  print('Using local IP: ${localIP.address}\n');

  // Create a service to advertise
  final testService = await MDNSService.create(
    instance: 'Dart Test Server',
    service: '_testservice._tcp',
    port: 9090,
    ips: [localIP],
    txt: [
      'version=1.0',
      'description=Dart mDNS Test Service',
      'path=/api',
      'protocol=http',
    ],
  );
  
  print('Created service: ${testService.instance}');
  print('   Service type: ${testService.service}');
  print('   Host: ${testService.hostName}');
  print('   IP: ${localIP.address}');
  print('   Port: ${testService.port}');
  print('   TXT Records: ${testService.txt.join(', ')}\n');

  // Create server configuration
  final serverConfig = MDNSServerConfig(
    zone: testService,
    logEmptyResponses: true,
    logger: (msg) => print(msg),
  );

  // Start the mDNS server
  final server = MDNSServer(serverConfig);
  
  try {
    await server.start();
    print('mDNS server started - advertising service!\n');
    
    // Wait a moment for server to be ready
    await Future.delayed(Duration(seconds: 2));
    
    // Now try to discover our own service
    print('Testing discovery of our advertised service...\n');
    
    final discoveredServices = await MDNSClient.discover(
      '_testservice._tcp',
      timeout: Duration(seconds: 5),
    );
    
    if (discoveredServices.isEmpty) {
      print('No services discovered (this might be expected due to localhost filtering)');
    } else {
      print('Discovered ${discoveredServices.length} service(s):');
      for (final service in discoveredServices) {
        print('');
        print('Service: ${service.name}');
        print('   Host: ${service.host}');
        print('   IPv4: ${service.addrV4?.address ?? 'none'}');
        print('   Port: ${service.port}');
        print('   Info: ${service.info}');
        if (service.infoFields.isNotEmpty) {
          print('   TXT: ${service.infoFields.join(', ')}');
        }
      }
    }
    
    print('\nServer will continue advertising for 30 seconds...');
    print('   You can now test discovery from another device/terminal:\n');
    print('   From another terminal, run:');
    print('   dart bin/test_current_with_retries.dart\n');
    print('   Or from another device, try:');
    print('   avahi-browse -r _testservice._tcp\n');
    
    // Keep server running for testing
    await Future.delayed(Duration(seconds: 30));
    
  } catch (e) {
    print('Error: $e');
  } finally {
    await server.stop();
    print('Server stopped');
  }
}
