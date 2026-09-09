# Magpie Bridge Protocol — Design

> Wire protocol of Magpie Bridge (Reliable UDP Relay Network).
> Source of requirements: `tasks/100-design-protocol.md`.

A frame consists of a **head** and an optional **body**. The receiver MUST
validate every head field and drop the frame on any violation.

## 1. Packet Layout

```
+--------------------------------------------------------------+
| Head (20 octets fixed + optional parameter area)             |
+--------------------------------------------------------------+
| Body (0 .. N octets, N = 1200)                               |
+--------------------------------------------------------------+
```

## 2. Head

### 2.1 Magic Code (fixed, 4 octets)

`'M' (0x4D), 'B' (0x42), 0x00, 0x01` — Magpie Bridge v1.

### 2.2 Meta Field (fixed, 4 octets)

| Field        | Width | Meaning                                          |
| ------------ | ----- | ------------------------------------------------ |
| Type         | 1     | Packet type + parameter width, see below         |
| Head Length  | 1     | Head size: 20 / 22 / 24 / 28                     |
| Body Length  | 2     | Body size; 0 for empty body                      |

**Type** — the low bits select the width of each parameter (`index`, `count`);
the high bit (0x80) marks an acknowledgement (reply). Four size classes:

| Type (data) | Type (reply) | Parameter width | Message size K        | Class            |
| ----------- | ------------ | --------------- | --------------------- | ---------------- |
| 0x00        | 0x80         | none            | miniature (1 packet)  | Micro            |
| 0x01        | 0x81         | 1 octet         | 1 <= K < 256          | General          |
| 0x02        | 0x82         | 2 octets        | 256 <= K < 65536      | Large file       |
| 0x04        | 0x84         | 4 octets        | 65536 <= K < 2^32     | Extra-large file |

**Head Length** is derivable from Type but kept as a fast self-check.

**Body Length** must satisfy `head_length + body_length <= MSS`.

### 2.3 Envelope (fixed, 12 octets)

| Field           | Width | Meaning                              |
| --------------- | ----- | ------------------------------------ |
| Target Bridge ID| 4     | Destination bid                      |
| Source Bridge ID| 4     | Originator bid (ACKs return here)    |
| Serial Number   | 4     | Message identity at the source       |

**Serial number** increments **per original message**, not per packet.
Segments of one message share the same `sn`; receivers identify and
deduplicate a (message, segment) pair by combining `sn` and `index`:

```
if type & 0x80 == 0:
    mid = sn
else:
    mid = (sn << (type & 0x0F)) | index
```

### 2.4 Parameter Area (0 / 2 / 4 / 8 octets)

Present only when `Type != 0`:

```
+-----------------+-----------------+
| index (w octets)| count (w octets)|
+-----------------+-----------------+
```

- `count` — total number of segments (`>= 1`).
- `index` — zero-based segment ordinal, `0 <= index < count`.
- Head sizes follow: 20 (no params), 22 (w=1), 24 (w=2), 28 (w=4).

## 3. Body

- Carries the application payload.
- Maximum size `N = 1200`; empty body is allowed (e.g., bare ACKs).

## 4. Payload Size Analysis (MSS and N)

### 4.1 Upper Bound

To avoid IP fragmentation, each emitted datagram must fit the minimum MTU
any path guarantees. RFC 8200 mandates an IPv6 minimum link MTU of 1280.

```
MSS = 1280 - 40 (IPv6 header) - 8 (UDP header) = 1232
```

1232 matches the widely deployed DNS Flag Day 2020 EDNS(0) recommendation.

### 4.2 Body Limit

The head is at most 28 octets (20 fixed + 8 parameter area); the theoretical
maximum body is `1232 - 28 = 1204`. The protocol reserves a 32-octet head
budget:

```
N = MSS - 32 = 1200
```

### 4.3 Evaluation — keep N = 1200

1. **Consistent with QUIC.** RFC 9000 mandates a 1200-octet initial
   datagram (entire UDP payload, including QUIC header). It is battle-tested
   across PPPoE (MTU 1492), VPN tunnels (~1400), and mobile networks; a
   1200-octet body plus a 28-octet head (1228 total) stays within the same
   budget.
2. **Headroom.** `1228 <= 1232` leaves 4 octets for future head extensions
   (e.g., a hop-count field) without touching `N`.
3. **Round number.** 1200 is easy to reason about, test, and document; the
   cost vs. the theoretical 1204 is negligible (0.3%).

Optional future work: Datagram PLPMTUD (RFC 8899) to raise the limit per
destination (e.g., 1472 on plain IPv4 Ethernet); `N` remains the safe
protocol-wide default.
