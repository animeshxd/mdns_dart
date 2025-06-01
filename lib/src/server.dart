/// mDNS server implementation for service advertising.
/// 
/// This module provides an mDNS server that can advertise services on the network
/// using the Zone interface from zone.dart.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'utils.dart';
import 'dns.dart';
import 'zone.dart';

/// mDNS server configuration
class MDNSServerConfig {
  /// Zone containing services to advertise
  final Zone zone;
  
  /// Network interface to bind to (optional)
  final NetworkInterface? networkInterface;
  
  /// Whether to log empty responses for debugging
  final bool logEmptyResponses;
  
  /// Custom logger function (optional)
  final void Function(String message)? logger;
  
  const MDNSServerConfig({
    required this.zone,
    this.networkInterface,
    this.logEmptyResponses = false,
    this.logger,
  });
}

/// mDNS server for advertising services on the network
class MDNSServer {
  static const String _ipv4MulticastAddr = '224.0.0.251';
  static const String _ipv6MulticastAddr = 'ff02::fb';
  static const int _mdnsPort = 5353;
  
  final MDNSServerConfig _config;
  RawDatagramSocket? _ipv4Socket;
  RawDatagramSocket? _ipv6Socket;
  
  bool _isRunning = false;
  final List<StreamSubscription> _subscriptions = [];
  
  MDNSServer(this._config);
  
  /// Start the mDNS server
  Future<void> start() async {
    if (_isRunning) {
      throw StateError('Server is already running');
    }
    
    _log('Starting mDNS server...');
    
    try {
      // Create IPv4 multicast socket
      try {
        _ipv4Socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, 
          _mdnsPort,
          reuseAddress: true,
          reusePort: true,
        );
        
        // Join multicast group
        _ipv4Socket!.joinMulticast(InternetAddress(_ipv4MulticastAddr));
        
        // Set network interface if specified
        if (_config.networkInterface != null) {
          _ipv4Socket!.setMulticastInterface(_config.networkInterface!);
        }
        
        // Listen for packets
        final ipv4Subscription = _ipv4Socket!.listen((event) => _handlePacket(event, _ipv4Socket!));
        _subscriptions.add(ipv4Subscription);
        
        _log('IPv4 multicast socket bound to port $_mdnsPort');
      } catch (e) {
        _log('Failed to create IPv4 socket: $e');
      }
      
      // Create IPv6 multicast socket
      try {
        _ipv6Socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv6, 
          _mdnsPort,
          reuseAddress: true,
          reusePort: true,
        );
        
        // Join multicast group
        _ipv6Socket!.joinMulticast(InternetAddress(_ipv6MulticastAddr));
        
        // Set network interface if specified (IPv6)
        if (_config.networkInterface != null) {
          _ipv6Socket!.setMulticastInterface(_config.networkInterface!);
        }
        
        // Listen for packets
        final ipv6Subscription = _ipv6Socket!.listen((event) => _handlePacket(event, _ipv6Socket!));
        _subscriptions.add(ipv6Subscription);
        
        _log('IPv6 multicast socket bound to port $_mdnsPort');
      } catch (e) {
        _log('Failed to create IPv6 socket: $e');
      }
      
      if (_ipv4Socket == null && _ipv6Socket == null) {
        throw StateError('Failed to create any multicast sockets');
      }
      
      _isRunning = true;
      _log('mDNS server started successfully');
      
    } catch (e) {
      await stop();
      rethrow;
    }
  }
  
  /// Stop the mDNS server
  Future<void> stop() async {
    if (!_isRunning) return;
    
    _log('Stopping mDNS server...');
    
    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    
    // Close sockets
    _ipv4Socket?.close();
    _ipv6Socket?.close();
    _ipv4Socket = null;
    _ipv6Socket = null;
    
    _isRunning = false;
    _log('mDNS server stopped');
  }
  
  /// Handle incoming packets
  void _handlePacket(RawSocketEvent event, RawDatagramSocket socket) {
    if (event == RawSocketEvent.read) {
      final datagram = socket.receive();
      if (datagram == null) return;
      
      try {
        _parseAndHandleQuery(datagram.data, datagram.address, datagram.port, socket);
      } catch (e) {
        _log('Error handling packet: $e');
      }
    }
  }
  
  /// Parse incoming DNS message and handle queries
  void _parseAndHandleQuery(Uint8List data, InternetAddress from, int port, RawDatagramSocket socket) {
    try {
      final message = DNSMessage.parse(data);
      if (message == null) return;
      
      // Only handle queries (not responses)
      if (message.header.isResponse) return;
      
      // Validate mDNS requirements
      if ((message.header.flags >> 11) & 0xF != 0) {
        _log('Ignoring query with non-zero opcode: ${(message.header.flags >> 11) & 0xF}');
        return;
      }
      
      if (message.header.flags & 0xF != 0) {
        _log('Ignoring query with non-zero rcode: ${message.header.flags & 0xF}');
        return;
      }
      
      _handleQuery(message, from, port, socket);
      
    } catch (e) {
      _log('Failed to parse DNS message: $e');
    }
  }
  
  /// Handle a parsed DNS query
  void _handleQuery(DNSMessage query, InternetAddress from, int port, RawDatagramSocket socket) {
    final multicastRecords = <DNSResourceRecord>[];
    final unicastRecords = <DNSResourceRecord>[];
    
    // Handle each question
    for (final question in query.questions) {
      final records = _config.zone.records(question);
      
      if (records.isEmpty) continue;
      
      // Determine if unicast response is requested
      // Check the unicast bit (top bit of qclass)
      final wantsUnicast = (question.dnsClass & 0x8000) != 0;
      
      if (wantsUnicast) {
        unicastRecords.addAll(records);
      } else {
        multicastRecords.addAll(records);
      }
    }
    
    // Log if no responses and logging enabled
    if (_config.logEmptyResponses && multicastRecords.isEmpty && unicastRecords.isEmpty) {
      final questionNames = query.questions.map((q) => q.name).join(', ');
      _log('No responses for query with questions: $questionNames');
    }
    
    // Send multicast response if needed
    if (multicastRecords.isNotEmpty) {
      final response = _createResponse(query, multicastRecords, false);
      _sendResponse(response, socket, isUnicast: false);
    }
    
    // Send unicast response if needed
    if (unicastRecords.isNotEmpty) {
      final response = _createResponse(query, unicastRecords, true);
      _sendResponse(response, socket, isUnicast: true, targetAddress: from, targetPort: port);
    }
  }
  
  /// Create a DNS response message
  DNSMessage _createResponse(DNSMessage query, List<DNSResourceRecord> records, bool isUnicast) {
    // Build flags with proper bit manipulation
    int flags = 0;
    flags |= 0x8000; // QR bit: Response
    flags |= 0x0400; // AA bit: Authoritative Answer
    // Other flags remain 0 (not truncated, no recursion, etc.)
    
    return DNSMessage(
      header: DNSHeader(
        id: isUnicast ? query.header.id : 0, // Use 0 for multicast responses
        flags: flags,
        qdcount: 0, // No questions in response
        ancount: records.length,
        nscount: 0,
        arcount: 0,
      ),
      questions: [], // No questions in response
      answers: records,
      authority: [],
      additional: [],
    );
  }
  
  /// Send a DNS response
  void _sendResponse(
    DNSMessage response, 
    RawDatagramSocket socket, {
    required bool isUnicast,
    InternetAddress? targetAddress,
    int? targetPort,
  }) {
    try {
      final data = response.pack();
      
      if (isUnicast && targetAddress != null && targetPort != null) {
        // Send unicast response directly to querier
        socket.send(data, targetAddress, targetPort);
        _log('Sent unicast response to ${targetAddress.address}:$targetPort (${data.length} bytes)');
      } else {
        // Send multicast response
        final multicastAddr = socket.address.type == InternetAddressType.IPv4
            ? InternetAddress(_ipv4MulticastAddr)
            : InternetAddress(_ipv6MulticastAddr);
        socket.send(data, multicastAddr, _mdnsPort);
        _log('Sent multicast response (${data.length} bytes)');
      }
    } catch (e) {
      _log('Failed to send response: $e');
    }
  }
  
  /// Log a message
  void _log(String message) {
    final logger = _config.logger;
    if (logger != null) {
      logger('[mDNS Server] $message');
    } else {
      print('[mDNS Server] $message');
    }
  }
  
  /// Whether the server is currently running
  bool get isRunning => _isRunning;
}
