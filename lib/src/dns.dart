/// DNS message format definitions and utilities for mDNS operations.
/// 
/// This module provides comprehensive DNS message parsing and building
/// capabilities, supporting all standard DNS record types used in mDNS.
library;

import 'dart:typed_data';

/// DNS record types used in mDNS operations
class DNSType {
  static const int A = 1;
  static const int NS = 2;
  static const int CNAME = 5;
  static const int SOA = 6;
  static const int PTR = 12;
  static const int MX = 15;
  static const int TXT = 16;
  static const int AAAA = 28;
  static const int SRV = 33;
  static const int OPT = 41;
  static const int ANY = 255;
}

/// DNS class types
class DNSClass {
  static const int IN = 1;
  static const int CS = 2;
  static const int CH = 3;
  static const int HS = 4;
  static const int NONE = 254;
  static const int ANY = 255;
  
  /// Cache flush bit for mDNS (RFC 6762)
  static const int FLUSH = 0x8000;
}

/// DNS message header flags
class DNSFlags {
  static const int QR = 0x8000;        // Query/Response
  static const int AA = 0x0400;        // Authoritative Answer
  static const int TC = 0x0200;        // Truncated
  static const int RD = 0x0100;        // Recursion Desired
  static const int RA = 0x0080;        // Recursion Available
  static const int AD = 0x0020;        // Authentic Data
  static const int CD = 0x0010;        // Checking Disabled
  
  // Response codes
  static const int NOERROR = 0;
  static const int FORMERR = 1;
  static const int SERVFAIL = 2;
  static const int NXDOMAIN = 3;
  static const int NOTIMP = 4;
  static const int REFUSED = 5;
}

/// Represents a complete DNS message
class DNSMessage {
  final DNSHeader header;
  final List<DNSQuestion> questions;
  final List<DNSResourceRecord> answers;
  final List<DNSResourceRecord> authority;
  final List<DNSResourceRecord> additional;

  DNSMessage({
    required this.header,
    required this.questions,
    required this.answers,
    required this.authority,
    required this.additional,
  });

  /// Creates a DNS query message
  factory DNSMessage.query({
    required int id,
    required String name,
    required int type,
    int dnsClass = DNSClass.IN,
    bool unicastResponse = false,
  }) {
    final header = DNSHeader(
      id: id,
      flags: 0, // Standard query
      qdcount: 1,
      ancount: 0,
      nscount: 0,
      arcount: 0,
    );

    final question = DNSQuestion(
      name: name,
      type: type,
      dnsClass: unicastResponse ? (dnsClass | 0x8000) : dnsClass,
    );

    return DNSMessage(
      header: header,
      questions: [question],
      answers: [],
      authority: [],
      additional: [],
    );
  }

  /// Creates a DNS response message
  factory DNSMessage.response({
    required int id,
    required List<DNSResourceRecord> answers,
    List<DNSResourceRecord> additional = const [],
    bool authoritative = true,
  }) {
    final header = DNSHeader(
      id: id,
      flags: DNSFlags.QR | (authoritative ? DNSFlags.AA : 0),
      qdcount: 0,
      ancount: answers.length,
      nscount: 0,
      arcount: additional.length,
    );

    return DNSMessage(
      header: header,
      questions: [],
      answers: answers,
      authority: [],
      additional: additional,
    );
  }

  /// Packs the DNS message into binary format
  Uint8List pack() {
    final buffer = ByteDataWriter();
    
    // Write header
    header.writeTo(buffer);
    
    // Write questions
    for (final question in questions) {
      question.writeTo(buffer);
    }
    
    // Write answers
    for (final answer in answers) {
      answer.writeTo(buffer);
    }
    
    // Write authority records
    for (final auth in authority) {
      auth.writeTo(buffer);
    }
    
    // Write additional records
    for (final add in additional) {
      add.writeTo(buffer);
    }
    
    return buffer.toBytes();
  }

  /// Parses a DNS message from binary data
  static DNSMessage? parse(Uint8List data) {
    if (data.length < 12) return null;
    
    try {
      final reader = ByteDataReader(data);
      
      // Parse header
      final header = DNSHeader.parse(reader);
      if (header == null) return null;
      
      // Parse questions
      final questions = <DNSQuestion>[];
      for (int i = 0; i < header.qdcount; i++) {
        final question = DNSQuestion.parse(reader);
        if (question == null) return null;
        questions.add(question);
      }
      
      // Parse answers
      final answers = <DNSResourceRecord>[];
      for (int i = 0; i < header.ancount; i++) {
        final answer = DNSResourceRecord.parse(reader);
        if (answer == null) return null;
        answers.add(answer);
      }
      
      // Parse authority
      final authority = <DNSResourceRecord>[];
      for (int i = 0; i < header.nscount; i++) {
        final auth = DNSResourceRecord.parse(reader);
        if (auth == null) return null;
        authority.add(auth);
      }
      
      // Parse additional
      final additional = <DNSResourceRecord>[];
      for (int i = 0; i < header.arcount; i++) {
        final add = DNSResourceRecord.parse(reader);
        if (add == null) return null;
        additional.add(add);
      }
      
      return DNSMessage(
        header: header,
        questions: questions,
        answers: answers,
        authority: authority,
        additional: additional,
      );
    } catch (e) {
      return null;
    }
  }
}

/// DNS message header
class DNSHeader {
  final int id;
  final int flags;
  final int qdcount;
  final int ancount;
  final int nscount;
  final int arcount;

  DNSHeader({
    required this.id,
    required this.flags,
    required this.qdcount,
    required this.ancount,
    required this.nscount,
    required this.arcount,
  });

  void writeTo(ByteDataWriter writer) {
    writer.writeUint16(id);
    writer.writeUint16(flags);
    writer.writeUint16(qdcount);
    writer.writeUint16(ancount);
    writer.writeUint16(nscount);
    writer.writeUint16(arcount);
  }

  static DNSHeader? parse(ByteDataReader reader) {
    if (reader.remainingLength < 12) return null;
    
    return DNSHeader(
      id: reader.readUint16(),
      flags: reader.readUint16(),
      qdcount: reader.readUint16(),
      ancount: reader.readUint16(),
      nscount: reader.readUint16(),
      arcount: reader.readUint16(),
    );
  }

  bool get isQuery => (flags & DNSFlags.QR) == 0;
  bool get isResponse => (flags & DNSFlags.QR) != 0;
  bool get isAuthoritative => (flags & DNSFlags.AA) != 0;
  bool get isTruncated => (flags & DNSFlags.TC) != 0;
  bool get recursionDesired => (flags & DNSFlags.RD) != 0;
  bool get recursionAvailable => (flags & DNSFlags.RA) != 0;
  int get responseCode => flags & 0x000F;
}

/// DNS question section
class DNSQuestion {
  final String name;
  final int type;
  final int dnsClass;

  DNSQuestion({
    required this.name,
    required this.type,
    required this.dnsClass,
  });

  void writeTo(ByteDataWriter writer) {
    _writeDomainName(writer, name);
    writer.writeUint16(type);
    writer.writeUint16(dnsClass);
  }

  static DNSQuestion? parse(ByteDataReader reader) {
    final name = _readDomainName(reader);
    if (name == null || reader.remainingLength < 4) return null;
    
    final type = reader.readUint16();
    final dnsClass = reader.readUint16();
    
    return DNSQuestion(
      name: name,
      type: type,
      dnsClass: dnsClass,
    );
  }

  bool get wantsUnicastResponse => (dnsClass & 0x8000) != 0;
  int get classCode => dnsClass & 0x7FFF;
}

/// Base class for DNS resource records
abstract class DNSResourceRecord {
  final String name;
  final int type;
  final int dnsClass;
  final int ttl;

  DNSResourceRecord({
    required this.name,
    required this.type,
    required this.dnsClass,
    required this.ttl,
  });

  /// Writes the record to the buffer
  void writeTo(ByteDataWriter writer);

  /// Gets the RDATA for this record
  Uint8List get rdata;

  /// Parses a resource record from the reader
  static DNSResourceRecord? parse(ByteDataReader reader) {
    final name = _readDomainName(reader);
    if (name == null || reader.remainingLength < 10) return null;
    
    final type = reader.readUint16();
    final dnsClass = reader.readUint16();
    final ttl = reader.readUint32();
    final rdLength = reader.readUint16();
    
    if (reader.remainingLength < rdLength) return null;
    
    final rdataStart = reader.offset;
    
    DNSResourceRecord? record;
    switch (type) {
      case DNSType.A:
        record = ARecord.parseRData(reader, name, dnsClass, ttl, rdLength);
        break;
      case DNSType.AAAA:
        record = AAAARecord.parseRData(reader, name, dnsClass, ttl, rdLength);
        break;
      case DNSType.PTR:
        record = PTRRecord.parseRData(reader, name, dnsClass, ttl, rdLength);
        break;
      case DNSType.SRV:
        record = SRVRecord.parseRData(reader, name, dnsClass, ttl, rdLength);
        break;
      case DNSType.TXT:
        record = TXTRecord.parseRData(reader, name, dnsClass, ttl, rdLength);
        break;
      default:
        // Skip unknown record types
        reader.skip(rdLength);
        return null;
    }
    
    // Ensure we consumed exactly rdLength bytes
    final consumed = reader.offset - rdataStart;
    if (consumed != rdLength) {
      reader.skip(rdLength - consumed);
    }
    
    return record;
  }

  bool get cacheFlush => (dnsClass & DNSClass.FLUSH) != 0;
  int get classCode => dnsClass & 0x7FFF;
}

/// A record (IPv4 address)
class ARecord extends DNSResourceRecord {
  final String address;

  ARecord({
    required super.name,
    required this.address,
    super.dnsClass = DNSClass.IN,
    super.ttl = 120,
  }) : super(type: DNSType.A);

  @override
  void writeTo(ByteDataWriter writer) {
    _writeDomainName(writer, name);
    writer.writeUint16(type);
    writer.writeUint16(dnsClass);
    writer.writeUint32(ttl);
    writer.writeUint16(4); // RDLENGTH
    
    final parts = address.split('.');
    for (final part in parts) {
      writer.writeUint8(int.parse(part));
    }
  }

  @override
  Uint8List get rdata {
    final parts = address.split('.');
    return Uint8List.fromList(parts.map((p) => int.parse(p)).toList());
  }

  static ARecord? parseRData(ByteDataReader reader, String name, int dnsClass, int ttl, int rdLength) {
    if (rdLength != 4) return null;
    
    final a = reader.readUint8();
    final b = reader.readUint8();
    final c = reader.readUint8();
    final d = reader.readUint8();
    
    return ARecord(
      name: name,
      address: '$a.$b.$c.$d',
      dnsClass: dnsClass,
      ttl: ttl,
    );
  }
}

/// AAAA record (IPv6 address)
class AAAARecord extends DNSResourceRecord {
  final String address;

  AAAARecord({
    required super.name,
    required this.address,
    super.dnsClass = DNSClass.IN,
    super.ttl = 120,
  }) : super(type: DNSType.AAAA);

  @override
  void writeTo(ByteDataWriter writer) {
    _writeDomainName(writer, name);
    writer.writeUint16(type);
    writer.writeUint16(dnsClass);
    writer.writeUint32(ttl);
    writer.writeUint16(16); // RDLENGTH
    
    // Parse IPv6 address and write 16 bytes
    final parts = address.split(':');
    final bytes = <int>[];
    
    // Handle IPv6 address parsing (simplified)
    for (int i = 0; i < 8; i++) {
      final part = i < parts.length ? parts[i] : '0';
      final value = int.parse(part.isEmpty ? '0' : part, radix: 16);
      bytes.add((value >> 8) & 0xFF);
      bytes.add(value & 0xFF);
    }
    
    for (final byte in bytes) {
      writer.writeUint8(byte);
    }
  }

  @override
  Uint8List get rdata {
    // Simplified IPv6 encoding
    final parts = address.split(':');
    final bytes = <int>[];
    
    for (int i = 0; i < 8; i++) {
      final part = i < parts.length ? parts[i] : '0';
      final value = int.parse(part.isEmpty ? '0' : part, radix: 16);
      bytes.add((value >> 8) & 0xFF);
      bytes.add(value & 0xFF);
    }
    
    return Uint8List.fromList(bytes);
  }

  static AAAARecord? parseRData(ByteDataReader reader, String name, int dnsClass, int ttl, int rdLength) {
    if (rdLength != 16) return null;
    
    final bytes = reader.readBytes(16);
    final parts = <String>[];
    
    for (int i = 0; i < 16; i += 2) {
      final value = (bytes[i] << 8) | bytes[i + 1];
      parts.add(value.toRadixString(16));
    }
    
    return AAAARecord(
      name: name,
      address: parts.join(':'),
      dnsClass: dnsClass,
      ttl: ttl,
    );
  }
}

/// PTR record (pointer)
class PTRRecord extends DNSResourceRecord {
  final String target;

  PTRRecord({
    required super.name,
    required this.target,
    super.dnsClass = DNSClass.IN,
    super.ttl = 120,
  }) : super(type: DNSType.PTR);

  @override
  void writeTo(ByteDataWriter writer) {
    _writeDomainName(writer, name);
    writer.writeUint16(type);
    writer.writeUint16(dnsClass);
    writer.writeUint32(ttl);
    
    final rdataWriter = ByteDataWriter();
    _writeDomainName(rdataWriter, target);
    final rdataBytes = rdataWriter.toBytes();
    
    writer.writeUint16(rdataBytes.length);
    writer.writeBytes(rdataBytes);
  }

  @override
  Uint8List get rdata {
    final writer = ByteDataWriter();
    _writeDomainName(writer, target);
    return writer.toBytes();
  }

  static PTRRecord? parseRData(ByteDataReader reader, String name, int dnsClass, int ttl, int rdLength) {
    final startOffset = reader.offset;
    final target = _readDomainName(reader);
    if (target == null) return null;
    
    return PTRRecord(
      name: name,
      target: target,
      dnsClass: dnsClass,
      ttl: ttl,
    );
  }
}

/// SRV record (service)
class SRVRecord extends DNSResourceRecord {
  final int priority;
  final int weight;
  final int port;
  final String target;

  SRVRecord({
    required super.name,
    required this.priority,
    required this.weight,
    required this.port,
    required this.target,
    super.dnsClass = DNSClass.IN,
    super.ttl = 120,
  }) : super(type: DNSType.SRV);

  @override
  void writeTo(ByteDataWriter writer) {
    _writeDomainName(writer, name);
    writer.writeUint16(type);
    writer.writeUint16(dnsClass);
    writer.writeUint32(ttl);
    
    final rdataWriter = ByteDataWriter();
    rdataWriter.writeUint16(priority);
    rdataWriter.writeUint16(weight);
    rdataWriter.writeUint16(port);
    _writeDomainName(rdataWriter, target);
    final rdataBytes = rdataWriter.toBytes();
    
    writer.writeUint16(rdataBytes.length);
    writer.writeBytes(rdataBytes);
  }

  @override
  Uint8List get rdata {
    final writer = ByteDataWriter();
    writer.writeUint16(priority);
    writer.writeUint16(weight);
    writer.writeUint16(port);
    _writeDomainName(writer, target);
    return writer.toBytes();
  }

  static SRVRecord? parseRData(ByteDataReader reader, String name, int dnsClass, int ttl, int rdLength) {
    if (rdLength < 6) return null;
    
    final priority = reader.readUint16();
    final weight = reader.readUint16();
    final port = reader.readUint16();
    final target = _readDomainName(reader);
    if (target == null) return null;
    
    return SRVRecord(
      name: name,
      priority: priority,
      weight: weight,
      port: port,
      target: target,
      dnsClass: dnsClass,
      ttl: ttl,
    );
  }
}

/// TXT record (text data)
class TXTRecord extends DNSResourceRecord {
  final List<String> strings;

  TXTRecord({
    required super.name,
    required this.strings,
    super.dnsClass = DNSClass.IN,
    super.ttl = 120,
  }) : super(type: DNSType.TXT);

  @override
  void writeTo(ByteDataWriter writer) {
    _writeDomainName(writer, name);
    writer.writeUint16(type);
    writer.writeUint16(dnsClass);
    writer.writeUint32(ttl);
    
    final rdataWriter = ByteDataWriter();
    for (final str in strings) {
      final bytes = str.codeUnits;
      rdataWriter.writeUint8(bytes.length);
      for (final byte in bytes) {
        rdataWriter.writeUint8(byte);
      }
    }
    final rdataBytes = rdataWriter.toBytes();
    
    writer.writeUint16(rdataBytes.length);
    writer.writeBytes(rdataBytes);
  }

  @override
  Uint8List get rdata {
    final writer = ByteDataWriter();
    for (final str in strings) {
      final bytes = str.codeUnits;
      writer.writeUint8(bytes.length);
      for (final byte in bytes) {
        writer.writeUint8(byte);
      }
    }
    return writer.toBytes();
  }

  static TXTRecord? parseRData(ByteDataReader reader, String name, int dnsClass, int ttl, int rdLength) {
    final strings = <String>[];
    final endOffset = reader.offset + rdLength;
    
    while (reader.offset < endOffset) {
      final length = reader.readUint8();
      if (reader.offset + length > endOffset) break;
      
      final bytes = reader.readBytes(length);
      strings.add(String.fromCharCodes(bytes));
    }
    
    return TXTRecord(
      name: name,
      strings: strings,
      dnsClass: dnsClass,
      ttl: ttl,
    );
  }
}

// Helper functions for domain name encoding/decoding

void _writeDomainName(ByteDataWriter writer, String name) {
  final labels = name.split('.');
  
  for (final label in labels) {
    if (label.isNotEmpty) {
      writer.writeUint8(label.length);
      for (final char in label.codeUnits) {
        writer.writeUint8(char);
      }
    }
  }
  writer.writeUint8(0); // End of name
}

String? _readDomainName(ByteDataReader reader) {
  final labels = <String>[];
  final visitedOffsets = <int>{};
  bool jumped = false;
  int? returnOffset;
  
  while (reader.remainingLength > 0) {
    final length = reader.readUint8();
    
    if (length == 0) {
      // End of name
      if (jumped && returnOffset != null) {
        reader.seek(returnOffset);
      }
      return labels.join('.');
    } else if ((length & 0xC0) == 0xC0) {
      // Pointer
      if (reader.remainingLength < 1) return null;
      
      final pointer = ((length & 0x3F) << 8) | reader.readUint8();
      
      if (visitedOffsets.contains(pointer)) {
        return null; // Infinite loop
      }
      visitedOffsets.add(pointer);
      
      if (!jumped) {
        returnOffset = reader.offset;
        jumped = true;
      }
      
      reader.seek(pointer);
    } else {
      // Regular label
      if (reader.remainingLength < length) return null;
      
      final labelBytes = reader.readBytes(length);
      labels.add(String.fromCharCodes(labelBytes));
    }
  }
  
  return null;
}

// Utility classes for reading/writing binary data

class ByteDataWriter {
  final List<int> _buffer = [];

  void writeUint8(int value) {
    _buffer.add(value & 0xFF);
  }

  void writeUint16(int value) {
    _buffer.add((value >> 8) & 0xFF);
    _buffer.add(value & 0xFF);
  }

  void writeUint32(int value) {
    _buffer.add((value >> 24) & 0xFF);
    _buffer.add((value >> 16) & 0xFF);
    _buffer.add((value >> 8) & 0xFF);
    _buffer.add(value & 0xFF);
  }

  void writeBytes(Uint8List bytes) {
    _buffer.addAll(bytes);
  }

  Uint8List toBytes() => Uint8List.fromList(_buffer);
}

class ByteDataReader {
  final Uint8List _data;
  int _offset = 0;

  ByteDataReader(this._data);

  int get offset => _offset;
  int get remainingLength => _data.length - _offset;

  void seek(int offset) {
    _offset = offset;
  }

  void skip(int bytes) {
    _offset += bytes;
  }

  int readUint8() {
    if (_offset >= _data.length) throw RangeError('Buffer underflow');
    return _data[_offset++];
  }

  int readUint16() {
    if (_offset + 1 >= _data.length) throw RangeError('Buffer underflow');
    final value = (_data[_offset] << 8) | _data[_offset + 1];
    _offset += 2;
    return value;
  }

  int readUint32() {
    if (_offset + 3 >= _data.length) throw RangeError('Buffer underflow');
    final value = (_data[_offset] << 24) |
                  (_data[_offset + 1] << 16) |
                  (_data[_offset + 2] << 8) |
                  _data[_offset + 3];
    _offset += 4;
    return value;
  }

  Uint8List readBytes(int length) {
    if (_offset + length > _data.length) throw RangeError('Buffer underflow');
    final bytes = _data.sublist(_offset, _offset + length);
    _offset += length;
    return bytes;
  }
}
