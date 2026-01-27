import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:mdns_dart/mdns_dart.dart';

void main() {
  group('ByteDataWriter', () {
    test('writes uint8 values correctly', () {
      final writer = ByteDataWriter();
      writer.writeUint8(0);
      writer.writeUint8(128);
      writer.writeUint8(255);

      expect(writer.toBytes(), equals([0, 128, 255]));
    });

    test('writes uint16 values correctly (big-endian)', () {
      final writer = ByteDataWriter();
      writer.writeUint16(0);
      writer.writeUint16(0x1234);
      writer.writeUint16(0xFFFF);

      expect(writer.toBytes(), equals([0x00, 0x00, 0x12, 0x34, 0xFF, 0xFF]));
    });

    test('writes uint32 values correctly (big-endian)', () {
      final writer = ByteDataWriter();
      writer.writeUint32(0);
      writer.writeUint32(0x12345678);
      writer.writeUint32(0xFFFFFFFF);

      expect(
        writer.toBytes(),
        equals([
          0x00, 0x00, 0x00, 0x00, // 0x00000000
          0x12, 0x34, 0x56, 0x78, // 0x12345678
          0xFF, 0xFF, 0xFF, 0xFF, // 0xFFFFFFFF
        ]),
      );
    });

    test('writes bytes correctly', () {
      final writer = ByteDataWriter();
      writer.writeBytes(Uint8List.fromList([1, 2, 3]));
      writer.writeBytes(Uint8List.fromList([4, 5]));

      expect(writer.toBytes(), equals([1, 2, 3, 4, 5]));
    });

    test('handles mixed writes', () {
      final writer = ByteDataWriter();
      writer.writeUint8(0xAA);
      writer.writeUint16(0xBBCC);
      writer.writeUint32(0xDDEEFF00);

      expect(
        writer.toBytes(),
        equals([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00]),
      );
    });
  });

  group('ByteDataReader', () {
    test('reads uint8 values correctly', () {
      final data = Uint8List.fromList([0, 128, 255]);
      final reader = ByteDataReader(data);

      expect(reader.readUint8(), equals(0));
      expect(reader.readUint8(), equals(128));
      expect(reader.readUint8(), equals(255));
    });

    test('reads uint16 values correctly (big-endian)', () {
      final data = Uint8List.fromList([0x00, 0x00, 0x12, 0x34, 0xFF, 0xFF]);
      final reader = ByteDataReader(data);

      expect(reader.readUint16(), equals(0));
      expect(reader.readUint16(), equals(0x1234));
      expect(reader.readUint16(), equals(0xFFFF));
    });

    test('reads uint32 values correctly (big-endian)', () {
      final data = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x00, // 0x00000000
        0x12, 0x34, 0x56, 0x78, // 0x12345678
        0xFF, 0xFF, 0xFF, 0xFF, // 0xFFFFFFFF
      ]);
      final reader = ByteDataReader(data);

      expect(reader.readUint32(), equals(0));
      expect(reader.readUint32(), equals(0x12345678));
      expect(reader.readUint32(), equals(0xFFFFFFFF));
    });

    test('reads bytes correctly', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final reader = ByteDataReader(data);

      expect(reader.readBytes(3), equals([1, 2, 3]));
      expect(reader.readBytes(2), equals([4, 5]));
    });

    test('handles seek and skip', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final reader = ByteDataReader(data);

      reader.skip(2);
      expect(reader.readUint8(), equals(3));

      reader.seek(0);
      expect(reader.readUint8(), equals(1));

      reader.seek(4);
      expect(reader.readUint8(), equals(5));
    });

    test('tracks offset and remaining length', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final reader = ByteDataReader(data);

      expect(reader.offset, equals(0));
      expect(reader.remainingLength, equals(5));

      reader.readUint16();
      expect(reader.offset, equals(2));
      expect(reader.remainingLength, equals(3));
    });

    test('throws on buffer underflow', () {
      final data = Uint8List.fromList([1, 2]);
      final reader = ByteDataReader(data);

      reader.readUint16(); // OK
      expect(() => reader.readUint8(), throwsA(isA<RangeError>()));
    });
  });

  group('DNSResourceRecord', () {
    test('A Record read/write cycle', () {
      final original = ARecord(
        name: 'example.com.',
        address: '1.2.3.4',
        ttl: 120,
      );

      final writer = ByteDataWriter();
      original.writeTo(writer);
      final bytes = writer.toBytes();

      final reader = ByteDataReader(bytes);
      final parsed = DNSResourceRecord.parse(reader);

      expect(parsed, isA<ARecord>());
      final aRecord = parsed as ARecord;
      expect(aRecord.name, equals('example.com'));
      expect(aRecord.address, equals('1.2.3.4'));
      expect(aRecord.ttl, equals(120));
      expect(aRecord.type, equals(DNSType.A));
    });

    test('ARecord handles boundary IP addresses', () {
      final addresses = ['0.0.0.0', '255.255.255.255'];
      for (final addr in addresses) {
        final original = ARecord(
          name: 'example.com.',
          address: addr,
          ttl: 120,
        );
        final writer = ByteDataWriter();
        original.writeTo(writer);
        final parsed =
            DNSResourceRecord.parse(ByteDataReader(writer.toBytes()));
        expect(parsed, isA<ARecord>());
        expect((parsed as ARecord).address, equals(addr));
      }
    });

    test('AAAA Record read/write cycle', () {
      final original = AAAARecord(
        name: 'example.com.',
        address: '2001:db8:0:0:0:0:0:1',
        ttl: 300,
      );

      final writer = ByteDataWriter();
      original.writeTo(writer);
      final bytes = writer.toBytes();

      final reader = ByteDataReader(bytes);
      final parsed = DNSResourceRecord.parse(reader);

      expect(parsed, isA<AAAARecord>());
      final aaaaRecord = parsed as AAAARecord;
      expect(aaaaRecord.name, equals('example.com'));
      expect(aaaaRecord.address.toLowerCase(), equals('2001:db8:0:0:0:0:0:1'));
      expect(aaaaRecord.type, equals(DNSType.AAAA));
    });

    test('AAAARecord handles boundary IP addresses', () {
      final addresses = {
        '::': '0:0:0:0:0:0:0:0',
        '::1': '0:0:0:0:0:0:0:1',
        'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff':
            'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
      };

      addresses.forEach((input, expected) {
        final original = AAAARecord(
          name: 'example.com.',
          address: input,
          ttl: 300,
        );
        final writer = ByteDataWriter();
        original.writeTo(writer);
        final parsed =
            DNSResourceRecord.parse(ByteDataReader(writer.toBytes()));
        expect(parsed, isA<AAAARecord>());
        // Note: AAAARecord parsing normalizes to fully expanded form in current implementation logic
        // The test expects the normalized form that the parser produces
        expect((parsed as AAAARecord).address.toLowerCase(), equals(expected));
      });
    });

    test('PTR Record read/write cycle', () {
      final original = PTRRecord(
        name: '_http._tcp.local.',
        target: 'My Service._http._tcp.local.',
        ttl: 4500,
      );

      final writer = ByteDataWriter();
      original.writeTo(writer);
      final bytes = writer.toBytes();

      final reader = ByteDataReader(bytes);
      final parsed = DNSResourceRecord.parse(reader);

      expect(parsed, isA<PTRRecord>());
      final ptrRecord = parsed as PTRRecord;
      expect(ptrRecord.name, equals('_http._tcp.local'));
      expect(ptrRecord.target, equals('My Service._http._tcp.local'));
      expect(ptrRecord.type, equals(DNSType.PTR));
    });

    test('SRV Record read/write cycle', () {
      final original = SRVRecord(
        name: 'My Service._http._tcp.local.',
        target: 'my-host.local.',
        port: 8080,
        priority: 10,
        weight: 20,
        ttl: 120,
      );

      final writer = ByteDataWriter();
      original.writeTo(writer);
      final bytes = writer.toBytes();

      final reader = ByteDataReader(bytes);
      final parsed = DNSResourceRecord.parse(reader);

      expect(parsed, isA<SRVRecord>());
      final srvRecord = parsed as SRVRecord;
      expect(srvRecord.name, equals('My Service._http._tcp.local'));
      expect(srvRecord.target, equals('my-host.local'));
      expect(srvRecord.port, equals(8080));
      expect(srvRecord.priority, equals(10));
      expect(srvRecord.weight, equals(20));
      expect(srvRecord.type, equals(DNSType.SRV));
    });

    test('TXT Record read/write cycle', () {
      final original = TXTRecord(
        name: 'service.local.',
        strings: ['key1=value1', 'key2=value2'],
        ttl: 60,
      );

      final writer = ByteDataWriter();
      original.writeTo(writer);
      final bytes = writer.toBytes();

      final reader = ByteDataReader(bytes);
      final parsed = DNSResourceRecord.parse(reader);

      expect(parsed, isA<TXTRecord>());
      final txtRecord = parsed as TXTRecord;
      expect(txtRecord.name, equals('service.local'));
      expect(txtRecord.strings, equals(['key1=value1', 'key2=value2']));
      expect(txtRecord.type, equals(DNSType.TXT));
    });

    test('NSEC Record read/write cycle', () {
      // NSEC records are used to prove non-existence of records
      final original = NSECRecord(
        name: 'example.com.',
        nextDomainName: 'next.example.com.',
        types: [DNSType.A, DNSType.MX, DNSType.PTR, DNSType.NSEC],
        ttl: 3600,
      );

      final writer = ByteDataWriter();
      original.writeTo(writer);
      final bytes = writer.toBytes();

      final reader = ByteDataReader(bytes);
      final parsed = DNSResourceRecord.parse(reader);

      expect(parsed, isA<NSECRecord>());
      final nsecRecord = parsed as NSECRecord;
      expect(nsecRecord.name, equals('example.com'));
      expect(nsecRecord.nextDomainName, equals('next.example.com'));
      expect(
        nsecRecord.types,
        containsAll([DNSType.A, DNSType.MX, DNSType.PTR, DNSType.NSEC]),
      );
      expect(nsecRecord.type, equals(DNSType.NSEC));
    });

    test('Parses unknown record types gracefully (skips them)', () {
      // Construct a fake record with an unknown type (e.g. 9999)
      final writer = ByteDataWriter();

      // Name: test.local.
      writer.writeUint8(4);
      writer.writeBytes(Uint8List.fromList('test'.codeUnits));
      writer.writeUint8(5);
      writer.writeBytes(Uint8List.fromList('local'.codeUnits));
      writer.writeUint8(0);

      writer.writeUint16(9999); // Unknown type
      writer.writeUint16(DNSClass.IN); // Class IN
      writer.writeUint32(120); // TTL
      writer.writeUint16(4); // RDLENGTH
      writer.writeBytes(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])); // RDATA

      final bytes = writer.toBytes();
      final reader = ByteDataReader(bytes);

      final parsed = DNSResourceRecord.parse(reader);
      expect(parsed, isNull);

      // Verify we skipped the record correctly by checking if we are at the end
      expect(reader.remainingLength, equals(0));
    });
  });

  group('DNSQuestion', () {
    test('read/write cycle', () {
      final original = DNSQuestion(
        name: '_http._tcp.local.',
        type: DNSType.PTR,
        dnsClass: DNSClass.IN,
      );

      final writer = ByteDataWriter();
      original.writeTo(writer);
      final bytes = writer.toBytes();

      final reader = ByteDataReader(bytes);
      final parsed = DNSQuestion.parse(reader);

      expect(parsed, isNotNull);
      expect(parsed!.name, equals('_http._tcp.local'));
      expect(parsed.type, equals(DNSType.PTR));
      expect(parsed.dnsClass, equals(DNSClass.IN));
    });

    test('unicast response bit', () {
      final question = DNSQuestion(
        name: 'test.local.',
        type: DNSType.A,
        dnsClass: DNSClass.IN | 0x8000,
      );

      expect(question.wantsUnicastResponse, isTrue);
      expect(question.classCode, equals(DNSClass.IN));
    });
    test('detects infinite compression loops', () {
      final writer = ByteDataWriter();
      // Write a pointer that points to itself (offset 0)
      // 0xC000 = Pointer to offset 0
      writer.writeUint8(0xC0);
      writer.writeUint8(0x00);

      final reader = ByteDataReader(writer.toBytes());
      final result = DNSQuestion.parse(reader);
      expect(result, isNull);
    });
  });

  group('DNSHeader', () {
    test('read/write cycle', () {
      final original = DNSHeader(
        id: 0x1234,
        flags: DNSFlags.QR | DNSFlags.AA,
        qdcount: 1,
        ancount: 2,
        nscount: 3,
        arcount: 4,
      );

      final writer = ByteDataWriter();
      original.writeTo(writer);
      final bytes = writer.toBytes();

      final reader = ByteDataReader(bytes);
      final parsed = DNSHeader.parse(reader);

      expect(parsed, isNotNull);
      expect(parsed!.id, equals(0x1234));
      expect(parsed.flags, equals(DNSFlags.QR | DNSFlags.AA));
      expect(parsed.qdcount, equals(1));
      expect(parsed.ancount, equals(2));
      expect(parsed.nscount, equals(3));
      expect(parsed.arcount, equals(4));
    });

    test('flag helpers', () {
      final header = DNSHeader(
        id: 0,
        flags:
            DNSFlags.QR | DNSFlags.AA | DNSFlags.TC | DNSFlags.RD | DNSFlags.RA,
        qdcount: 0,
        ancount: 0,
        nscount: 0,
        arcount: 0,
      );

      expect(header.isResponse, isTrue);
      expect(header.isQuery, isFalse);
      expect(header.isAuthoritative, isTrue);
      expect(header.isTruncated, isTrue);
      expect(header.recursionDesired, isTrue);
      expect(header.recursionAvailable, isTrue);
    });
  });

  group('DNSMessage', () {
    test('query creation', () {
      final msg = DNSMessage.query(
        id: 100,
        name: '_http._tcp.local.',
        type: DNSType.PTR,
      );

      expect(msg.header.id, equals(100));
      expect(msg.header.isQuery, isTrue);
      expect(msg.questions, hasLength(1));
      expect(msg.questions.first.name, equals('_http._tcp.local.'));
    });

    test('response creation', () {
      final answer = ARecord(
        name: 'host.local.',
        address: '1.2.3.4',
        ttl: 120,
      );
      final msg = DNSMessage.response(
        id: 200,
        answers: [answer],
      );

      expect(msg.header.id, equals(200));
      expect(msg.header.isResponse, isTrue);
      expect(msg.answers, hasLength(1));
      expect(msg.answers.first.name, equals('host.local.'));
    });

    test('pack and parse cycle', () {
      final msg = DNSMessage.query(
        id: 123,
        name: 'test.local.',
        type: DNSType.A,
      );

      final bytes = msg.pack();
      final parsed = DNSMessage.parse(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.header.id, equals(123));
      expect(parsed.questions, hasLength(1));
      expect(parsed.questions.first.name, equals('test.local'));
    });
    test('handles out-of-bounds pointers', () {
      final writer = ByteDataWriter();
      // 0xC0FF = Pointer to offset 255 (beyond buffer)
      writer.writeUint8(0xC0);
      writer.writeUint8(0xFF);

      final result = DNSMessage.parse(writer.toBytes());
      expect(result, isNull);
    });

    test('handles truncated header', () {
      final bytes = Uint8List.fromList([0, 1, 2]); // Less than 12 bytes
      final msg = DNSMessage.parse(bytes);
      expect(msg, isNull);
    });

    test('handles truncated label length', () {
      final writer = ByteDataWriter();
      final header = DNSHeader(
        id: 1,
        flags: 0,
        qdcount: 1,
        ancount: 0,
        nscount: 0,
        arcount: 0,
      );
      header.writeTo(writer);

      // Question Name: Label of length 10, but ends immediately
      writer.writeUint8(10);

      final msg = DNSMessage.parse(writer.toBytes());
      expect(msg, isNull);
    });

    test('handles truncated compression pointer', () {
      final writer = ByteDataWriter();
      // Header: qdcount=1
      final header = DNSHeader(
        id: 1,
        flags: 0,
        qdcount: 1,
        ancount: 0,
        nscount: 0,
        arcount: 0,
      );
      header.writeTo(writer);

      // 0xC0 indicates pointer, but missing 2nd byte
      writer.writeUint8(0xC0);

      final msg = DNSMessage.parse(writer.toBytes());
      expect(msg, isNull);
    });

    test('handles RDLENGTH exceeding buffer', () {
      final writer = ByteDataWriter();
      // Valid Header: 1 Answer
      final header = DNSHeader(
        id: 1,
        flags: 0,
        qdcount: 0,
        ancount: 1,
        nscount: 0,
        arcount: 0,
      );
      header.writeTo(writer);

      // Answer Record
      writer.writeUint8(1);
      writer.writeUint8(97); // 'a'
      writer.writeUint8(0);
      writer.writeUint16(DNSType.A);
      writer.writeUint16(DNSClass.IN);
      writer.writeUint32(120);
      // RDLENGTH: 100 bytes (but buffer ends)
      writer.writeUint16(100);

      final msg = DNSMessage.parse(writer.toBytes());
      expect(msg, isNull);
    });

    test('handles record count mismatch (claims records but EOF)', () {
      final writer = ByteDataWriter();
      // Header claims 5 questions, but provided 0
      final header = DNSHeader(
        id: 1,
        flags: 0,
        qdcount: 5,
        ancount: 0,
        nscount: 0,
        arcount: 0,
      );
      header.writeTo(writer);

      final msg = DNSMessage.parse(writer.toBytes());
      expect(msg, isNull);
    });
  });
}
