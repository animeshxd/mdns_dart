# Examples

A few usage examples for `mdns_dart`:

### Discover HTTP Services

See [`client.dart`](/example/client.dart):

Discovers all HTTP services (`_http._tcp`) on the local network and prints their details.

### Discover Services on Docker/Bridge Networks

See [`client_docker0.dart`](/example/client_docker0.dart):

Discovers services using the `docker0` interface, useful for Docker or bridge network scenarios.

### Advertise a Custom Service

See [`server.dart`](/example/server.dart):

Advertises a custom mDNS service and demonstrates how to discover it on the same network interface.

For more details, refer to the code in each example file.
