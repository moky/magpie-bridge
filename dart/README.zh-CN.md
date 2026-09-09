# magpie_bridge (Dart)

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Dart](https://img.shields.io/badge/dart-2.17+-blue.svg)](https://pub.dev/packages/magpie_bridge)

可靠的 UDP 中继网络 —— Dart 协议库。

本包实现 Magpie Bridge 协议编解码：报文打包、解包、校验、消息分包与应答辅助。

> [English](README.md)

## 安装

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  magpie_bridge: ^0.1.0
```

然后运行：

```bash
dart pub get
```

## 快速开始

```dart
import 'package:magpie_bridge/magpie_bridge.dart';

void main() {
  // 构造并发送一个小报文
  final pkt = Packet(
    type: typeMini,
    targetBid: 42,
    sourceBid: 7,
    sn: 1,
    body: [104, 101, 108, 108, 111], // 'hello'
  );
  final data = pkt.pack(); // 可直接通过 UDP 发送的 Uint8List

  // 解析收到的报文
  final received = Packet.unpack(data);
  print(received.body); // [104, 101, 108, 108, 111]

  // 将大消息拆分为多个分片
  final message = List<int>.filled(5000, 120);
  final segments = splitMessage(message, 2, 7, 42);
  for (final seg in segments) {
    send(seg.pack());
  }

  // 构造应答包
  final ack = buildAck(received);
  send(ack.pack()); // body = [0x4F, 0x4B] ('OK')，bid 对调
}
```

## 协议概览

| 字段             | 大小     | 说明                               |
| ---------------- | -------- | ---------------------------------- |
| Magic Code       | 4 B      | `MB\x00\x01`（Magpie Bridge v1）   |
| Type             | 1 B      | 包类型 + 参数宽度                  |
| Head Length      | 1 B      | 20 / 22 / 24 / 28                  |
| Body Length      | 2 B      | 报文体字节数                       |
| Target Bridge ID | 4 B      | 目标 bid                           |
| Source Bridge ID | 4 B      | 源 bid                             |
| Serial Number    | 4 B      | 消息身份标识                       |
| index / count    | 0/2/4/8 B| 分片序号 / 分片总数                |
| Body             | 0..1200 B| 应用负载                           |

- 最大 UDP 负载（MSS）：**1232** 字节（1280 - 40 - 8，双栈安全）。
- 最大报文体：**1200** 字节。
- 完整规范见 `../docs/design-protocol.md`。

## API 参考

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

- `pack() -> Uint8List` — 序列化。
- `Packet.unpack(List<int> bytes) -> Packet` — 解析。
- `validate() -> bool` — 检查报文是否合法。
- `messageId -> int` — 去重键（数据包为 `sn`，应答包为
  `(sn << (type & 0x0F)) | index`）。
- `headLength`、`paramWidth`、`isAck` — 派生属性。

### 辅助函数

- `selectType(int messageSize) -> int` — 按消息大小选择 Type。
- `splitMessage(List<int> data, int sn, int sourceBid, int targetBid) -> List<Packet>`。
- `buildAck(Packet packet) -> Packet` — 构造 `'OK'` 应答包。
- `buildControl(List<int> body, int sn, {int sourceBid, int targetBid}) -> Packet`
  — 构造控制报文（SYN/ACK/PING/PONG/FIN），Type 为 0。

### 异常

- `ProtocolException` — 报文非法或解析失败时抛出。

## 开发

```bash
cd dart
dart pub get
dart analyze
dart test
```

## 许可证

MIT — 见 [LICENSE](LICENSE)。
