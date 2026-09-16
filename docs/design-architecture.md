# Magpie Bridge Architecture Design

The network structure is **N:1 client-server**: server S is a discrete relay node that serves many clients efficiently, but only those registered on it. The server only provides minimal relaying and is not linked to other servers.

## 1. System Architecture

```mermaid
flowchart LR
    subgraph clients
        C1[Client 1]
        C2[Client 2]
        C3[Client N]
    end
    subgraph relay
        S[Relay server S<br/>single UDP port]
    end
    C1 -->|"UDP packets"| S
    C2 -->|"UDP packets"| S
    C3 -->|"UDP packets"| S
    S -->|"relay by target bid"| C2
    S -->|"relay by target bid"| C3
    C1 -. direct B=0 .- C2
```

- The server keeps an in-memory **yellow_pages: bid → socket** mapping table;
- A client applies for a bid (doorplate) via handshake; other clients can then request relaying by bid.

## 2. Server Internals (Separated RX/TX)

Receiving and forwarding are handled by **separate threads**: the receiver only receives; N=256 forwarding threads only send.

```mermaid
flowchart LR
    UDP[(UDP port<br/>single binding)] --> R[Receiver thread]
    R -->|"push raw, no judgment"| Q1[Preprocess wait list]
    Q1 --> PP[Preprocess thread<br/>validate and assign]
    PP -->|"target=0 system cmds"| MQ[Manage request queue]
    PP -->|"data packets"| Q2[Forward queues<br/>assigned by source bid mod]
    MQ --> MT[Manager thread<br/>handshake/heartbeat/wave]
    Q2 --> FT1[Forward thread 1]
    Q2 --> FT2[Forward thread 2]
    Q2 --> FTN[Forward thread 256]
    MT -->|"SYN! / PONG etc."| UDP
    FT1 -->|"UDP send"| UDP
    FT2 -->|"UDP send"| UDP
    FTN -->|"UDP send"| UDP
```

- **Receiver thread**: binds one UDP port, pushes each packet with its socket info into the preprocess wait list without any judgment. One UDP port means fd usage does not grow with users;
- **Preprocess thread**: validates and assigns (see below);
- **Manager thread**: handles system commands such as handshake / heartbeat / wave;
- **Forward threads (N=256)**: poll and send data packets.

## 3. Preprocess Validation Chain

```mermaid
flowchart TD
    P[take packet + socket] --> V1{head valid?}
    V1 -- bad --> DR[drop]
    V1 -- ok --> V2{B=1?<br/>server only handles bridged}
    V2 -- no --> DR
    V2 -- yes --> V3{target bid = 0?}
    V3 -- yes --> MG[hand to manager thread]
    V3 -- no --> V4{source bid = 0?}
    V4 -- yes --> DR
    V4 -- no --> V5{bid matches socket?<br/>lookup yellow_pages}
    V5 -- no --> DR
    V5 -- yes --> UP[update liveness]
    UP --> AS[assign forward thread<br/>n = source bid % 256]
```

> source=0 implies target=0 (only true for the 1st handshake packet); source=0 with target≠0 is a bad packet and dropped.

## 4. Manager Thread

Takes packets from the manage queue and identifies the command type; unknown commands are dropped.

```mermaid
flowchart TD
    P[take manage request] --> C{classify}
    C -->|"source bid = 0<br/>(command should be SYN?)"| H1[1st handshake]
    C -->|"command = ACK!<br/>source bid > 0"| H3[3rd handshake]
    C -->|"command = PING<br/>source bid > 0"| HB[heartbeat]
    C -->|"command = FIN?<br/>source bid > 0"| FW[wave]
    C -->|"unknown command"| DR[drop]
    H1 --> H1A[allocate free bid<br/>register socket]
    H1A --> H1B[reply SYN!<br/>no forward thread assigned]
    H3 --> H3A[lookup source bid]
    H3A --> H3B{socket matches?}
    H3B -- no --> DR
    H3B -- yes --> H3C[update liveness<br/>assign forward thread]
    HB --> HB1[reply PONG<br/>update liveness]
    FW --> FW1[delete record<br/>release bid]
```

## 5. Forward Threads (N=256)

When assigning, the preprocess thread computes `n = (source bid) % N` and hands the packet to thread n; each thread keeps one wait queue per source bid.

```mermaid
flowchart TD
    L[start polling] --> S[poll source bids]
    S --> E{any queue non-empty?}
    E -- no --> SL[sleep briefly]
    SL --> L
    E -- yes --> T[take front packet<br/>lookup target bid]
    T --> A{exists and active?}
    A -- no --> DR[drop, next loop]
    A -- yes --> SEND[send via UDP to<br/>target socket]
    SEND --> L
```

- **Breadth-first**: polls queues of all source bids, so one user flooding cannot starve others;
- **Rate limiting**: a cap on tasks per time unit prevents traffic storms; since work is split across 256 threads, one thread hitting its cap does not affect others, containing storms to a small scope.
