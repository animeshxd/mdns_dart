/// mDNS zone and service management.
///
/// This module provides the Zone interface and MDNSService implementation
/// for serving mDNS records dynamically.
library;

import 'dart:io';
import 'dns.dart';

/// Default TTL for mDNS records in seconds
const int defaultTTL = 120;

/// Interface for serving DNS records dynamically
abstract class Zone {
  /// Returns DNS records in response to a DNS question
  List<DNSResourceRecord> records(DNSQuestion question);
}

/// mDNS service implementation that can serve records for a named service
class MDNSService implements Zone {
  /// Service instance name (e.g. "My Printer")
  final String instance;

  /// Service type (e.g. "_http._tcp.")
  final String service;

  /// Domain (defaults to "local.")
  final String domain;

  /// Host machine DNS name (e.g. "mymachine.local.")
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
    serviceAddr = '${_trimDot(service)}.${_trimDot(domain)}.';
    instanceAddr = '$instance.${_trimDot(service)}.${_trimDot(domain)}.';
    enumAddr = '_services._dns-sd._udp.${_trimDot(domain)}.';
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

    // Ensure domain ends with dot
    if (!domain.endsWith('.')) {
      domain = '$domain.';
    }
    if (!_isValidFQDN(domain)) {
      throw ArgumentError('Domain is not a valid FQDN: $domain');
    }

    // Get hostname if not provided
    String actualHostName = hostName ?? Platform.localHostname;
    if (!actualHostName.endsWith('.')) {
      actualHostName = '$actualHostName.';
    }
    if (!_isValidFQDN(actualHostName)) {
      throw ArgumentError('Hostname is not a valid FQDN: $actualHostName');
    }

    // Get IP addresses if not provided
    List<InternetAddress> actualIPs = ips ?? [];
    if (actualIPs.isEmpty) {
      try {
        // Try to lookup the hostname
        actualIPs = await InternetAddress.lookup(
          actualHostName.substring(0, actualHostName.length - 1),
        );
      } catch (e) {
        // If that fails, try with domain suffix
        try {
          final fullHostName =
              '${actualHostName.substring(0, actualHostName.length - 1)}$domain';
          actualIPs = await InternetAddress.lookup(
            fullHostName.substring(0, fullHostName.length - 1),
          );
        } catch (e) {
          throw ArgumentError(
            'Could not determine IP addresses for $actualHostName',
          );
        }
      }
    }

    // Validate IP addresses
    for (final ip in actualIPs) {
      if (ip.type != InternetAddressType.IPv4 &&
          ip.type != InternetAddressType.IPv6) {
        throw ArgumentError('Invalid IP address: ${ip.address}');
      }
    }

    return MDNSService(
      instance: instance,
      service: service,
      domain: domain,
      hostName: actualHostName,
      port: port,
      ips: actualIPs,
      txt: txt,
    );
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

  /// Clears all services
  void clear() {
    _services.clear();
  }
}

// Helper functions

String _trimDot(String s) {
  return s.replaceAll(RegExp(r'^\.+|\.+$'), '');
}

bool _isValidFQDN(String s) {
  if (s.isEmpty) return false;
  if (!s.endsWith('.')) return false;

  // Basic validation - could be more comprehensive
  final labels = s.substring(0, s.length - 1).split('.');
  if (labels.isEmpty) return false;

  for (final label in labels) {
    if (label.isEmpty) return false;
    if (label.length > 63) return false;
    if (!RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(label)) {
      return false;
    }
  }

  return true;
}
