## 2.2.1
- Refactored `MDNSService.create` to avoid filtering out explicitly provided IP addresses.  

## 2.2.0
- Refactored `MDNSService.create` to use usable `InternetAddress` from `NetworkInterface` by default. ([#13](https://github.com/animeshxd/mdns_dart/issues/13))
- Fixed IPv6 serialization for `AAAARecord` to ensure correct formatting in mDNS responses. ([#11](https://github.com/animeshxd/mdns_dart/pull/11))
- Added simple integration tests to verify full client-to-server discovery workflows.
- Added unit tests for DNS message parsing.
- Added unit tests for `QuerySession`, `MDNSService`, `MDNSService.create` and `MDNSService.records`.
- Added unit tests for `trimDot` and `isValidFQDN` utility functions.
- Extracted mDNS query record assembly and state management logic into a new `QuerySession` class.
- Refactored `trimDot` and `isValidFQDN` helpers to `src/utils.dart` and made them public.
- Updated `ServiceEntry.addrV4` and `ServiceEntry.addrV6` to use `firstOrNull` for `Bad State: No element` error.
- Removed print as default logging for `MDNSServer` and relied on user-provided logger instead. 

## 2.1.0
- Added note on client_docker0.dart example about unicast responses in Docker environments.
- Added missing logic to bind the IPv6 unicast socket to the interface's specific IP address.
- Bound unicast sockets to the specific IP address of the selected network interface on initialization.
- Refactored `_initialize` from `_Client` and split into `_bindUnicastSocket` and `_bindMulticastSocket` for better maintainability.

## 2.0.1
- Refactored `_createResponse` from `MDNSServer` to use `DNSFlags` constants for clarity.
- Improved documentation for `QueryParams.service` parameter to clarify expected format.
- Reformatted all code for improved consistency and readability.

## 2.0.0
- Changed the default value of `reusePort` to `false`. Implementations that require port reuse must now explicitly set `reusePort: true`. ([#6](https://github.com/animeshxd/mdns_dart/issues/6))
- Lowered minimum Dart SDK constraint to `^3.0.0` for wider compatibility. ([#5](https://github.com/animeshxd/mdns_dart/issues/5))
- Significantly simplified the `discover` method by removing redundant timeout, result, and error handling logic.
- Removed the unused `entriesController` property from `QueryParams`.
- Cleaned up the `QueryParams.defaultFor` factory to remove redundant default values.
- Fixed incorrect placement of the documentation for the `setMulticastInterface` extension method.
- Added a note to `QueryParams.reusePort` regarding potential socket binding issues on Android.

## 1.1.1
- Reformatted all code for improved consistency and readability.
- Enhanced error handling and logging for mDNS query sending over IPv4 and IPv6
- `_sendQuery` now throws a `StateError` if mDNS query sending fails for both IPv4 and IPv6.

## 1.1.0

- Added support for multiple addresses in a `ServiceEntry`
- Added filtering to ignore non-service related mDNS packets
- Added NSEC record support with proper type 47 handling per RFC 4034
- Improved unknown record type handling with explicit logging

## 1.0.5

- Updated package description to specify support for both mDNS service discovery and advertisement.

## 1.0.4

- Added configurable socket options: `reusePort`, `reuseAddress`, and `multicastHops`
- Added comprehensive logging support for debugging network issues
- Minimized example files for cleaner demonstration
- Formatted for improved readability

## 1.0.3

- Updated `README.md` with improved feature comparison table and refined examples.
- Improved example/example.md

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

