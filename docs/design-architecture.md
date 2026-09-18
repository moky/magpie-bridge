# Magpie Bridge Architecture Design

## Topology

N:1 C-S structure. Server S is an independent relay node, serving only clients registered on it.

```mermaid
flowchart TD
    subgraph Clients
        A["Client A<br/>bid=100"]
        B["Client B<br/>bid=200"]
        C["Client C<br/>bid=300"]
    end
    A -.->|"direct B=0"| B
    A -->|"relay B=1"| S
    B -->|"relay B=1"| S
    C -->|"relay B=1"| S
    S["Server S<br/>yellow_pages: bid to socket"]
```

## Server Thread Model

Receive and forward are separated:

```mermaid
flowchart LR
    UDP["UDP port"] --> R["Receiver thread"]
    R --> WQ["Preprocess queue"]
    WQ --> P["Preprocess thread"]
    P -->|"target=0 or mgmt"| MQ["Mgmt queue"]
    P -->|"forward"| D["Forward threads N=256"]
    MQ --> M["Mgmt thread"]
    D --> T["Send to target socket"]
    M --> SYS["assign bid / verify / ping / teardown"]
```

### Receiver Thread

Binds a single UDP port; on receive, pushes packet + socket into the preprocess queue. No extra fd as users grow.

### Preprocess Thread

```mermaid
flowchart TD
    P["Take packet"] --> V1["Validate header"]
    V1 -->|"fail"| DROP["Drop"]
    V1 --> V2{"B = 1?"}
    V2 -- "No" --> DROP
    V2 -- "Yes" --> T{"target = 0?"}
    T -- "Yes" --> MGT["To mgmt thread"]
    T -- "No" --> SRC{"source = 0?"}
    SRC -- "Yes" --> DROP
    SRC -- "No" --> CHK{"socket matches yellow_pages?"}
    CHK -- "No" --> DROP
    CHK -- "Yes" --> UPD["Update last-active"]
    UPD --> DISP["n = source % N, dispatch to thread n"]
```

### Management Thread

Handles management packets with target=0:

| Type | Key | Action |
|------|-----|--------|
| SYN? | source=0 | allocate bid, bind socket, reply SYN! |
| ACK! | command=ACK! and source>0 | verify socket, dispatch to forward thread |
| PING | command=PING | reply PONG, update last-active |
| FIN? | command=FIN? | delete record, release bid |

### Forward Threads (N=256)

Sharded by `n = source_bid % N`; each forward thread holds send queues per source bid.

```mermaid
flowchart TD
    L["Round-robin over source bids"] --> Q{"queue non-empty?"}
    Q -- "No" --> SLEEP["sleep briefly"] --> L
    Q -- "Yes" --> POP["Dequeue packet"]
    POP --> T{"target exists & active?"}
    T -- "No" --> DROP["Drop"] --> L
    T -- "Yes" --> SEND["Send to target socket"] --> L
```

**Flow control**: per-thread rate limit; one flood cannot affect other threads.
