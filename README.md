# mdns_dart

## About

`mdns_dart` is a pure Dart implementation of Multicast DNS (mDNS) for service discovery and advertising on local networks. This library is a direct port of the proven [HashiCorp mDNS](https://github.com/hashicorp/mdns) implementation, adapted for the Dart ecosystem. It requires no native dependencies and works across platforms, including Docker and bridge networks.

This project is not affiliated with HashiCorp. All original credit goes to HashiCorp; this port is maintained for Dart and Flutter developers.

## Features

| Feature                  | This Library     | multicast_dns   | nsd                | flutter_nsd        |
|--------------------------|------------------|-----------------|--------------------|--------------------|
| **Interface Binding**    | Full support     | Full support    | Platform dependent | Platform dependent |
| **Docker/Bridge Networks**| Works perfectly  | Limited         | Platform dependent | Platform dependent |
| **Service Advertising**  | Full server      | Discovery only  | Via platform APIs  | Via platform APIs  |
| **Pure Dart**            | No native deps   | Pure Dart       | Platform plugins   | Platform plugins   |
| **Direct Socket Control**| No control       | Limited         | No control         | No control         |
| **Cross-Network Discovery**| Solved           | Broken          | Platform dependent | Platform dependent |

## Installation

```bash
dart pub add mdns_dart
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  mdns_dart: ^latest
```

For the latest development version:

```bash
dart pub add mdns_dart --git-url https://github.com/animeshxd/mdns_dart.git
```

## Usage

### Import

```dart
import 'package:mdns_dart/mdns_dart.dart';
```

### Basic Service Discovery

```dart
final results = await MDNSClient.discover('_http._tcp');
for (final service in results) {
  print('${service.name} at ${service.primaryAddress?.address}:${service.port}');
}
```

For more advanced usage, see the `example/` directory.

## License

This project is licensed under the MIT License, originally by HashiCorp. See the LICENSE file for details.
