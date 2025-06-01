## 1.0.2

- Exported `src/server.dart` in the public API (lib/mdns_dart.dart) for direct access to mDNS server functionality.

## 1.0.1

- Fixed deprecated `multicastInterface` usage with modern `setRawOption` implementation

## 1.0.0

- Initial release: Port of HashiCorp's mDNS to Dart
- Comprehensive mDNS service discovery with full protocol support
- Interface binding for cross-network discovery 
- Support for both IPv4 and IPv6
- Docker/bridge network compatibility
- Full mDNS server for service advertising
- Pure Dart implementation with no native dependencies

