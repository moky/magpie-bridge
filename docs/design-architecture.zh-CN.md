# Magpie Bridge 架构设计

网络结构为 **N:1 的 C-S 结构**：服务器 S 是离散型转发节点，可高效为众多客户端提供转发服务，但仅限于已在本服务器注册的客户端。服务器只做最简单转发，不与其他服务器关联。

## 1. 系统架构

```mermaid
flowchart LR
    subgraph clients
        C1[客户端 1]
        C2[客户端 2]
        C3[客户端 N]
    end
    subgraph relay
        S[转发服务器 S<br/>单一 UDP 端口]
    end
    C1 -->|"UDP 数据包"| S
    C2 -->|"UDP 数据包"| S
    C3 -->|"UDP 数据包"| S
    S -->|"按 target bid 转发"| C2
    S -->|"按 target bid 转发"| C3
    C1 -. 直连 B=0 .- C2
```

- 服务器在内存维护一张 **yellow_pages：bid → socket** 映射表；
- 客户端经握手向服务器申请 bid（门牌号），此后其他客户端可凭 bid 请求转发。

## 2. 服务器内部架构（收发分离）

接收与转发由**独立线程**处理：接收线程只管收，转发线程（N=256 条）只管发。

```mermaid
flowchart LR
    UDP[(UDP 端口<br/>单端口绑定)] --> R[接收线程]
    R -->|"原样塞入，不判断"| Q1[预处理等待列表]
    Q1 --> PP[预处理线程<br/>校验与指派]
    PP -->|"target=0 系统指令"| MQ[管理请求队列]
    PP -->|"数据包"| Q2[转发等待队列<br/>source bid 取模分配]
    MQ --> MT[管理线程<br/>握手/心跳/挥手]
    Q2 --> FT1[转发线程 1]
    Q2 --> FT2[转发线程 2]
    Q2 --> FTN[转发线程 256]
    MT -->|"SYN! / PONG 等"| UDP
    FT1 -->|"UDP 发送"| UDP
    FT2 -->|"UDP 发送"| UDP
    FTN -->|"UDP 发送"| UDP
```

- **接收线程**：绑定一个 UDP 端口，收到包不做任何判断，连同 socket 信息塞进预处理等待列表。UDP 单端口不随用户数增加 fd 占用；
- **预处理线程**：校验并指派（见下）；
- **管理线程**：处理握手 / 心跳 / 挥手等系统指令；
- **转发线程（N=256）**：轮询并发送数据包。

## 3. 预处理校验链

```mermaid
flowchart TD
    P[取出数据包 + socket] --> V1{协议头校验}
    V1 -- 错误 --> DR[丢弃]
    V1 -- 通过 --> V2{B=1?<br/>服务器只处理桥接包}
    V2 -- 否 --> DR
    V2 -- 是 --> V3{target bid = 0?}
    V3 -- 是 --> MG[交管理线程]
    V3 -- 否 --> V4{source bid = 0?}
    V4 -- 是 --> DR
    V4 -- 否 --> V5{bid 与 socket 匹配?<br/>查 yellow_pages}
    V5 -- 不匹配 --> DR
    V5 -- 匹配 --> UP[更新活跃时间]
    UP --> AS[指派转发线程<br/>n = source bid % 256]
```

> source bid=0 时 target bid 必为 0（仅"第一次握手包"如此）；若 source=0 而 target≠0，属错误包直接丢弃。

## 4. 管理线程

从管理请求队列取包，识别指令类型；无法识别为下列任一类型（未知 command）直接丢弃。

```mermaid
flowchart TD
    P[取出管理请求] --> C{判断类型}
    C -->|"source bid = 0<br/>（command 应为 SYN?）"| H1[第一次握手]
    C -->|"command = ACK!<br/>source bid > 0"| H3[第三次握手]
    C -->|"command = PING<br/>source bid > 0"| HB[心跳]
    C -->|"command = FIN?<br/>source bid > 0"| FW[挥手]
    C -->|"未知 command"| DR[丢弃]
    H1 --> H1A[分配空记录 bid<br/>登记当前 socket]
    H1A --> H1B[回复 SYN!<br/>不指派转发线程]
    H3 --> H3A[source bid 查表]
    H3A --> H3B{socket 匹配?}
    H3B -- 否 --> DR
    H3B -- 是 --> H3C[更新活跃时间<br/>指派转发线程]
    HB --> HB1[回复 PONG<br/>更新活跃时间]
    FW --> FW1[删除记录<br/>释放 bid]
```

## 5. 转发线程（N=256）

预处理线程指派任务时计算 `n = (source bid) % N`，交给第 n 条转发线程；线程内为每个 source bid 建一个等待转发队列。

```mermaid
flowchart TD
    L[开始轮询] --> S[轮询辖下 source bid]
    S --> E{某队列非空?}
    E -- 否 --> SL[sleep 一小段]
    SL --> L
    E -- 是 --> T[取出队首数据包<br/>查 target bid]
    T --> A{存在且活跃?}
    A -- 否 --> DR[丢弃，进入下一循环]
    A -- 是 --> SEND[经 UDP 发送到<br/>target 对应 socket]
    SEND --> L
```

- **广度优先**：轮询辖下所有 source bid 的队列，避免单个用户洪泛挤占其他用户；
- **流量控制**：设定单位时间处理上限，防止流量风暴；因任务拆分到 256 条线程，单线程达上限不影响其他线程，风暴被限制在小范围。
