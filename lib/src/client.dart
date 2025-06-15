/// mDNS client for service discovery.
///
/// This module provides comprehensive mDNS client functionality for discovering
/// and querying services on the network, with support for multiple interfaces
/// and both IPv4 and IPv6.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'utils.dart';
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

  /// IPv4 addresses
  List<InternetAddress>? addrsV4;

  /// IPv6 addresses
  List<InternetAddress>? addrsV6;

  /// Service port
  int port;

  /// Service info string (first TXT record)
  String info;

  /// All TXT record fields
  List<String> infoFields;

  bool _hasTXT = false;
  bool _sent = false;

  ServiceEntry({
    required this.name,
    this.host = '',
    this.addrsV4,
    this.addrsV6,
    this.port = 0,
    this.info = '',
    this.infoFields = const [],
  });

  /// Checks if we have all the info we need for a complete service
  bool get isComplete {
    return (addrV4 != null || addrV6 != null) && port != 0 && _hasTXT;
  }

  /// IPv4 address (backward compatibility - returns first address)
  InternetAddress? get addrV4 {
    return addrsV4?.first;
  }

  /// IPv6 address (backward compatibility - returns first address)
  InternetAddress? get addrV6 {
    return addrsV6?.first;
  }

  /// Gets the primary IP address (prefers IPv4)
  InternetAddress? get primaryAddress {
    return addrV4 ?? addrV6;
  }

  /// Gets all IP addresses (IPv4 and IPv6 combined)
  List<InternetAddress> get allAddresses {
    final List<InternetAddress> addresses = [];
    if (addrsV4 != null) addresses.addAll(addrsV4!);
    if (addrsV6 != null) addresses.addAll(addrsV6!);
    return addresses;
  }

  /// Adds an IPv4 address if it doesn't already exist
  void addIPv4Address(InternetAddress address) {
    addrsV4 ??= [];
    if (!addrsV4!.any((addr) => addr.address == address.address)) {
      addrsV4!.add(address);
    }
  }

  /// Adds an IPv6 address if it doesn't already exist
  void addIPv6Address(InternetAddress address) {
    addrsV6 ??= [];
    if (!addrsV6!.any((addr) => addr.address == address.address)) {
      addrsV6!.add(address);
    }
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
    final allAddrs = allAddresses.map((a) => a.address).join(', ');
    final addressStr = allAddrs.isNotEmpty ? allAddrs : 'unknown';
    return 'ServiceEntry(name: $name, host: $host, addresses: [$addressStr], port: $port)';
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

  /// Whether to use SO_REUSEPORT socket option for multicast sockets
  ///
  /// This allows multiple processes to bind to the same multicast address and port.
  /// Supported on Linux, macOS, and Android API 21+.
  final bool reusePort;

  /// Whether to use SO_REUSEADDR socket option for multicast sockets
  ///
  /// This allows the socket to bind to an address that is already in use.
  /// Generally recommended for multicast sockets.
  final bool reuseAddress;

  /// Time-to-live (TTL) for multicast packets
  ///
  /// Controls how many network hops multicast packets can traverse.
  /// Default is 1 (local network only), which is appropriate for mDNS.
  /// Higher values allow wider propagation but may not be necessary for local discovery.
  final int multicastHops;

  /// Custom logger function (optional)
  ///
  /// If provided, this function will be called with log messages during the query process.
  /// Useful for debugging network issues or monitoring query progress.
  final void Function(String message)? logger;

  QueryParams({
    required this.service,
    this.domain = 'local',
    this.timeout = const Duration(seconds: 1),
    this.networkInterface,
    this.entriesController,
    this.wantUnicastResponse = false,
    this.disableIPv4 = false,
    this.disableIPv6 = false,
    this.reusePort = true,
    this.reuseAddress = true,
    this.multicastHops = 1,
    this.logger,
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
      reusePort: true,
      reuseAddress: true,
      multicastHops: 1,
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
      reusePort: params.reusePort,
      reuseAddress: params.reuseAddress,
      multicastHops: params.multicastHops,
      logger: params.logger,
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
    bool reusePort = true,
    bool reuseAddress = true,
    int multicastHops = 1,
    void Function(String message)? logger,
  }) async {
    final results = <ServiceEntry>[];
    final completer = Completer<List<ServiceEntry>>();

    final params = QueryParams(
      service: service,
      domain: domain,
      timeout: timeout,
      networkInterface: networkInterface,
      wantUnicastResponse: wantUnicastResponse,
      reusePort: reusePort,
      reuseAddress: reuseAddress,
      multicastHops: multicastHops,
      logger: logger,
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
  final bool _reusePort;
  final bool _reuseAddress;
  final int _multicastHops;
  final void Function(String message)? _logger;

  RawDatagramSocket? _ipv4UnicastConn;
  RawDatagramSocket? _ipv6UnicastConn;
  RawDatagramSocket? _ipv4MulticastConn;
  RawDatagramSocket? _ipv6MulticastConn;

  bool _closed = false;
  final Completer<void> _closedCompleter = Completer<void>();

  _Client({
    required bool useIPv4,
    required bool useIPv6,
    required bool reusePort,
    required bool reuseAddress,
    required int multicastHops,
    void Function(String message)? logger,
  }) : _useIPv4 = useIPv4,
       _useIPv6 = useIPv6,
       _reusePort = reusePort,
       _reuseAddress = reuseAddress,
       _multicastHops = multicastHops,
       _logger = logger {
    if (!_useIPv4 && !_useIPv6) {
      throw ArgumentError('Must enable at least one of IPv4 and IPv6');
    }
  }

  /// Initializes the client sockets
  Future<void> _initialize() async {
    _log('Initializing mDNS client...');

    // Create unicast connections
    if (_useIPv4) {
      try {
        _ipv4UnicastConn = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
        );
        _log('IPv4 unicast socket bound to port ${_ipv4UnicastConn!.port}');
      } catch (e) {
        _log('Failed to create IPv4 unicast socket: $e');
      }
    }

    if (_useIPv6) {
      try {
        _ipv6UnicastConn = await RawDatagramSocket.bind(
          InternetAddress.anyIPv6,
          0,
        );
        _log('IPv6 unicast socket bound to port ${_ipv6UnicastConn!.port}');
      } catch (e) {
        _log('Failed to create IPv6 unicast socket: $e');
        // IPv6 unicast failed
      }
    }

    if (_ipv4UnicastConn == null && _ipv6UnicastConn == null) {
      _log('Error: Failed to bind to any unicast UDP port');
      throw StateError('Failed to bind to any unicast UDP port');
    }

    // Create multicast connections
    if (_useIPv4) {
      try {
        _ipv4MulticastConn = await _bindMulticastSocket(
          InternetAddress.anyIPv4,
          mDNSPort,
          reusePort: _reusePort,
          reuseAddress: _reuseAddress,
          multicastHops: _multicastHops,
        );
        _ipv4MulticastConn!.joinMulticast(InternetAddress(ipv4mDNS));
        _log(
          'IPv4 multicast socket bound to port $mDNSPort with reusePort=$_reusePort, reuseAddress=$_reuseAddress, multicastHops=$_multicastHops',
        );
      } catch (e) {
        _log('Failed to create IPv4 multicast socket: $e');
        _ipv4MulticastConn?.close();
        _ipv4MulticastConn = null;
      }
    }

    if (_useIPv6) {
      try {
        _ipv6MulticastConn = await _bindMulticastSocket(
          InternetAddress.anyIPv6,
          mDNSPort,
          reusePort: _reusePort,
          reuseAddress: _reuseAddress,
          multicastHops: _multicastHops,
        );
        _ipv6MulticastConn!.joinMulticast(InternetAddress(ipv6mDNS));
        _log(
          'IPv6 multicast socket bound to port $mDNSPort with reusePort=$_reusePort, reuseAddress=$_reuseAddress, multicastHops=$_multicastHops',
        );
      } catch (e) {
        _log('Failed to create IPv6 multicast socket: $e');
        _ipv6MulticastConn?.close();
        _ipv6MulticastConn = null;
      }
    }

    if (_ipv4MulticastConn == null && _ipv6MulticastConn == null) {
      _log('Error: Failed to bind to any multicast UDP port');
      throw StateError('Failed to bind to any multicast UDP port');
    }

    // Disable combinations where we don't have both unicast and multicast
    if (_ipv4UnicastConn == null || _ipv4MulticastConn == null) {
      if (_ipv4UnicastConn == null && _ipv4MulticastConn != null) {
        _log('Disabling IPv4: unicast socket creation failed');
      } else if (_ipv4UnicastConn != null && _ipv4MulticastConn == null) {
        _log('Disabling IPv4: multicast socket creation failed');
      }
      _ipv4UnicastConn?.close();
      _ipv4MulticastConn?.close();
      _ipv4UnicastConn = null;
      _ipv4MulticastConn = null;
    }

    if (_ipv6UnicastConn == null || _ipv6MulticastConn == null) {
      if (_ipv6UnicastConn == null && _ipv6MulticastConn != null) {
        _log('Disabling IPv6: unicast socket creation failed');
      } else if (_ipv6UnicastConn != null && _ipv6MulticastConn == null) {
        _log('Disabling IPv6: multicast socket creation failed');
      }
      _ipv6UnicastConn?.close();
      _ipv6MulticastConn?.close();
      _ipv6UnicastConn = null;
      _ipv6MulticastConn = null;
    }

    if (_ipv4UnicastConn == null && _ipv6UnicastConn == null) {
      _log('Error: Must have at least one working IP version');
      throw StateError('Must have at least one working IP version');
    }

    final activeVersions = <String>[];
    if (_ipv4UnicastConn != null) activeVersions.add('IPv4');
    if (_ipv6UnicastConn != null) activeVersions.add('IPv6');
    _log(
      'mDNS client initialized successfully with ${activeVersions.join(' and ')}',
    );
  }

  /// Binds a multicast socket with configurable socket options
  ///
  /// Throws exceptions on binding failures rather than returning null.
  /// Users should handle exceptions based on their requirements.
  ///
  /// Note for Android: If you encounter binding issues with reusePort=true,
  /// try setting reusePort=false and handle socket conflicts manually.
  Future<RawDatagramSocket> _bindMulticastSocket(
    InternetAddress address,
    int port, {
    required bool reusePort,
    required bool reuseAddress,
    required int multicastHops,
  }) async {
    // Try binding with the specified options
    final socket = await RawDatagramSocket.bind(
      address,
      port,
      reuseAddress: reuseAddress,
      reusePort: reusePort,
      ttl: multicastHops,
    );

    return socket;
  }

  /// Sets the multicast interface and rebinds unicast socket to interface IP
  Future<void> _setInterface(NetworkInterface iface) async {
    _log('Setting network interface to: ${iface.name}');

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
        _log(
          'IPv4 unicast socket rebound to interface ${iface.name} at ${ipv4Addr.address}',
        );
      } catch (e) {
        _log('Failed to bind IPv4 socket to interface ${iface.name}: $e');
        // Interface binding failed, try fallback
        try {
          _ipv4UnicastConn = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
          );
          _log('IPv4 unicast socket fallback to anyIPv4 successful');
        } catch (e2) {
          _log('IPv4 unicast socket fallback failed: $e2');
          _ipv4UnicastConn = null;
        }
      }
    }

    // Set multicast interface
    if (_ipv4MulticastConn != null) {
      try {
        _ipv4MulticastConn!.setMulticastInterface(iface);
        _log('IPv4 multicast interface set to ${iface.name}');
      } catch (e) {
        _log('Failed to set IPv4 multicast interface to ${iface.name}: $e');
      }
    }

    if (_ipv6MulticastConn != null) {
      try {
        // Set IPv6 multicast interface using setRawOption
        _ipv6MulticastConn!.setMulticastInterface(iface);
        _log('IPv6 multicast interface set to ${iface.name}');
      } catch (e) {
        _log('Failed to set IPv6 multicast interface to ${iface.name}: $e');
      }
    }
  }

  /// Performs the actual mDNS query
  Stream<ServiceEntry> _performQuery(QueryParams params) async* {
    if (_closed) throw StateError('Client is closed');

    // Create service address
    final serviceAddr =
        '${_trimDot(params.service)}.${_trimDot(params.domain)}.';
    _log(
      'Starting query for service: $serviceAddr (timeout: ${params.timeout})',
    );

    // Create service matcher for filtering results
    final serviceMatcher = _ServiceMatcher(params.service, params.domain);

    // Create message channel for received packets
    final messageController = StreamController<_MessageAddr>();

    // Start listening for responses
    final subscriptions = <StreamSubscription>[];
    int activeConnections = 0;

    if (_ipv4UnicastConn != null) {
      subscriptions.add(_listenOnSocket(_ipv4UnicastConn!, messageController));
      activeConnections++;
    }
    if (_ipv6UnicastConn != null) {
      subscriptions.add(_listenOnSocket(_ipv6UnicastConn!, messageController));
      activeConnections++;
    }
    if (_ipv4MulticastConn != null) {
      subscriptions.add(
        _listenOnSocket(_ipv4MulticastConn!, messageController),
      );
      activeConnections++;
    }
    if (_ipv6MulticastConn != null) {
      subscriptions.add(
        _listenOnSocket(_ipv6MulticastConn!, messageController),
      );
      activeConnections++;
    }

    _log('Listening on $activeConnections socket connections');

    // Set up timeout timer variable
    Timer? timeoutTimer;

    try {
      // Create query message
      final queryId = Random().nextInt(65536);
      final query = DNSMessage.query(
        id: queryId,
        name: serviceAddr,
        type: DNSType.PTR,
        unicastResponse: params.wantUnicastResponse,
      );

      _log(
        'Created DNS query (ID: $queryId, type: PTR, unicast: ${params.wantUnicastResponse})',
      );

      // Send query
      await _sendQuery(query);
      _log('Query sent to mDNS multicast addresses');

      // Track in-progress responses
      final inProgress = <String, ServiceEntry>{};
      final completedServices = <String>{};

      // Set up timeout
      if (params.timeout != Duration.zero) {
        timeoutTimer = Timer(params.timeout, () {
          _log(
            'Query timeout reached (${params.timeout}), closing message stream',
          );
          if (!messageController.isClosed) {
            messageController.close();
          }
        });
        _log('Query timeout set to ${params.timeout}');
      } else {
        _log('No timeout set for query');
      }

      // Listen for responses until timeout
      int receivedPackets = 0;
      await for (final msgAddr in messageController.stream) {
        receivedPackets++;
        _log(
          'Received packet #$receivedPackets from ${msgAddr.source}:${msgAddr.port} with ${msgAddr.message.answers.length + msgAddr.message.additional.length} records',
        );

        final records = <DNSResourceRecord>[
          ...msgAddr.message.answers,
          ...msgAddr.message.additional,
        ];

        for (final record in records) {
          final entry = _ensureEntry(inProgress, record.name);
          entry.host = entry.host.isEmpty ? record.name : entry.host;

          switch (record) {
            case PTRRecord ptr:
              _log('Processing PTR record: ${ptr.name} -> ${ptr.target}');
              final targetEntry = _ensureEntry(inProgress, ptr.target);
              targetEntry.name = ptr.target;
              _alias(inProgress, ptr.target, ptr.name);
              break;

            case SRVRecord srv:
              _log(
                'Processing SRV record: ${srv.name} -> ${srv.target}:${srv.port} (priority: ${srv.priority}, weight: ${srv.weight})',
              );
              entry.host = srv.target;
              entry.port = srv.port;
              break;

            case ARecord a:
              _log('Processing A record: ${a.name} -> ${a.address}');
              final ipv4Address = InternetAddress(a.address);
              entry.addIPv4Address(ipv4Address);

              // Propagate A record to all entries that reference this host
              for (final otherEntry in inProgress.values) {
                if (otherEntry.host == a.name && otherEntry != entry) {
                  otherEntry.addIPv4Address(ipv4Address);
                }
              }
              break;

            case AAAARecord aaaa:
              _log('Processing AAAA record: ${aaaa.name} -> ${aaaa.address}');
              final ipv6Address = InternetAddress(aaaa.address);
              entry.addIPv6Address(ipv6Address);

              // Propagate AAAA record to all entries that reference this host
              for (final otherEntry in inProgress.values) {
                if (otherEntry.host == aaaa.name && otherEntry != entry) {
                  otherEntry.addIPv6Address(ipv6Address);
                }
              }
              break;

            case TXTRecord txt:
              _log(
                'Processing TXT record: ${txt.name} with ${txt.strings.length} text fields',
              );
              entry.infoFields = txt.strings;
              entry.info = txt.strings.isNotEmpty ? txt.strings.first : '';
              entry.markHasTXT();
              break;

            case NSECRecord _:
              _log(
                'Ignoring NSEC record for ${record.name} (used for negative responses)',
              );
              break;

            default:
              _log(
                'Ignoring unknown record type: ${record.runtimeType} for ${record.name}',
              );
          }

          // Check if entry is complete and hasn't been sent
          if (entry.isComplete &&
              !entry.wasSent &&
              !completedServices.contains(entry.name) &&
              serviceMatcher.matches(entry.name)) {
            _log(
              'Service entry complete and matches query: ${entry.name} at ${entry.allAddresses.map((a) => a.address).join(', ')}:${entry.port}',
            );
            entry.markSent();
            completedServices.add(entry.name);
            yield entry;
          }

          // Also check all other entries for completeness after linking
          for (final otherEntry in inProgress.values) {
            if (otherEntry.isComplete &&
                !otherEntry.wasSent &&
                !completedServices.contains(otherEntry.name) &&
                serviceMatcher.matches(otherEntry.name)) {
              _log(
                'Linked service entry complete and matches query: ${otherEntry.name} at ${otherEntry.allAddresses.map((a) => a.address).join(', ')}:${otherEntry.port}',
              );
              otherEntry.markSent();
              completedServices.add(otherEntry.name);
              yield otherEntry;
            }
          }
        }
      }

      _log(
        'Query completed. Total packets received: $receivedPackets, services found: ${completedServices.length}',
      );
    } finally {
      // Cancel timeout timer if it exists
      timeoutTimer?.cancel();
      _log('Query cleanup: timeout timer cancelled');

      // Clean up subscriptions
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      _log(
        'Query cleanup: ${subscriptions.length} socket subscriptions cancelled',
      );
      await messageController.close();
      _log('Query cleanup: message controller closed');
    }
  }

  /// Listens on a socket for incoming packets
  StreamSubscription _listenOnSocket(
    RawDatagramSocket socket,
    StreamController<_MessageAddr> messageController,
  ) {
    _log('Started listening on socket ${socket.address}:${socket.port}');

    return socket.listen((event) {
      if (event == RawSocketEvent.read && !_closed) {
        final packet = socket.receive();
        if (packet != null) {
          _log(
            'Received ${packet.data.length} bytes from ${packet.address}:${packet.port}',
          );
          final message = DNSMessage.parse(packet.data);
          if (message != null &&
              (message.header.ancount > 0 || message.header.arcount > 0)) {
            _log(
              'Parsed valid DNS message with ${message.header.ancount} answers and ${message.header.arcount} additional records',
            );
            messageController.add(
              _MessageAddr(message, packet.address, packet.port),
            );
          } else if (message == null) {
            _log(
              'Failed to parse DNS message from ${packet.address}:${packet.port}',
            );
          } else {
            _log(
              'Ignoring DNS message with no relevant records from ${packet.address}:${packet.port}',
            );
          }
        }
      }
    });
  }

  /// Sends a DNS query to multicast addresses
  Future<void> _sendQuery(DNSMessage query) async {
    final data = query.pack();
    _log('Sending ${data.length} byte DNS query packet');

    bool ipv4Error = true;
    bool ipv6Error = true;

    if (_ipv4UnicastConn != null) {
      try {
        _ipv4UnicastConn!.send(data, InternetAddress(ipv4mDNS), mDNSPort);
        _log('Sent query via IPv4 unicast to $ipv4mDNS:$mDNSPort');
        ipv4Error = false;
      } catch (e) {
        _log('Failed to send query via IPv4 unicast: $e');
      }
    }

    if (_ipv6UnicastConn != null) {
      try {
        _ipv6UnicastConn!.send(data, InternetAddress(ipv6mDNS), mDNSPort);
        _log('Sent query via IPv6 unicast to $ipv6mDNS:$mDNSPort');
        ipv6Error = false;
      } catch (e) {
        _log('Failed to send query via IPv6 unicast: $e');
      }
    }

    if (ipv4Error && ipv6Error) {
      _log('Failed to send query on both IPv4 and IPv6 connections');
      throw StateError(
        'Failed to send mDNS query on both IPv4 and IPv6 connections',
      );
    }

    if (!ipv4Error && !ipv6Error) {
      _log('Query sent successfully on both IPv4 and IPv6 connections');
    } else if (!ipv4Error) {
      _log('Query sent successfully on IPv4 connection only');
    } else if (!ipv6Error) {
      _log('Query sent successfully on IPv6 connection only');
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
    if (_closed) {
      _log('Close requested but client is already closed');
      return;
    }

    _log('Closing mDNS client...');
    _closed = true;

    int closedConnections = 0;

    if (_ipv4UnicastConn != null) {
      _ipv4UnicastConn!.close();
      closedConnections++;
      _log('Closed IPv4 unicast connection');
    }

    if (_ipv6UnicastConn != null) {
      _ipv6UnicastConn!.close();
      closedConnections++;
      _log('Closed IPv6 unicast connection');
    }

    if (_ipv4MulticastConn != null) {
      _ipv4MulticastConn!.close();
      closedConnections++;
      _log('Closed IPv4 multicast connection');
    }

    if (_ipv6MulticastConn != null) {
      _ipv6MulticastConn!.close();
      closedConnections++;
      _log('Closed IPv6 multicast connection');
    }

    _log(
      'mDNS client closed successfully ($closedConnections connections closed)',
    );
    _closedCompleter.complete();
  }

  /// Returns a future that completes when the client is closed
  Future<void> get onClosed => _closedCompleter.future;

  /// Log a message
  void _log(String message) {
    final logger = _logger;
    if (logger != null) {
      logger('[mDNS Client] $message');
    }
  }
}

/// Helper class for message and source address
class _MessageAddr {
  final DNSMessage message;
  final InternetAddress source;
  final int port;

  _MessageAddr(this.message, this.source, this.port);
}

/// Helper class for matching service entries against the requested service
class _ServiceMatcher {
  final String _fullServicePattern;

  _ServiceMatcher(String service, String domain)
    : _fullServicePattern = '${_trimDot(service)}.${_trimDot(domain)}.';

  /// Checks if a service entry name matches the requested service
  bool matches(String serviceName) {
    if (serviceName.isEmpty) return false;

    // Normalize the service name
    final normalizedName = serviceName.endsWith('.')
        ? serviceName
        : '$serviceName.';

    // Direct match check
    if (normalizedName.toLowerCase().endsWith(
      _fullServicePattern.toLowerCase(),
    )) {
      return true;
    }

    // Check if it's an instance of the requested service
    // Instance names typically follow the pattern: "Instance Name._service._tcp.local."
    final parts = normalizedName.split('.');
    if (parts.length >= 3) {
      // Rebuild the service pattern from the parts (skip the instance name)
      final serviceFromName = parts.skip(1).join('.');
      if (serviceFromName.toLowerCase() == _fullServicePattern.toLowerCase()) {
        return true;
      }
    }

    return false;
  }
}

/// Trims dots from start and end of string
String _trimDot(String s) {
  return s.replaceAll(RegExp(r'^\.+|\.+$'), '');
}
