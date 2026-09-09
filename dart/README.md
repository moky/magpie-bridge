# magpie_bridge (Dart)

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Dart](https://img.shields.io/badge/dart-2.17+-blue.svg)](https://pub.dev/packages/magpie_bridge)

Reliable UDP Relay Network — wire protocol library for Dart.

This package implements the Magpie Bridge protocol codec: packet packing,
unpacking, validation, message segmentation, and acknowledgement helpers.

> [中文文档](README.zh-CN.md)

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  magpie_bridge: ^0.1.0
```

Then run:

```bash
dart pub get
```

## Quick Start

```dart
import 'package:magpie_bridge/magpie_bridge.dart';

void main() {
  // Build and send a small packet
  final pkt = Packet(
    type: typeMini,
    targetBid: 42,
    sourceBid: 7,
    sn: 1,
    body: [104, 101, 108, 108, 111], // 'hello'
  );
  final data = pkt.pack(); // Uint8List ready for UDP send

  // Parse a received packet
  final received = Packet.unpack(data);
  print(received.body); // [104, 101, 108, 108, 111]

  // Split a large message into segments
  final message = List<int>.filled(5000, 120);
  final segments = splitMessage(message, 2, 7, 42);
  for (final seg in segments) {
    send(seg.pack());
  }

  // Build an acknowledgement
  final ack = buildAck(received);
  send(ack.pack()); // body = [0x4F, 0x4B] ('OK'), bids swapped
}
```

## Protocol Overview

| Field             | Size     | Description                          |
| ----------------- | -------- | ------------------------------------ |
| Magic Code        | 4 B      | `MB\x00\x01` (Magpie Bridge v1)      |
| Type              | 1 B      | packet type + parameter width        |
| Head Length       | 1 B      | 20 / 22 / 24 / 28                    |
| Body Length       | 2 B      | body size in octets                  |
| Target Bridge ID  | 4 B      | destination bid                      |
| Source Bridge ID  | 4 B      | originator bid                       |
| Serial Number     | 4 B      | message identity                     |
| index / count     | 0/2/4/8 B| segment ordinal / total segments     |
| Body              | 0..1200 B| application payload                  |

- Maximum UDP payload (MSS): **1232** octets (1280 - 40 - 8, dual-stack safe).
- Maximum body size: **1200** octets.
- See `../docs/design-protocol.md` for the full specification.

## API Reference

### `Packet`

```dart
Packet({
  int type = typeMini,
  int targetBid = 0,
  int sourceBid = 0,
  int sn = 0,
  int? index,
  int? count,
  List<int> body = const [],
})
```

- `pack() -> Uint8List` — serialize.
- `Packet.unpack(List<int> bytes) -> Packet` — parse.
- `validate() -> bool` — check whether the packet is well-formed.
- `messageId -> int` — deduplication key (`sn` for data packets,
  `(sn << (type & 0x0F)) | index` for ACKs).
- `headLength`, `paramWidth`, `isAck` — derived properties.

### Helpers

- `selectType(int messageSize) -> int` — choose Type by message size.
- `splitMessage(List<int> data, int sn, int sourceBid, int targetBid) -> List<Packet>`.
- `buildAck(Packet packet) -> Packet` — build a `'OK'` acknowledgement.
- `buildControl(List<int> body, int sn, {int sourceBid, int targetBid}) -> Packet`
  — build a control packet (SYN/ACK/PING/PONG/FIN) with Type 0.

### Exceptions

- `ProtocolException` — thrown on invalid packets or parsing failures.

## Development

```bash
cd dart
dart pub get
dart analyze
dart test
```

## License

MIT — see [LICENSE](LICENSE).
