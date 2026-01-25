import 'dart:io';
import 'package:test/test.dart';
import 'package:mdns_dart/mdns_dart.dart';

void main() {
  group('mDNS Integration', () {
    late MDNSServer server;
    late MultiServiceZone zone;

    setUp(() async {
      zone = MultiServiceZone();

      // Create a test service
      final service = MDNSService(
        instance: 'IntegrationTestService',
        service: '_test._tcp.',
        domain: 'local.',
        hostName: 'test-host.local.',
        port: 12345,
        ips: [InternetAddress('127.0.0.1')],
        txt: ['version=1.0', 'status=ready'],
      );

      zone.addService(service);

      // Start server. mDNS uses port 5353.
      server = MDNSServer(MDNSServerConfig(
        zone: zone,
        reuseAddress: true,
        reusePort: true,
      ));

      try {
        await server.start();
      } catch (e) {
        // print('Warning: Failed to start MDNSServer for integration test: $e');
      }
    });

    tearDown(() async {
      await server.stop();
    });

    test('client discovers service registered on server', () async {
      if (!server.isRunning) {
        markTestSkipped(
            'MDNSServer is not running (multicast probably not supported or port 5353 busy)');
        return;
      }

      // Query for the existing service
      final results = await MDNSClient.discover(
        '_test._tcp',
        timeout: const Duration(seconds: 1),
      );

      expect(results, isNotEmpty,
          reason: 'Service should have been discovered');

      final entry =
          results.firstWhere((e) => e.name.contains('IntegrationTestService'));
      expect(entry.port, equals(12345));
      expect(entry.allAddresses.map((a) => a.address), contains('127.0.0.1'));
      expect(entry.infoFields, containsAll(['version=1.0', 'status=ready']));
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('client returns empty list for non-existing service', () async {
      if (!server.isRunning) {
        markTestSkipped('MDNSServer is not running');
        return;
      }

      // Query for a service that does NOT exist
      final results = await MDNSClient.discover(
        '_nonexistent._tcp',
        timeout: const Duration(seconds: 1),
      );

      expect(results, isEmpty,
          reason: 'No results should be returned for a non-existing service');
    }, timeout: const Timeout(Duration(seconds: 5)));
  });
}
