/// mDNS client for service discovery.
/// 
/// This module provides comprehensive mDNS client functionality for discovering
/// and querying services on the network, with support for multiple interfaces
/// and both IPv4 and IPv6.
library client;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'dns.dart';

/// mDNS multicast addresses and port
const String ipv4mDNS = '224.0.0.251';
const String ipv6mDNS = 'ff02::fb';
const int mDNSPort = 5353;

/// Represents a discovered service entry
class ServiceEntry {
  /// Service instance name
  String name;
  
  /// Hostname
  String host;
  
  /// IPv4 address
  InternetAddress? addrV4;
  
  /// IPv6 address
  InternetAddress? addrV6;
  
  /// Service port
  int port;
  
  /// Service info string (first TXT record)
  String info;
  
  /// All TXT record fields
  List<String> infoFields;
  
  /// Legacy address field (use addrV4/addrV6 instead)
  @Deprecated('Use addrV4 or addrV6 instead')
  InternetAddress? addr;
  
  bool _hasTXT = false;
  bool _sent = false;

  ServiceEntry({
    required this.name,
    this.host = '',
    this.addrV4,
    this.addrV6,
    this.port = 0,
    this.info = '',
    this.infoFields = const [],
    this.addr,
  });

  /// Checks if we have all the info we need for a complete service
  bool get isComplete {
    return (addrV4 != null || addrV6 != null || addr != null) && 
           port != 0 && 
           _hasTXT;
  }

  /// Gets the primary IP address (prefers IPv4)
  InternetAddress? get primaryAddress {
    return addrV4 ?? addrV6 ?? addr;
  }

  /// Marks this entry as having TXT records
  void markHasTXT() {
    _hasTXT = true;
  }

  /// Marks this entry as sent to the results channel
  void markSent() {
    _sent = true;
  }

  /// Whether this entry has been sent
  bool get wasSent => _sent;

  @override
  String toString() {
    final address = primaryAddress?.address ?? 'unknown';
    return 'ServiceEntry(name: $name, host: $host, address: $address, port: $port)';
  }
}

/// Parameters for customizing mDNS queries
class QueryParams {
  /// Service to lookup (e.g., "_http._tcp.local")
  final String service;
  
  /// Lookup domain (default: "local")
  final String domain;
  
  /// Query timeout
  final Duration timeout;
  
  /// Network interface to use for multicast
  final NetworkInterface? networkInterface;
  
  /// Stream for discovered entries
  final StreamController<ServiceEntry>? entriesController;
  
  /// Whether to request unicast responses
  final bool wantUnicastResponse;
  
  /// Whether to disable IPv4
  final bool disableIPv4;
  
  /// Whether to disable IPv6
  final bool disableIPv6;

  QueryParams({
    required this.service,
    this.domain = 'local',
    this.timeout = const Duration(seconds: 1),
    this.networkInterface,
    this.entriesController,
    this.wantUnicastResponse = false,
    this.disableIPv4 = false,
    this.disableIPv6 = false,
  });

  /// Creates default parameters for a service
  factory QueryParams.defaultFor(String service) {
    return QueryParams(
      service: service,
      domain: 'local',
      timeout: const Duration(seconds: 1),
      wantUnicastResponse: false,
      disableIPv4: false,
      disableIPv6: false,
    );
  }
}

/// High-level mDNS client for service discovery
class MDNSClient {
  /// Performs a service lookup with custom parameters
  static Future<Stream<ServiceEntry>> query(QueryParams params) async {
    final client = _Client(
      useIPv4: !params.disableIPv4,
      useIPv6: !params.disableIPv6,
    );

    try {
      await client._initialize();
      
      if (params.networkInterface != null) {
        await client._setInterface(params.networkInterface!);
      }

      return client._performQuery(params);
    } catch (e) {
      await client.close();
      rethrow;
    }
  }

  /// Simple service lookup using default parameters
  static Future<Stream<ServiceEntry>> lookup(String service) async {
    final params = QueryParams.defaultFor(service);
    return query(params);
  }

  /// Discovers services and collects results into a list
  static Future<List<ServiceEntry>> discover(
    String service, {
    Duration timeout = const Duration(seconds: 3),
    String domain = 'local',
    NetworkInterface? networkInterface,
    bool wantUnicastResponse = false,
  }) async {
    final results = <ServiceEntry>[];
    final completer = Completer<List<ServiceEntry>>();
    
    final params = QueryParams(
      service: service,
      domain: domain,
      timeout: timeout,
      networkInterface: networkInterface,
      wantUnicastResponse: wantUnicastResponse,
    );

    try {
      final stream = await query(params);
      late StreamSubscription subscription;
      
      subscription = stream.listen(
        (entry) {
          results.add(entry);
        },
        onDone: () {
          completer.complete(results);
        },
        onError: (error) {
          completer.completeError(error);
        },
      );

      // Set up timeout
      Timer(timeout, () {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete(results);
        }
      });

      return await completer.future;
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    }
  }
}

/// Internal mDNS client implementation
class _Client {
  final bool _useIPv4;
  final bool _useIPv6;

  RawDatagramSocket? _ipv4UnicastConn;
  RawDatagramSocket? _ipv6UnicastConn;
  RawDatagramSocket? _ipv4MulticastConn;
  RawDatagramSocket? _ipv6MulticastConn;

  bool _closed = false;
  final Completer<void> _closedCompleter = Completer<void>();

  _Client({
    required bool useIPv4,
    required bool useIPv6,
  }) : _useIPv4 = useIPv4, _useIPv6 = useIPv6 {
    if (!_useIPv4 && !_useIPv6) {
      throw ArgumentError('Must enable at least one of IPv4 and IPv6');
    }
  }

  /// Initializes the client sockets
  Future<void> _initialize() async {
    // Create unicast connections
    if (_useIPv4) {
      try {
        _ipv4UnicastConn = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
        );
      } catch (e) {
        // IPv4 unicast failed
      }
    }

    if (_useIPv6) {
      try {
        _ipv6UnicastConn = await RawDatagramSocket.bind(
          InternetAddress.anyIPv6,
          0,
        );
      } catch (e) {
        // IPv6 unicast failed
      }
    }

    if (_ipv4UnicastConn == null && _ipv6UnicastConn == null) {
      throw StateError('Failed to bind to any unicast UDP port');
    }

    // Create multicast connections
    if (_useIPv4) {
      try {
        _ipv4MulticastConn = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          mDNSPort,
          reuseAddress: true,
          reusePort: true,
        );
        _ipv4MulticastConn!.multicastHops = 255;
        _ipv4MulticastConn!.joinMulticast(InternetAddress(ipv4mDNS));
      } catch (e) {
        _ipv4MulticastConn?.close();
        _ipv4MulticastConn = null;
      }
    }

    if (_useIPv6) {
      try {
        _ipv6MulticastConn = await RawDatagramSocket.bind(
          InternetAddress.anyIPv6,
          mDNSPort,
          reuseAddress: true,
          reusePort: true,
        );
        _ipv6MulticastConn!.multicastHops = 255;
        _ipv6MulticastConn!.joinMulticast(InternetAddress(ipv6mDNS));
      } catch (e) {
        _ipv6MulticastConn?.close();
        _ipv6MulticastConn = null;
      }
    }

    if (_ipv4MulticastConn == null && _ipv6MulticastConn == null) {
      throw StateError('Failed to bind to any multicast UDP port');
    }

    // Disable combinations where we don't have both unicast and multicast
    if (_ipv4UnicastConn == null || _ipv4MulticastConn == null) {
      _ipv4UnicastConn?.close();
      _ipv4MulticastConn?.close();
      _ipv4UnicastConn = null;
      _ipv4MulticastConn = null;
    }

    if (_ipv6UnicastConn == null || _ipv6MulticastConn == null) {
      _ipv6UnicastConn?.close();
      _ipv6MulticastConn?.close();
      _ipv6UnicastConn = null;
      _ipv6MulticastConn = null;
    }

    if (_ipv4UnicastConn == null && _ipv6UnicastConn == null) {
      throw StateError('Must have at least one working IP version');
    }
  }

  /// Sets the multicast interface and rebinds unicast socket to interface IP
  Future<void> _setInterface(NetworkInterface iface) async {
    // Key fix: Rebind unicast socket to specific interface IP
    if (_useIPv4) {
      // Close existing unicast connection
      _ipv4UnicastConn?.close();
      
      try {
        // Find IPv4 address on this interface
        final ipv4Addr = iface.addresses.firstWhere(
          (addr) => addr.type == InternetAddressType.IPv4,
        );
        
        // Rebind unicast socket to specific interface IP
        _ipv4UnicastConn = await RawDatagramSocket.bind(
          ipv4Addr, // Bind to specific interface IP, not anyIPv4
          0,
        );
      } catch (e) {
        // Interface binding failed, try fallback
        try {
          _ipv4UnicastConn = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
          );
        } catch (e2) {
          _ipv4UnicastConn = null;
        }
      }
    }

    // Set multicast interface
    if (_ipv4MulticastConn != null) {
      try {
        _ipv4MulticastConn!.multicastInterface = iface;
      } catch (e) {
        // Interface setting failed for IPv4
      }
    }

    if (_ipv6MulticastConn != null) {
      try {
        _ipv6MulticastConn!.multicastInterface = iface;
      } catch (e) {
        // Interface setting failed for IPv6
      }
    }
  }

  /// Performs the actual mDNS query
  Stream<ServiceEntry> _performQuery(QueryParams params) async* {
    if (_closed) throw StateError('Client is closed');

    // Create service address
    final serviceAddr = '${_trimDot(params.service)}.${_trimDot(params.domain)}.';

    // Create message channel for received packets
    final messageController = StreamController<_MessageAddr>();
    
    // Start listening for responses
    final subscriptions = <StreamSubscription>[];
    
    if (_ipv4UnicastConn != null) {
      subscriptions.add(_listenOnSocket(_ipv4UnicastConn!, messageController));
    }
    if (_ipv6UnicastConn != null) {
      subscriptions.add(_listenOnSocket(_ipv6UnicastConn!, messageController));
    }
    if (_ipv4MulticastConn != null) {
      subscriptions.add(_listenOnSocket(_ipv4MulticastConn!, messageController));
    }
    if (_ipv6MulticastConn != null) {
      subscriptions.add(_listenOnSocket(_ipv6MulticastConn!, messageController));
    }

    // Set up timeout timer variable
    Timer? timeoutTimer;

    try {
      // Create query message
      final query = DNSMessage.query(
        id: Random().nextInt(65536),
        name: serviceAddr,
        type: DNSType.PTR,
        unicastResponse: params.wantUnicastResponse,
      );

      // Send query
      await _sendQuery(query);

      // Track in-progress responses
      final inProgress = <String, ServiceEntry>{};
      final completedServices = <String>{};

      // Set up timeout
      if (params.timeout != Duration.zero) {
        timeoutTimer = Timer(params.timeout, () {
          if (!messageController.isClosed) {
            messageController.close();
          }
        });
      }

      // Listen for responses until timeout
      await for (final msgAddr in messageController.stream) {
        final records = <DNSResourceRecord>[
          ...msgAddr.message.answers,
          ...msgAddr.message.additional,
        ];

        for (final record in records) {
          final entry = _ensureEntry(inProgress, record.name);
          entry.host = entry.host.isEmpty ? record.name : entry.host;

          switch (record) {
            case PTRRecord ptr:
              final targetEntry = _ensureEntry(inProgress, ptr.target);
              targetEntry.name = ptr.target;
              _alias(inProgress, ptr.target, ptr.name);
              break;

            case SRVRecord srv:
              entry.host = srv.target;
              entry.port = srv.port;
              break;

            case ARecord a:
              entry.addrV4 = InternetAddress(a.address);
              entry.addr ??= entry.addrV4; // For backward compatibility
              
              // Key fix: Propagate A record to all entries that reference this host
              for (final otherEntry in inProgress.values) {
                if (otherEntry.host == a.name && otherEntry != entry) {
                  otherEntry.addrV4 = InternetAddress(a.address);
                  otherEntry.addr ??= otherEntry.addrV4;
                }
              }
              break;

            case AAAARecord aaaa:
              entry.addrV6 = InternetAddress(aaaa.address);
              entry.addr ??= entry.addrV6; // For backward compatibility
              
              // Key fix: Propagate AAAA record to all entries that reference this host
              for (final otherEntry in inProgress.values) {
                if (otherEntry.host == aaaa.name && otherEntry != entry) {
                  otherEntry.addrV6 = InternetAddress(aaaa.address);
                  otherEntry.addr ??= otherEntry.addrV6;
                }
              }
              break;

            case TXTRecord txt:
              entry.infoFields = txt.strings;
              entry.info = txt.strings.isNotEmpty ? txt.strings.first : '';
              entry.markHasTXT();
              break;
          }

          // Check if entry is complete and hasn't been sent
          if (entry.isComplete && 
              !entry.wasSent && 
              !completedServices.contains(entry.name)) {
            entry.markSent();
            completedServices.add(entry.name);
            yield entry;
          }
          
          // Also check all other entries for completeness after linking
          for (final otherEntry in inProgress.values) {
            if (otherEntry.isComplete && 
                !otherEntry.wasSent && 
                !completedServices.contains(otherEntry.name)) {
              otherEntry.markSent();
              completedServices.add(otherEntry.name);
              yield otherEntry;
            }
          }
        }
      }
    } finally {
      // Cancel timeout timer if it exists
      timeoutTimer?.cancel();
      
      // Clean up subscriptions
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await messageController.close();
    }
  }

  /// Listens on a socket for incoming packets
  StreamSubscription _listenOnSocket(
    RawDatagramSocket socket,
    StreamController<_MessageAddr> messageController,
  ) {
    return socket.listen((event) {
      if (event == RawSocketEvent.read && !_closed) {
        final packet = socket.receive();
        if (packet != null) {
          final message = DNSMessage.parse(packet.data);
          if (message != null && 
              (message.header.ancount > 0 || message.header.arcount > 0)) {
            messageController.add(_MessageAddr(message, packet.address, packet.port));
          }
        }
      }
    });
  }

  /// Sends a DNS query to multicast addresses
  Future<void> _sendQuery(DNSMessage query) async {
    final data = query.pack();

    if (_ipv4UnicastConn != null) {
      try {
        _ipv4UnicastConn!.send(data, InternetAddress(ipv4mDNS), mDNSPort);
      } catch (e) {
        // Send failed
      }
    }

    if (_ipv6UnicastConn != null) {
      try {
        _ipv6UnicastConn!.send(data, InternetAddress(ipv6mDNS), mDNSPort);
      } catch (e) {
        // Send failed
      }
    }
  }

  /// Ensures an entry exists in the progress map
  ServiceEntry _ensureEntry(Map<String, ServiceEntry> inProgress, String name) {
    return inProgress.putIfAbsent(name, () => ServiceEntry(name: name));
  }

  /// Sets up an alias between two entries
  void _alias(Map<String, ServiceEntry> inProgress, String src, String dst) {
    final srcEntry = _ensureEntry(inProgress, src);
    inProgress[dst] = srcEntry;
  }

  /// Closes the client and all connections
  Future<void> close() async {
    if (_closed) return;
    
    _closed = true;
    
    _ipv4UnicastConn?.close();
    _ipv6UnicastConn?.close();
    _ipv4MulticastConn?.close();
    _ipv6MulticastConn?.close();
    
    _closedCompleter.complete();
  }

  /// Returns a future that completes when the client is closed
  Future<void> get onClosed => _closedCompleter.future;
}

/// Helper class for message and source address
class _MessageAddr {
  final DNSMessage message;
  final InternetAddress source;
  final int port;

  _MessageAddr(this.message, this.source, this.port);
}

/// Trims dots from start and end of string
String _trimDot(String s) {
  return s.replaceAll(RegExp(r'^\.+|\.+$'), '');
}
