# Magpie Bridge Workflow — Design

> Connection workflow of Magpie Bridge: handshake, sending, heartbeat,
> and teardown. Source of requirements: `tasks/110-design-workflow.md`.
> Packet format: see `design-protocol.md`.

## 1. Roles and Path Selection

- Two roles: **client** and **forwarding server** (the "bridge").
- If two clients A and B can connect directly, send directly; otherwise
  forward through server S.
- Forwarding servers are independent of each other; each client picks a
  server by measured connectivity (speed).

## 2. Handshake (Bridge Building)

### 2.1 Client to Server (applying for a bid)

The client must obtain a `bid` from the server first; other clients then ask
the server to relay packets using that bid.

1. **1st handshake**: client sends `SYN` (target/source bid = 0, `sn` = its
   initial sequence number) and enters `SYN_SENT`.
2. **2nd handshake**: server replies `SYN+ACK` (target bid = random `x`
   assigned from the socket, source bid = 0, `sn` = its own initial
   sequence number) and enters `SYN_RCVD`. The reply MAY attach the client
   socket info in the body, e.g. `{"udp":"12.34.57.78:12345"}`, with
   `body_size = len(body)`.
3. **3rd handshake**: client replies `ACK` (target bid = 0, source bid =
   `x`); the server validates `x` and binds it with the socket
   `ip:port` to a service thread. Both enter `ESTABLISHED`.

### 2.2 Client to Client (direct)

Both bids are 0, meaning direct sending without relay. Same 3-step
handshake. Each side manages its own half — the link is modeled as two
**directed pipes**, one per direction; each side marks its own pipe
`ESTABLISHED` locally.

### 2.3 Handshake Parameters

| Step      | type | sn      | Body     | Body size |
| --------- | ---- | ------- | -------- | --------- |
| SYN       | 0    | i       | `SYN`    | 3         |
| SYN+ACK   | 128  | i       | `SYN+ACK`| 7         |
| ACK       | 128  | i + 1   | `ACK`    | 3         |

## 3. bid Rules

- A `bid` is an integer ("house number") assigned by the server on first
  contact; the client broadcasts it to other users through other channels.
- `target bid == 0` → the packet is addressed to the server itself (used in
  handshake / teardown).
- `source bid == 0` → only a packet originated by the server; a client must
  not claim it. A client packet with `source bid == 0` and a non-zero
  target is illegal and dropped by the server. Any source bid that does not
  match the server's record for that socket is also dropped.
- The server forwards only when **both bids are non-zero and valid**: it
  looks up both bids, and on success relays the packet **unchanged** to the
  socket of the target bid.

## 4. Sending

### 4.1 Via a Forwarding Server

1. Both clients A and B register their bids on the same server S.
2. A fills both bids into the header and sends the packet to S.
3. S checks: target bid exists and is **active** (has uplink traffic within
   T), and source bid matches the current socket; then updates A's active
   time and forwards the packet unchanged.
4. S does NOT reply an ACK for relayed packets; A confirms receipt via B's
   automatic ACK.

### 4.2 Direct Sending

After the handshake, A sends packets directly to B (both bid fields = 0).

### 4.3 Acknowledgement (B -> A)

On receiving a data packet (direct or relayed), B MUST reply an ACK:

- `type >= 128` (received type OR 0x80);
- body = `OK` (2 octets);
- target/source bids swapped (both 0 for direct, swapping optional);
- `sn` copied unchanged;
- `index`/`count` copied unchanged if present.

## 5. Heartbeat (Keep-alive)

The client periodically checks its own send time; if nothing (including
ACKs) has been sent beyond a preset interval, it sends a heartbeat to keep
the connection alive.

1. **Initiate**: A sends `PING` to B/S — `sn` = its own incremented `i`,
   `type` = 0, body = `PING` (4 octets).
2. **Reply**: B/S auto-replies `PONG` — `sn` = received `i`, `type` = 128,
   body = `PONG` (4 octets).

Notes:

- The server never initiates heartbeats; the C-S connection state is
  maintained by the client.
- For direct connections, each directed pipe is maintained by its own
  initiator.

## 6. Teardown (Wave)

Unlike TCP's 4-way teardown, this protocol closes directly:

1. **Active close**: A sends `FIN` (body `FIN`, 3 octets) to S (or B),
   enters `FIN_WAIT`.
2. **Passive close**: S (or B) replies `ACK` and closes immediately.
3. A closes after receiving the ACK, or after 2MSL without it.

For direct connections, each directed pipe is closed by its own initiator;
when one side passively closes a pipe, it then actively closes the reverse
pipe — overall resembling TCP's 4-way teardown.

### 6.1 Teardown Parameters

| Step    | type | sn | Body      | Body size |
| ------- | ---- | -- | --------- | --------- |
| FIN     | 0    | i  | `FIN`     | 3         |
| FIN+ACK | 128  | i  | `FIN+ACK` | 7         |
