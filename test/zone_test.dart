import 'dart:io';
import 'package:test/test.dart';
import 'package:mdns_dart/mdns_dart.dart';

void main() {
  group('MDNSService', () {
    late MDNSService service;
    final ipv4 = InternetAddress('192.168.1.5');
    final ipv6 = InternetAddress('fe80::1');

    setUp(() {
      service = MDNSService(
        instance: 'My Printer',
        service: '_ipp._tcp.',
        domain: 'local.',
        hostName: 'printer.local.',
        port: 631,
        ips: [ipv4, ipv6],
        txt: ['txtvers=1', 'note=Office Printer'],
      );
    });

    test('initializes correctly', () {
      expect(service.instance, equals('My Printer'));
      expect(service.service, equals('_ipp._tcp.'));
      expect(service.domain, equals('local.'));
      expect(service.hostName, equals('printer.local.'));
      expect(service.port, equals(631));
      expect(service.ips, containsAll([ipv4, ipv6]));
      expect(service.txt, containsAll(['txtvers=1', 'note=Office Printer']));
    });

    test('computes addresses correctly', () {
      expect(service.serviceAddr, equals('_ipp._tcp.local.'));
      expect(service.instanceAddr, equals('My Printer._ipp._tcp.local.'));
      expect(service.enumAddr, equals('_services._dns-sd._udp.local.'));
    });

    group('Initialization Error Handling', () {
      test('throws ArgumentError on empty instance name', () async {
        expect(
          () => MDNSService.create(
            instance: '',
            service: '_http._tcp',
            port: 80,
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError on empty service name', () async {
        expect(
          () => MDNSService.create(
            instance: 'My Service',
            service: '',
            port: 80,
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError on invalid port (0)', () async {
        expect(
          () => MDNSService.create(
            instance: 'My Service',
            service: '_http._tcp',
            port: 0,
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError on invalid port (negative)', () async {
        expect(
          () => MDNSService.create(
            instance: 'My Service',
            service: '_http._tcp',
            port: -1,
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError on invalid port (> 65535)', () async {
        expect(
          () => MDNSService.create(
            instance: 'My Service',
            service: '_http._tcp',
            port: 65536,
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError on invalid domain FQDN', () async {
        expect(
          () => MDNSService.create(
            instance: 'My Service',
            service: '_http._tcp',
            port: 80,
            domain: 'invalid_domain..', // Double dot
          ),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError on invalid hostname FQDN', () async {
        expect(
          () => MDNSService.create(
            instance: 'My Service',
            service: '_http._tcp',
            port: 80,
            hostName: 'host..local', // Invalid format
          ),
          throwsArgumentError,
        );
      });

      test('validates explicit IP addresses', () async {
        final service = await MDNSService.create(
          instance: 'Valid IPs',
          service: '_http._tcp',
          port: 80,
          ips: [InternetAddress('127.0.0.1')],
        );
        expect(service.ips, hasLength(1));
      });
      test('resolves explicit hostname to loopback addresses', () async {
        final service = await MDNSService.create(
          instance: 'Hostname Resolve',
          service: '_http._tcp',
          hostName: 'localhost',
          port: 80,
        );

        expect(service.ips, isNotEmpty);
        expect(service.ips.every((ip) => ip.isLoopback), isTrue);
      });

      test('does not filter link-local IPv6 when explicitly provided',
          () async {
        final service = await MDNSService.create(
          instance: 'Explicit IPs',
          service: '_http._tcp',
          port: 80,
          ips: [
            InternetAddress('fe80::1'),
            InternetAddress('127.0.0.1'),
          ],
        );

        expect(service.ips, hasLength(2));
      });
      test('succeeds when only link-local addresses are provided explicitly',
          () async {
        final service = await MDNSService.create(
          instance: 'Explicit Link-Local',
          service: '_http._tcp',
          port: 80,
          ips: [InternetAddress('fe80::1')],
        );
        expect(service.ips, hasLength(1));
        expect(service.ips.first.isLinkLocal, isTrue);
      });

      test('removes duplicate IP addresses', () async {
        final service = await MDNSService.create(
          instance: 'Duplicate IPs',
          service: '_http._tcp',
          port: 80,
          ips: [
            InternetAddress('127.0.0.1'),
            InternetAddress('127.0.0.1'),
          ],
        );

        expect(service.ips, hasLength(1));
        expect(service.ips.first.isLoopback, isTrue);
      });

      test(
        'throws SocketException when explicit hostname cannot be resolved',
        () async => expect(
          () => MDNSService.create(
            instance: 'Unresolvable Hostname',
            service: '_http._tcp',
            hostName: 'nonexistent.local',
            port: 80,
          ),
          throwsA(isA<SocketException>()),
        ),
      );
    });

    group('Service Enumeration (_serviceEnum)', () {
      test('responds to PTR query for _services._dns-sd._udp.local.', () {
        final question = DNSQuestion(
          name: '_services._dns-sd._udp.local.',
          type: DNSType.PTR,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);
        expect(records, hasLength(1));

        final ptr = records.first as PTRRecord;
        expect(ptr.name, equals('_services._dns-sd._udp.local.'));
        expect(ptr.target, equals('_ipp._tcp.local.'));
        expect(ptr.ttl, equals(120));
      });

      test('responds to ANY query for _services._dns-sd._udp.local.', () {
        final question = DNSQuestion(
          name: '_services._dns-sd._udp.local.',
          type: DNSType.ANY,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);
        expect(records, hasLength(1));
        expect(records.first, isA<PTRRecord>());
      });

      test('returns empty for irrelevant types (e.g., A)', () {
        final question = DNSQuestion(
          name: '_services._dns-sd._udp.local.',
          type: DNSType.A,
          dnsClass: DNSClass.IN,
        );
        expect(service.records(question), isEmpty);
      });
    });
    group('Service Records (_serviceRecords)', () {
      test('responds to PTR query for service type (e.g., _ipp._tcp.local.)',
          () {
        final question = DNSQuestion(
          name: '_ipp._tcp.local.',
          type: DNSType.PTR,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);

        // Should return PTR to instance
        final ptr = records.whereType<PTRRecord>().first;
        expect(ptr.name, equals('_ipp._tcp.local.'));
        expect(ptr.target, equals('My Printer._ipp._tcp.local.'));

        // And recursively include instance records (SRV, TXT)
        expect(records.whereType<SRVRecord>(), isNotEmpty);
        expect(records.whereType<TXTRecord>(), isNotEmpty);
      });

      test('responds to ANY query for service type', () {
        final question = DNSQuestion(
          name: '_ipp._tcp.local.',
          type: DNSType.ANY,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);
        expect(records.whereType<PTRRecord>(), isNotEmpty);
      });
    });
    group('Instance Records (_instanceRecords)', () {
      test('responds to SRV query for instance name', () {
        final question = DNSQuestion(
          name: 'My Printer._ipp._tcp.local.',
          type: DNSType.SRV,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);

        // 1. Check SRV
        final srv = records.whereType<SRVRecord>().first;
        expect(srv.name, equals('My Printer._ipp._tcp.local.'));
        expect(srv.target, equals('printer.local.'));
        expect(srv.port, equals(631));

        // 2. Check Additional Records (A/AAAA)
        expect(records.whereType<ARecord>(), isNotEmpty);
        expect(records.whereType<AAAARecord>(), isNotEmpty);
      });

      test('responds to TXT query for instance name', () {
        final question = DNSQuestion(
          name: 'My Printer._ipp._tcp.local.',
          type: DNSType.TXT,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);
        expect(records, hasLength(1));

        final txt = records.first as TXTRecord;
        expect(txt.name, equals('My Printer._ipp._tcp.local.'));
        expect(txt.strings, containsAll(['txtvers=1', 'note=Office Printer']));
      });

      test('responds to ANY query for instance name (SRV + TXT)', () {
        final question = DNSQuestion(
          name: 'My Printer._ipp._tcp.local.',
          type: DNSType.ANY,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);

        expect(records.whereType<SRVRecord>(), isNotEmpty);
        expect(records.whereType<TXTRecord>(), isNotEmpty);
      });

      test('handles service with no IPs (returns SRV but no additional A/AAAA)',
          () {
        final noIpService = MDNSService(
          instance: 'NoIP',
          service: '_test._tcp.',
          domain: 'local.',
          hostName: 'void.local.',
          port: 80,
          ips: [],
          txt: [],
        );

        final records = noIpService.records(DNSQuestion(
          name: 'NoIP._test._tcp.local.',
          type: DNSType.SRV,
          dnsClass: DNSClass.IN,
        ));

        expect(records.whereType<SRVRecord>(), hasLength(1));
        expect(records.whereType<ARecord>(), isEmpty);
        expect(records.whereType<AAAARecord>(), isEmpty);
      });

      test('handles service with empty TXT', () {
        final emptyTxtService = MDNSService(
          instance: 'EmptyTXT',
          service: '_test._tcp.',
          domain: 'local.',
          hostName: 'host.local.',
          port: 80,
          ips: [ipv4],
          txt: [],
        );

        final records = emptyTxtService.records(DNSQuestion(
          name: 'EmptyTXT._test._tcp.local.',
          type: DNSType.TXT,
          dnsClass: DNSClass.IN,
        ));

        expect(records, hasLength(1));
        final txt = records.first as TXTRecord;
        expect(txt.strings, isEmpty);
      });
    });
    group('Host Records (lookup by hostname)', () {
      test('responds to A query for hostname', () {
        final question = DNSQuestion(
          name: 'printer.local.',
          type: DNSType.A,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);
        final aRecords = records.whereType<ARecord>().toList();

        expect(aRecords, hasLength(1));
        expect(aRecords.first.address, equals('192.168.1.5'));
      });

      test('responds to AAAA query for hostname', () {
        final question = DNSQuestion(
          name: 'printer.local.',
          type: DNSType.AAAA,
          dnsClass: DNSClass.IN,
        );

        final records = service.records(question);
        final aaaaRecords = records.whereType<AAAARecord>().toList();

        expect(aaaaRecords, hasLength(1));
        expect(aaaaRecords.first.address, equals('fe80::1'));
      });

      test('ignores other types for hostname (e.g., PTR)', () {
        final question = DNSQuestion(
          name: 'printer.local.',
          type: DNSType.PTR, // Not valid for hostname direct lookup here
          dnsClass: DNSClass.IN,
        );

        expect(service.records(question), isEmpty);
      });

      test('returns empty AAAA records for IPv4-only service', () {
        final ipv4Service = MDNSService(
          instance: 'IPv4Only',
          service: '_test._tcp.',
          domain: 'local.',
          hostName: 'host.local.',
          port: 80,
          ips: [ipv4],
          txt: [],
        );

        final records = ipv4Service.records(DNSQuestion(
          name: 'host.local.',
          type: DNSType.AAAA,
          dnsClass: DNSClass.IN,
        ));

        expect(records, isEmpty);
      });
    });

    group('Goodbye records', () {
      test('generates all records with TTL=0', () {
        final records = service.goodbyeRecords();

        // Should have PTR + SRV + TXT + A + AAAA = 5 records
        expect(records, hasLength(5));

        // All TTLs must be 0
        for (final record in records) {
          expect(record.ttl, equals(0), reason: '${record.runtimeType} TTL');
        }

        // Verify record types
        expect(records.whereType<PTRRecord>(), hasLength(1));
        expect(records.whereType<SRVRecord>(), hasLength(1));
        expect(records.whereType<TXTRecord>(), hasLength(1));
        expect(records.whereType<ARecord>(), hasLength(1));
        expect(records.whereType<AAAARecord>(), hasLength(1));
      });

      test('MultiServiceZone collects goodbye records from all services', () {
        final zone = MultiServiceZone();
        zone.addService(service);

        final service2 = MDNSService(
          instance: 'Web Server',
          service: '_http._tcp.',
          domain: 'local.',
          hostName: 'web.local.',
          port: 80,
          ips: [InternetAddress('10.0.0.1')],
          txt: ['path=/'],
        );
        zone.addService(service2);

        final records = zone.goodbyeRecords();

        // service1: PTR + SRV + TXT + A + AAAA = 5
        // service2: PTR + SRV + TXT + A = 4
        expect(records, hasLength(9));
        for (final record in records) {
          expect(record.ttl, equals(0));
        }
      });
    });

    group('TXT record helpers', () {
      test('createTXTRecords formats correctly', () {
        final map = {'key1': 'val1', 'key2': ''};
        final txt = MDNSService.createTXTRecords(map);
        expect(txt, equals(['key1=val1', 'key2=']));
      });

      test('parseTXTRecords parses correctly', () {
        final txt = ['key1=val1', 'key2=', 'flag'];
        final map = MDNSService.parseTXTRecords(txt);
        expect(map['key1'], equals('val1'));
        expect(map['key2'], equals(''));
        expect(map['flag'], equals(''));
      });
    });
  });
}
