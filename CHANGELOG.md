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

