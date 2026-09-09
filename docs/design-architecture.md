# Magpie Bridge Architecture — Design

> Server-side architecture of Magpie Bridge.
> Source of requirements: `tasks/120-design-architecture.md`.
> Packet format: see `design-protocol.md`; workflows: see
> `design-workflow.md`.

## 1. Network Structure

- N:1 client-server topology; the server S is a **discrete forwarding
  node**.
- One server can efficiently serve many clients, but only clients
  **registered on that server**.
- The server provides the simplest relay only and **does not associate
  with other servers**.

## 2. Server Design Overview

- **Receive/send separation**: receiving and forwarding are handled by
  separate threads.
- The server keeps an in-memory mapping table **`yellow_pages`**:
  `bid -> socket`.

Data flow:

```
UDP port
   |
   v
[Receiver thread] --(packet + socket)--> [Preprocessor queue]
                                               |
                 +-----------------------------+-----------------+
                 v                                               v
        [Manager thread] (target=0)                  [Forward threads x256]
        handshake / heartbeat / teardown             relay to target socket
```

## 3. Thread Model

### 3.1 Receiver Thread

- Binds **one** UDP port on startup.
- Pushes every received packet, together with its socket info, into the
  preprocessor wait list **without any judgment**.
- Because only one UDP port is used, fd usage does not grow with the
  number of clients.

### 3.2 Preprocessor Thread

Pops a packet from the wait list and:

1. **Validate the head** — any error → drop and exit.
2. **target bid == 0** → hand to the manager thread.
3. **source bid == 0** → invalid here → drop and exit.
4. Look up `yellow_pages`: source bid's socket must match the record;
   otherwise drop.
5. On match, update the active time and assign the packet to a forward
   thread.

> Note: `source bid == 0` implies `target bid == 0` as well; such packets
> exist only as the 1st handshake and were already routed by step 2.

### 3.3 Manager Thread

Handles packets from the management queue:

| Case                          | Criterion                      | Action                                   |
| ----------------------------- | ------------------------------ | ---------------------------------------- |
| 1st handshake                 | source bid == 0 (body `SYN`)   | allocate a free bid, register the socket, reply |
| 3rd handshake                 | source bid > 0 (body `ACK`)    | compare socket with record; drop on mismatch; update active time |
| Heartbeat                     | body `PING` (source bid > 0)   | reply `PONG`, update active time         |
| Teardown                      | body `FIN` (source bid > 0)    | delete record, release the bid           |

### 3.4 Forward Threads (N = 256)

- On startup the server spawns N forward threads (default 256).
- The preprocessor assigns a task by hashing: `n = source bid % N`, then
  queues the packet on forward thread `n`.
- Each forward thread keeps one waiting queue **per source bid**.

**Forward thread runloop** — fair, breadth-first:

1. Poll its source bids; if a queue is non-empty, take its head packet.
2. If all queues are empty, sleep briefly and continue.
3. Look up the packet's target bid in `yellow_pages`: if missing or
   inactive, drop and continue.
4. Send the packet to the target bid's socket over the bound UDP interface.

**Flow control**: a limit on the number of tasks processed per time window
prevents traffic storms; since tasks are split across 256 threads, a storm
on one thread does not affect the others and is contained to a small scope.
