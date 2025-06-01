import 'package:mdns_dart/mdns_dart.dart';

/// Integration test for the clean mdns_dart package
void main() async {

  // Discover HTTP services
  print('Discovering HTTP services...');
  final results = await MDNSClient.discover(
    '_http._tcp',
    timeout: Duration(seconds: 3),
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
