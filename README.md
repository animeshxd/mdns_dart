# mdns_dart

A pure Dart mDNS (Multicast DNS) library for service discovery and advertising. This library is a port of HashiCorp's mDNS implementation.

## Features

| Feature | This Library | multicast_dns | nsd | flutter_nsd |
|---------|-------------|---------------|-----|-------------|
| **Interface Binding** | Full support | Default only | Platform dependent | Platform dependent |
| **Docker/Bridge Networks** | Works perfectly | Limited | Inconsistent | Inconsistent |
| **Service Advertising** | Full server | Discovery only | Via platform APIs | Via platform APIs |
| **Pure Dart** | No native deps | Pure Dart | Platform plugins | Platform plugins |
| **ESP32/IoT Discovery** | Excellent | Limited | Depends on platform | Depends on platform |
| **Direct Socket Control** | No control | Limited | No control | No control |
| **Cross-Network Discovery** | Solved | Broken | Platform dependent | Platform dependent |

## Getting Started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  mdns_dart: ^latest
```

## Minimal Example

```dart
import 'package:mdns_dart/mdns_dart.dart';

void main() async {
  // Discover all HTTP services on the local network
  final results = await MDNSClient.discover('_http._tcp');
  for (final service in results) {
    print('Service: \\${service.name} at \\${service.primaryAddress?.address}:\\${service.port}');
  }
}
```

For more advanced usage, see the `example/` directory.

## License

This project is licensed under the MIT License, originally by HashiCorp. See the LICENSE file for details.
