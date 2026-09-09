/// Protocol constants for Magpie Bridge.
library;

/// Magic code: 'M', 'B', 0x00, 0x01 (Magpie Bridge v1)
const List<int> magic = [0x4D, 0x42, 0x00, 0x01];

/// Fixed head size (octets), before the optional parameter area
const int headFixed = 20;

/// Maximum UDP payload size (octets), dual-stack safe: 1280 - 40 - 8
const int mss = 1232;

/// Maximum body size (octets): MSS - 32 (reserved head budget)
const int maxBody = 1200;

/// High bit of Type marks an acknowledgement (reply) packet
const int ackBit = 0x80;

// Data packet types (low nibble = parameter width in octets)
const int typeMini = 0x00; // no parameter area, miniature single packet
const int typeSmall = 0x01; // 1-octet parameters, 1 <= K < 256
const int typeMedium = 0x02; // 2-octet parameters, 256 <= K < 65536
const int typeLarge = 0x04; // 4-octet parameters, 65536 <= K < 2^32

// Acknowledgement packet types
const int typeAckMini = 0x80;
const int typeAckSmall = 0x81;
const int typeAckMedium = 0x82;
const int typeAckLarge = 0x84;

/// Mapping from low nibble to parameter width (octets)
const Map<int, int> paramWidthMap = {0: 0, 1: 1, 2: 2, 4: 4};

/// Mapping from low nibble to total head length (octets)
const Map<int, int> headLengthMap = {0: 20, 1: 22, 2: 24, 4: 28};
