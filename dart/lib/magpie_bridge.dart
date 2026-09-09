/// Magpie Bridge protocol library.
///
/// Reliable UDP Relay Network wire protocol codec.
///
/// ```dart
/// import 'package:magpie_bridge/magpie_bridge.dart';
///
/// final pkt = Packet(type: typeMini, targetBid: 42, sourceBid: 7, sn: 1, body: [104, 101, 108, 108, 111]);
/// final data = pkt.pack();
/// final restored = Packet.unpack(data);
/// ```
library magpie_bridge;

export 'src/constants.dart';
export 'src/exceptions.dart';
export 'src/packet.dart';
