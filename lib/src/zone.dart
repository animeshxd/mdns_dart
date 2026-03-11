/// mDNS zone and service management.
///
/// This module provides the Zone interface and MDNSService implementation
/// for serving mDNS records dynamically.
library;

import 'dart:io';
import 'dns.dart';
import 'utils.dart';

/// Default TTL for mDNS records in seconds
const int defaultTTL = 120;

/// Interface for serving DNS records dynamically
abstract class Zone {
  /// Returns DNS records in response to a DNS question
  List<DNSResourceRecord> records(DNSQuestion question);

  /// Returns all records with TTL=0 for sending goodbye packets
  /// (RFC 6762 Section 10.1).
  List<DNSResourceRecord> goodbyeRecords() => [];
}

/// mDNS service implementation that can serve records for a named service
class MDNSService implements Zone {
  /// Service instance name (e.g. "My Printer")
  final String instance;

  /// Service type (e.g. "_http._tcp.")
  final String service;

  /// Domain (defaults to "local.")
  final String domain;

  /// Host machine DNS name (e.g. "mymachine.")
  final String hostName;

  /// Service port number
  final int port;

  /// IP addresses for the service's host
  final List<InternetAddress> ips;

  /// Service TXT records
  final List<String> txt;

  // Computed addresses
  late final String serviceAddr;
  late final String instanceAddr;
  late final String enumAddr;

  MDNSService({
    required this.instance,
    required this.service,
    required this.domain,
    required this.hostName,
    required this.port,
    required this.ips,
    required this.txt,
  }) {
    serviceAddr = '${trimDot(service)}.${trimDot(domain)}.';
    instanceAddr = '$instance.$serviceAddr';
    enumAddr = '_services._dns-sd._udp.${trimDot(domain)}.';
  }

  /// Creates a new MDNSService with automatic host detection
  static Future<MDNSService> create({
    required String instance,
    required String service,
    String domain = 'local.',
    String? hostName,
    required int port,
    List<InternetAddress>? ips,
    List<String> txt = const [],
  }) async {
    // Validate inputs
    if (instance.isEmpty) {
      throw ArgumentError('Service instance name cannot be empty');
    }

    if (service.isEmpty) {
      throw ArgumentError('Service name cannot be empty');
    }

    if (port <= 0 || port > 65535) {
      throw ArgumentError('Invalid port number: $port');
    }

    final normalizedDomain = domain.endsWith('.') ? domain : '$domain.';

    if (!isValidFQDN(normalizedDomain)) {
      throw ArgumentError('Domain is not a valid FQDN: $normalizedDomain');
    }

    final baseHostName = hostName ?? Platform.localHostname;
    final normalizedHostName =
        baseHostName.endsWith('.') ? baseHostName : '$baseHostName.';

    if (!isValidFQDN(normalizedHostName)) {
      throw ArgumentError('Hostname is not a valid FQDN: $normalizedHostName');
    }

    final resolvedIps = await _resolveIps(
      explicitIps: ips,
      explicitHostName: hostName,
      normalizedHostName: normalizedHostName,
      normalizedDomain: normalizedDomain,
    );

    if (resolvedIps.isEmpty) {
      throw ArgumentError(
        'Could not determine usable IP addresses for $normalizedHostName',
      );
    }

    return MDNSService(
      instance: instance,
      service: service,
      domain: normalizedDomain,
      hostName: normalizedHostName,
      port: port,
      ips: resolvedIps,
      txt: txt,
    );
  }

  static Future<List<InternetAddress>> _resolveIps({
    required List<InternetAddress>? explicitIps,
    required String? explicitHostName,
    required String normalizedHostName,
    String normalizedDomain = 'local.',
  }) async {
    if (explicitIps != null && explicitIps.isNotEmpty) {
      return explicitIps.toSet().toList();
    }

    // If user explicitly provided hostname, resolve once via system DNS.
    if (explicitHostName != null) {
      try {
        final result = await InternetAddress.lookup(
          normalizedHostName.substring(0, normalizedHostName.length - 1),
        );
        return _sanitizeIps(result);
      } on Exception catch (_) {
        // If resolution fails, try hostname + domain as fallback
        final hostWithDomain = '$normalizedHostName$normalizedDomain';
        final result = await InternetAddress.lookup(
          hostWithDomain.substring(0, hostWithDomain.length - 1),
        );
        return _sanitizeIps(result);
      }
    }

    // Otherwise: deterministic interface enumeration.
    final interfaces = await NetworkInterface.list();

    final addresses = interfaces
        .expand((iface) => iface.addresses)
        .where(_isUsableAddress)
        .toSet() // deduplicate
        .toList();

    return addresses;
  }

  static List<InternetAddress> _sanitizeIps(
    List<InternetAddress> addresses,
  ) {
    return addresses.where(_isUsableAddress).toSet().toList();
  }

  static bool _isUsableAddress(InternetAddress address) {
    // if (address.isLoopback) return false;

    if (address.type == InternetAddressType.IPv6 && address.isLinkLocal) {
      return false;
    }

    return address.type == InternetAddressType.IPv4 ||
        address.type == InternetAddressType.IPv6;
  }

  @override
  List<DNSResourceRecord> records(DNSQuestion question) {
    // Normalize query name to FQDN format (with trailing dot)
    final queryName =
        question.name.endsWith('.') ? question.name : '${question.name}.';

    switch (queryName) {
      case String name when name == enumAddr:
        return _serviceEnum(question);
      case String name when name == serviceAddr:
        return _serviceRecords(question);
      case String name when name == instanceAddr:
        return _instanceRecords(question);
      case String name when name == hostName:
        if (question.type == DNSType.A || question.type == DNSType.AAAA) {
          return _instanceRecords(question);
        }
        return [];
      default:
        return [];
    }
  }

  /// Returns service enumeration records
  List<DNSResourceRecord> _serviceEnum(DNSQuestion question) {
    switch (question.type) {
      case DNSType.ANY:
      case DNSType.PTR:
        return [
          PTRRecord(
            name: question.name,
            target: serviceAddr,
            dnsClass: DNSClass.IN,
            ttl: defaultTTL,
          ),
        ];
      default:
        return [];
    }
  }

  /// Returns service records (PTR pointing to instance)
  List<DNSResourceRecord> _serviceRecords(DNSQuestion question) {
    switch (question.type) {
      case DNSType.ANY:
      case DNSType.PTR:
        final records = <DNSResourceRecord>[
          PTRRecord(
            name: question.name,
            target: instanceAddr,
            dnsClass: DNSClass.IN,
            ttl: defaultTTL,
          ),
        ];

        // Add instance records as additional
        final instanceQuestion = DNSQuestion(
          name: instanceAddr,
          type: DNSType.ANY,
          dnsClass: DNSClass.IN,
        );
        records.addAll(_instanceRecords(instanceQuestion));

        return records;
      default:
        return [];
    }
  }

  /// Returns instance records (SRV, TXT, A, AAAA)
  List<DNSResourceRecord> _instanceRecords(DNSQuestion question) {
    switch (question.type) {
      case DNSType.ANY:
        final records = <DNSResourceRecord>[];

        // Add SRV record
        records.addAll(
          _instanceRecords(
            DNSQuestion(
              name: instanceAddr,
              type: DNSType.SRV,
              dnsClass: DNSClass.IN,
            ),
          ),
        );

        // Add TXT record
        records.addAll(
          _instanceRecords(
            DNSQuestion(
              name: instanceAddr,
              type: DNSType.TXT,
              dnsClass: DNSClass.IN,
            ),
          ),
        );

        return records;

      case DNSType.A:
        final records = <DNSResourceRecord>[];
        for (final ip in ips) {
          if (ip.type == InternetAddressType.IPv4) {
            records.add(
              ARecord(
                name: hostName,
                address: ip.address,
                dnsClass: DNSClass.IN,
                ttl: defaultTTL,
              ),
            );
          }
        }
        return records;

      case DNSType.AAAA:
        final records = <DNSResourceRecord>[];
        for (final ip in ips) {
          if (ip.type == InternetAddressType.IPv6) {
            records.add(
              AAAARecord(
                name: hostName,
                address: ip.address,
                dnsClass: DNSClass.IN,
                ttl: defaultTTL,
              ),
            );
          }
        }
        return records;

      case DNSType.SRV:
        final records = <DNSResourceRecord>[
          SRVRecord(
            name: question.name,
            priority: 10,
            weight: 1,
            port: port,
            target: hostName,
            dnsClass: DNSClass.IN,
            ttl: defaultTTL,
          ),
        ];

        // Add A/AAAA records as additional
        records.addAll(
          _instanceRecords(
            DNSQuestion(
              name: instanceAddr,
              type: DNSType.A,
              dnsClass: DNSClass.IN,
            ),
          ),
        );

        records.addAll(
          _instanceRecords(
            DNSQuestion(
              name: instanceAddr,
              type: DNSType.AAAA,
              dnsClass: DNSClass.IN,
            ),
          ),
        );

        return records;

      case DNSType.TXT:
        return [
          TXTRecord(
            name: question.name,
            strings: txt,
            dnsClass: DNSClass.IN,
            ttl: defaultTTL,
          ),
        ];

      default:
        return [];
    }
  }

  @override
  List<DNSResourceRecord> goodbyeRecords() {
    return [
      PTRRecord(
        name: serviceAddr,
        target: instanceAddr,
        dnsClass: DNSClass.IN,
        ttl: 0,
      ),
      SRVRecord(
        name: instanceAddr,
        priority: 10,
        weight: 1,
        port: port,
        target: hostName,
        dnsClass: DNSClass.IN,
        ttl: 0,
      ),
      TXTRecord(
        name: instanceAddr,
        strings: txt,
        dnsClass: DNSClass.IN,
        ttl: 0,
      ),
      for (final ip in ips)
        if (ip.type == InternetAddressType.IPv4)
          ARecord(
            name: hostName,
            address: ip.address,
            dnsClass: DNSClass.IN,
            ttl: 0,
          )
        else
          AAAARecord(
            name: hostName,
            address: ip.address,
            dnsClass: DNSClass.IN,
            ttl: 0,
          ),
    ];
  }

  /// Creates TXT record strings from key-value pairs
  static List<String> createTXTRecords(Map<String, String> data) {
    return data.entries.map((entry) => '${entry.key}=${entry.value}').toList();
  }

  /// Parses TXT record strings into key-value pairs
  static Map<String, String> parseTXTRecords(List<String> txt) {
    final result = <String, String>{};

    for (final record in txt) {
      final parts = record.split('=');
      if (parts.length >= 2) {
        final key = parts[0];
        final value = parts.skip(1).join('=');
        result[key] = value;
      } else if (parts.length == 1) {
        result[parts[0]] = '';
      }
    }

    return result;
  }

  @override
  String toString() {
    return 'MDNSService(instance: $instance, service: $service, '
        'host: $hostName, port: $port, ips: ${ips.map((ip) => ip.address).join(', ')})';
  }
}

/// Multi-service zone that can serve multiple services
class MultiServiceZone implements Zone {
  final List<MDNSService> _services = [];

  /// Adds a service to this zone
  void addService(MDNSService service) {
    _services.add(service);
  }

  /// Removes a service from this zone
  bool removeService(MDNSService service) {
    return _services.remove(service);
  }

  /// Gets all services in this zone
  List<MDNSService> get services => List.unmodifiable(_services);

  @override
  List<DNSResourceRecord> records(DNSQuestion question) {
    final allRecords = <DNSResourceRecord>[];

    for (final service in _services) {
      allRecords.addAll(service.records(question));
    }

    return allRecords;
  }

  @override
  List<DNSResourceRecord> goodbyeRecords() {
    return _services.expand((s) => s.goodbyeRecords()).toList();
  }

  /// Clears all services
  void clear() {
    _services.clear();
  }
}
