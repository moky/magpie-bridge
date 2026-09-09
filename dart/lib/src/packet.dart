import 'dart:typed_data';

import 'constants.dart';
import 'exceptions.dart';

/// A single Magpie Bridge protocol frame (head + body).
class Packet {
  final int type;
  final int targetBid;
  final int sourceBid;
  final int sn;
  final int? index;
  final int? count;
  final List<int> body;

  const Packet({
    this.type = typeMini,
    this.targetBid = 0,
    this.sourceBid = 0,
    this.sn = 0,
    this.index,
    this.count,
    this.body = const [],
  });

  /// Width (octets) of each parameter (index, count).
  int get paramWidth {
    final low = type & 0x0F;
    if (!paramWidthMap.containsKey(low)) {
      throw ProtocolException('invalid type low nibble: $low');
    }
    return paramWidthMap[low]!;
  }

  /// Total head length including the parameter area.
  int get headLength => headFixed + 2 * paramWidth;

  /// True when the high bit of Type is set.
  bool get isAck => (type & ackBit) != 0;

  /// Deduplication key combining sn and index.
  ///
  /// For data packets the key is sn alone; for acknowledgement packets
  /// the key is (sn << (type & 0x0F)) | index.
  int get messageId {
    if ((type & ackBit) == 0) return sn;
    return (sn << (type & 0x0F)) | (index ?? 0);
  }

  /// Serialize the packet to bytes.
  Uint8List pack() {
    final w = paramWidth;
    if (body.length > maxBody) {
      throw ProtocolException('body too large: ${body.length} > $maxBody');
    }
    if (headLength + body.length > mss) {
      throw ProtocolException(
        'packet too large: ${headLength + body.length} > $mss',
      );
    }
    if (w > 0) {
      if (index == null || count == null) {
        throw const ProtocolException(
          'index and count are required for segmented packets',
        );
      }
      if (!(0 <= index! && index! < count!)) {
        throw ProtocolException('invalid index/count: $index/$count');
      }
      final maxVal = (1 << (8 * w)) - 1;
      if (index! > maxVal || count! > maxVal) {
        throw const ProtocolException('index/count exceeds parameter width');
      }
    }

    final total = headLength + body.length;
    final data = ByteData(total);
    var offset = 0;

    // Magic code
    for (var i = 0; i < 4; i++) {
      data.setUint8(offset++, magic[i]);
    }
    // Type
    data.setUint8(offset++, type & 0xFF);
    // Head Length
    data.setUint8(offset++, headLength & 0xFF);
    // Body Length
    data.setUint16(offset, body.length, Endian.big);
    offset += 2;
    // Target / Source / SN (each 4 octets, big-endian)
    data.setUint32(offset, targetBid & 0xFFFFFFFF, Endian.big);
    offset += 4;
    data.setUint32(offset, sourceBid & 0xFFFFFFFF, Endian.big);
    offset += 4;
    data.setUint32(offset, sn & 0xFFFFFFFF, Endian.big);
    offset += 4;
    // index / count
    if (w > 0) {
      _writeUint(data, offset, index!, w);
      offset += w;
      _writeUint(data, offset, count!, w);
      offset += w;
    }
    // Body
    for (var i = 0; i < body.length; i++) {
      data.setUint8(offset++, body[i]);
    }

    return data.buffer.asUint8List();
  }

  static void _writeUint(ByteData data, int offset, int value, int width) {
    switch (width) {
      case 1:
        data.setUint8(offset, value & 0xFF);
        break;
      case 2:
        data.setUint16(offset, value & 0xFFFF, Endian.big);
        break;
      case 4:
        data.setUint32(offset, value & 0xFFFFFFFF, Endian.big);
        break;
      default:
        throw ProtocolException('unsupported width: $width');
    }
  }

  static int _readUint(ByteData data, int offset, int width) {
    switch (width) {
      case 1:
        return data.getUint8(offset);
      case 2:
        return data.getUint16(offset, Endian.big);
      case 4:
        return data.getUint32(offset, Endian.big);
      default:
        throw ProtocolException('unsupported width: $width');
    }
  }

  /// Parse bytes into a Packet.
  static Packet unpack(List<int> bytes) {
    if (bytes.length < headFixed) {
      throw ProtocolException(
        'packet too short: ${bytes.length} < $headFixed',
      );
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));

    // Magic code
    for (var i = 0; i < 4; i++) {
      if (data.getUint8(i) != magic[i]) {
        throw const ProtocolException('bad magic code');
      }
    }

    final type = data.getUint8(4);
    final headLen = data.getUint8(5);
    final bodyLen = data.getUint16(6, Endian.big);

    if (headLen + bodyLen != bytes.length) {
      throw ProtocolException(
        'length mismatch: head=$headLen body=$bodyLen total=${bytes.length}',
      );
    }

    final low = type & 0x0F;
    if (!paramWidthMap.containsKey(low)) {
      throw ProtocolException('invalid type low nibble: $low');
    }
    final w = paramWidthMap[low]!;
    final expectedHead = headFixed + 2 * w;
    if (headLen != expectedHead) {
      throw ProtocolException(
        'head length mismatch: $headLen != $expectedHead',
      );
    }

    final target = data.getUint32(8, Endian.big);
    final source = data.getUint32(12, Endian.big);
    final sn = data.getUint32(16, Endian.big);

    int? index;
    int? count;
    if (w > 0) {
      index = _readUint(data, 20, w);
      count = _readUint(data, 20 + w, w);
    }

    final body = bytes.sublist(headLen, headLen + bodyLen);
    return Packet(
      type: type,
      targetBid: target,
      sourceBid: source,
      sn: sn,
      index: index,
      count: count,
      body: body,
    );
  }

  /// Return true if the packet can be packed without error.
  bool validate() {
    try {
      pack();
      return true;
    } on ProtocolException {
      return false;
    }
  }

  @override
  String toString() =>
      'Packet(type=0x${type.toRadixString(16).padLeft(2, '0')}, '
      'target=$targetBid, source=$sourceBid, sn=$sn, '
      'index=$index, count=$count, body=${body.length}B)';
}

// -- helpers ---------------------------------------------------------------

/// Select the data packet Type for a message of size K (octets).
int selectType(int messageSize) {
  if (messageSize <= 0) return typeMini;
  if (messageSize < 256) return typeSmall;
  if (messageSize < 65536) return typeMedium;
  return typeLarge;
}

/// Split a message into one or more packets (max [maxBody] octets each).
List<Packet> splitMessage(
  List<int> data,
  int sn,
  int sourceBid,
  int targetBid,
) {
  if (data.isEmpty) {
    return [
      Packet(
        type: typeMini,
        targetBid: targetBid,
        sourceBid: sourceBid,
        sn: sn,
        body: const [],
      ),
    ];
  }
  final type = selectType(data.length);
  final count = (data.length + maxBody - 1) ~/ maxBody;
  final packets = <Packet>[];
  for (var i = 0; i < count; i++) {
    final start = i * maxBody;
    final end = (start + maxBody).clamp(0, data.length);
    final chunk = data.sublist(start, end);
    packets.add(Packet(
      type: type,
      targetBid: targetBid,
      sourceBid: sourceBid,
      sn: sn,
      index: i,
      count: count,
      body: chunk,
    ));
  }
  return packets;
}

/// Build a data acknowledgement (body = 'OK') for the given packet.
Packet buildAck(Packet packet) {
  return Packet(
    type: packet.type | ackBit,
    targetBid: packet.sourceBid,
    sourceBid: packet.targetBid,
    sn: packet.sn,
    index: packet.index,
    count: packet.count,
    body: const [0x4F, 0x4B], // 'O', 'K'
  );
}

/// Build a control packet (SYN/ACK/PING/PONG/FIN) using Type 0 (mini).
Packet buildControl(
  List<int> body,
  int sn, {
  int sourceBid = 0,
  int targetBid = 0,
}) {
  return Packet(
    type: typeMini,
    targetBid: targetBid,
    sourceBid: sourceBid,
    sn: sn,
    body: body,
  );
}
