# Magpie Bridge Workflow Design

Two roles: **client** and **relay server**. Direct connection (B=0) is preferred when possible; otherwise packets go through the server (B=1). Servers are independent; clients pick one by connectivity speed.

> System commands (handshake/heartbeat/farewell) always use **D=0** and carry no dsn; replies pair by **socket** (reply to whichever socket the request came from). In the server scenario source bid validates identity only, never reply addressing. The sender needs no wait-for-reply queue.

## 1. Handshake (connection setup)

### 1.1 Client ↔ Server (apply for bid)

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server
    C->>S: SYN? (target=0, source=0)
    Note right of C: SYN_SENT
    S-->>C: SYN! (target=x, source=0) + socket info
    Note right of S: SYN_RCVD
    C->>S: ACK! (target=0, source=x)
    S->>S: validate x↔socket, assign handler
    Note over C,S: ESTABLISHED, connection up
```

### 1.2 Client ↔ Client (B=0, direct)

```mermaid
sequenceDiagram
    participant A as Client A
    participant B as Client B
    A->>B: SYN? (no bid fields)
    Note right of A: SYN_SENT
    B-->>A: SYN!
    Note right of B: SYN_RCVD
    A->>B: ACK!
    Note over A,B: each side marks one "directional pipe"
```

> The server may attach the client socket info in SYN!, e.g. body `{"udp":"12.34.57.78:12345"}`.

## 2. Sending & Acknowledgement

```mermaid
flowchart LR
    A[Sender A] -->|B=1 relay| S{Server S}
    S -->|validate target/source vs socket<br/>refresh liveness| T[Receiver B]
    T -->|COPY: A=1,C=1,D=1<br/>swap target/source| S
    S -->|relay unchanged| A
    A2[Sender A] -.->|B=0 direct| T2[Receiver B]
    T2 -.->|COPY reply| A2
```

- Data packet: A=0, D=1 (command optional or "DATA"), dsn incremented, with actual segment info;
- Any normal data packet is acknowledged with **COPY** (A=1, C=1, D=1, echoing source dsn/index/count); if B=1, swap target/source;
- The server sends no acknowledgement when relaying; the sender is confirmed by the receiver's COPY;
- System commands (D=0) reply with their own dedicated acknowledgements (SYN!/PONG/FIN!) instead of COPY.

## 3. Farewell (closing connection)

```mermaid
sequenceDiagram
    participant A as Client A
    participant P as Peer (server/client)
    A->>P: FIN? (data done, closing my side)
    Note right of A: FIN_WAIT
    P-->>A: FIN!
    P->>P: close directly
    A->>A: close on receipt (or after 2MSL)
```

> Direct mode has two "directional pipes"; each pipe is closed by its initiator sending FIN. The peer, after passive close, actively closes the reverse pipe — overall similar to TCP's 4-way handshake.

## 4. Heartbeat (keep-alive)

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server/Peer
    Note over C: no packet (replies included) sent beyond the interval
    C->>S: PING (B=1: target=0, source=own bid)
    S-->>C: PONG
    Note over C,S: connection stays alive
```

> The server never initiates heartbeats; the connection state is maintained by the client.
