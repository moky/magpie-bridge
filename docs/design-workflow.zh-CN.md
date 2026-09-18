# Magpie Bridge 工作流设计

## 角色

- **客户端**：通过 bid 注册到服务器，或直连其他客户端
- **服务器 S**：独立转发节点，维护 yellow_pages（bid → socket），不与其他服务器关联

两种发送途径：直连（B=0）或经服务器转发（B=1）。

## 握手（3 次）

系统指令 D=0，应答配对依靠 socket（从哪来回哪去），无需维护等待队列。

### 客户端 → 服务器（B=1）

```mermaid
sequenceDiagram
    participant C as 客户端
    participant S as 服务器
    Note over C,S: C 申请 bid，target/source 均为 0
    C->>S: SYN? (A=0,C=1,D=0, target=0, source=0)
    Note over S: 分配随机 bid=x，绑定 socket
    S->>C: SYN! (A=1,C=1,D=0, target=x, source=0)
    Note over C: 记录 bid=x
    C->>S: ACK! (A=1,C=1,D=0, target=0, source=x)
    Note over S: 验证 socket 匹配，进入 ESTABLISHED
```

### 客户端 → 客户端（B=0）

```mermaid
sequenceDiagram
    participant A as 客户端 A
    participant B as 客户端 B
    A->>B: SYN? (B=0, 无 bid 字段)
    Note over A: SYN_SENT
    B->>A: SYN!
    Note over B: SYN_RCVD
    A->>B: ACK!
    Note over A,B: 双方各自管理一条有向管道，ESTABLISHED
```

## 挥手（2 次）

不同于 TCP 的 4 次挥手，这里直接关闭：

```mermaid
sequenceDiagram
    participant A as 主动方
    participant B as 被动方
    A->>B: FIN? (A=0,C=1,D=0)
    Note over A: FIN_WAIT
    B->>A: FIN! (A=1,C=1,D=0)
    Note over B: 立即关闭
    Note over A: 收到 ACK 或超时后关闭
```

> C-C 场景下两条有向管道各自独立关闭，总流程类似 TCP 4 次挥手。

## 发送

### 经服务器转发（B=1）

1. A、B 均已在 S 注册 bid
2. A 填写 target=B_bid, source=A_bid，发往 S
3. S 校验：target 存在且活跃、source 与 socket 匹配
4. S 原样转发给 B（不修改包）

> 服务器不回复应答，由 B 自动回 COPY 给 A 确认。

### 直连（B=0）

双方握手建立连接后，直接发送（包头无 bid 字段）。

## 应答（COPY）

收到普通数据包（A=0, D=1）时回复 COPY（A=1, C=1, D=1）：

```mermaid
flowchart TD
    R["收到普通数据包"] --> A1["A = type | 0x80"]
    A1 --> B1{"B = 1?"}
    B1 -- "是" --> SW["target / source 对调"]
    B1 -- "否" --> C1
    SW --> C1["C = type | 0x20, command = COPY"]
    C1 --> D1["dsn / index / count 保持不变"]
    D1 --> E1["B / D / E 标志位不变，body 可空"]
```

系统指令（D=0）不回 COPY，回各自专用应答（SYN!/PONG/FIN!）。

## 心跳

客户端超时未发包则主动发 PING，对端回 PONG。服务器不主动发起，连接保活由客户端负责。

- C-S：B=1，target=0, source=本机 bid
- C-C：B=0，发起方维护自己方向的管道
