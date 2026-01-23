import 'package:test/test.dart';
import 'package:mdns_dart/mdns_dart.dart';

void main() {
  group('QuerySession', () {
    test('assembles complete service from ordered records', () {
      final session = QuerySession(service: '_http._tcp');
      final records = [
        PTRRecord(
          name: '_http._tcp.local.',
          target: 'my-service._http._tcp.local.',
          ttl: 120,
        ),
        SRVRecord(
          name: 'my-service._http._tcp.local.',
          target: 'my-host.local.',
          port: 8080,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        TXTRecord(
          name: 'my-service._http._tcp.local.',
          strings: ['ver=1'],
          ttl: 120,
        ),
        ARecord(
          name: 'my-host.local.',
          address: '192.168.1.1',
          ttl: 120,
        ),
      ];

      final results = session.addRecords(records);
      expect(results, hasLength(1));
      final entry = results.first;
      expect(entry.name, 'my-service._http._tcp.local.');
      expect(entry.port, 8080);
      expect(entry.addrV4?.address, '192.168.1.1');
      expect(entry.info, 'ver=1');
    });

    test('ignores partial services', () {
      final session = QuerySession(service: '_http._tcp');
      final records = [
        PTRRecord(
          name: '_http._tcp.local.',
          target: 'partial._http._tcp.local.',
          ttl: 120,
        ),
        // Missing SRV, TXT, A
      ];

      final results = session.addRecords(records);
      expect(results, isEmpty);
    });

    test('deduplicates results', () {
      final session = QuerySession(service: '_http._tcp');

      final records = [
        PTRRecord(
          name: '_http._tcp.local.',
          target: 's1._http._tcp.local.',
          ttl: 120,
        ),
        SRVRecord(
          name: 's1._http._tcp.local.',
          target: 'h1.local.',
          port: 80,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        TXTRecord(name: 's1._http._tcp.local.', strings: [''], ttl: 120),
        ARecord(name: 'h1.local.', address: '1.2.3.4', ttl: 120),
      ];

      var results = session.addRecords(records);

      expect(results, hasLength(1));

      // Feed same records again

      results = session.addRecords(records);

      expect(results, isEmpty);
    });

    // The server should handle conflicting instance names.
    test('merges IPs when service instance host changes', () {
      final session = QuerySession(service: '_http._tcp');

      // 1. Initial discovery of s1 at h1
      final records1 = [
        PTRRecord(
          name: '_http._tcp.local.',
          target: 's1._http._tcp.local.',
          ttl: 120,
        ),
        SRVRecord(
          name: 's1._http._tcp.local.',
          target: 'h1.local.',
          port: 80,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        TXTRecord(name: 's1._http._tcp.local.', strings: [''], ttl: 120),
        ARecord(name: 'h1.local.', address: '1.1.1.1', ttl: 120),
      ];
      final results1 = session.addRecords(records1);
      expect(results1, hasLength(1));
      expect(
        results1.first.allAddresses.map((a) => a.address),
        contains('1.1.1.1'),
      );

      // 2. Service "moves" to h2 or another server announces s1 at h2
      final records2 = [
        SRVRecord(
          name: 's1._http._tcp.local.',
          target: 'h2.local.',
          port: 80,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        ARecord(name: 'h2.local.', address: '2.2.2.2', ttl: 120),
      ];

      // No new emission expected as it was already complete
      session.addRecords(records2);

      final entry = results1.first;
      final addresses = entry.allAddresses.map((a) => a.address).toList();

      // Old behavior: IPs are accumulated/merged
      expect(addresses, contains('1.1.1.1'));
      expect(addresses, contains('2.2.2.2'));
      expect(entry.host, 'h2.local.');
    });

    test('handles redundant/repeated partial records', () {
      final session = QuerySession(service: '_http._tcp');

      // 1. Receive PTR (links name)
      session.addRecords([
        PTRRecord(
          name: '_http._tcp.local.',
          target: 's1._http._tcp.local.',
          ttl: 120,
        ),
      ]);

      // 2. Receive PTR AGAIN (redundant) + SRV
      session.addRecords([
        PTRRecord(
          name: '_http._tcp.local.',
          target: 's1._http._tcp.local.',
          ttl: 120,
        ),
        SRVRecord(
          name: 's1._http._tcp.local.',
          target: 'h1.local.',
          port: 80,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
      ]);

      // 3. Receive SRV AGAIN (redundant) + TXT + A
      final results = session.addRecords([
        SRVRecord(
          name: 's1._http._tcp.local.',
          target: 'h1.local.',
          port: 80,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        TXTRecord(name: 's1._http._tcp.local.', strings: [''], ttl: 120),
        ARecord(name: 'h1.local.', address: '1.1.1.1', ttl: 120),
      ]);

      // Should be complete now
      expect(results, hasLength(1));
      expect(results.first.name, 's1._http._tcp.local.');

      // 4. Receive EVERYTHING again (packet retransmission)
      final retransmission = session.addRecords([
        PTRRecord(
          name: '_http._tcp.local.',
          target: 's1._http._tcp.local.',
          ttl: 120,
        ),
        SRVRecord(
          name: 's1._http._tcp.local.',
          target: 'h1.local.',
          port: 80,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        TXTRecord(name: 's1._http._tcp.local.', strings: [''], ttl: 120),
        ARecord(name: 'h1.local.', address: '1.1.1.1', ttl: 120),
      ]);

      // Should NOT re-emit the result
      expect(retransmission, isEmpty);

      // Verify state is still valid
      final entry = results.first;
      expect(entry.allAddresses.map((a) => a.address), contains('1.1.1.1'));
      expect(entry.allAddresses, hasLength(1)); // Should not duplicate IP
    });

    test('handles dual-stack (IPv4 + IPv6) records', () {
      final session = QuerySession(service: '_http._tcp');
      final records = [
        PTRRecord(
          name: '_http._tcp.local.',
          target: 's1._http._tcp.local.',
          ttl: 120,
        ),
        SRVRecord(
          name: 's1._http._tcp.local.',
          target: 'h1.local.',
          port: 80,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        TXTRecord(name: 's1._http._tcp.local.', strings: [''], ttl: 120),
        ARecord(name: 'h1.local.', address: '192.168.1.1', ttl: 120),
        AAAARecord(name: 'h1.local.', address: 'fe80::1', ttl: 120),
      ];

      final results = session.addRecords(records);
      expect(results, hasLength(1));

      final entry = results.first;
      expect(entry.addrV4?.address, '192.168.1.1');
      expect(entry.addrV6?.address, 'fe80::1');
      expect(
        entry.allAddresses.map((a) => a.address),
        containsAll(['192.168.1.1', 'fe80::1']),
      );
    });

    test('filters out irrelevant records', () {
      final session = QuerySession(service: '_http._tcp');

      // Records for a DIFFERENT service type
      final noise = [
        PTRRecord(
          name: '_googlecast._tcp.local.',
          target: 'chromecast._googlecast._tcp.local.',
          ttl: 120,
        ),
        SRVRecord(
          name: 'chromecast._googlecast._tcp.local.',
          target: 'device.local.',
          port: 8009,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        TXTRecord(
          name: 'chromecast._googlecast._tcp.local.',
          strings: ['fn=Living Room'],
          ttl: 120,
        ),
        ARecord(name: 'device.local.', address: '192.168.1.50', ttl: 120),
      ];

      var results = session.addRecords(noise);
      expect(results, isEmpty);

      // Valid records
      final valid = [
        PTRRecord(
          name: '_http._tcp.local.',
          target: 'web._http._tcp.local.',
          ttl: 120,
        ),
        SRVRecord(
          name: 'web._http._tcp.local.',
          target: 'server.local.',
          port: 80,
          priority: 0,
          weight: 0,
          ttl: 120,
        ),
        TXTRecord(name: 'web._http._tcp.local.', strings: [''], ttl: 120),
        ARecord(name: 'server.local.', address: '192.168.1.1', ttl: 120),
      ];

      results = session.addRecords(valid);
      expect(results, hasLength(1));
      expect(results.first.name, 'web._http._tcp.local.');
    });
  });
}
