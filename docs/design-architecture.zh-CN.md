# Magpie Bridge 架构设计

网络结构为 **N:1 的 C-S 结构**：S 为离散型转发节点，只为已在本服务器注册的客户端服务；服务器互不关联，只做最简单的转发。

## 1. 系统架构

```mermaid
graph TB
    subgraph CL[客户端]
        A[客户端 A<br/>bid=a]
        B[客户端 B<br/>bid=b]
        C[客户端 C<br/>bid=c]
    end
    subgraph SV[转发服务器]
        S[服务器 S<br/>yellow_pages: bid→socket]
    end
    A -- "B=1 转发" --> S
    B -- "B=1 转发" --> S
    C -- "B=1 转发" --> S
    S -- "按 target bid 原样转发" --> A
    S -- "按 target bid 原样转发" --> B
    A -. "B=0 直连" .-> B
    B -. "B=0 直连" .-> C
```

要点：

- 可直连时优先直连（B=0，无 bid 字段）；否则经服务器转发（B=1）；
- 服务器只按 yellow_pages 中 bid→socket 映射转发，不改动数据包；
- 客户端通过握手申请 bid 并广播，其他客户端凭 bid 请求转发。

## 2. 服务器内部架构

```mermaid
flowchart LR
    UDP[UDP 端口<br/>接收线程] -->|数据包 + socket| PRE[预处理线程]
    PRE -->|校验链| CHK{target bid?}
    CHK -- 0 --> MGR[管理线程<br/>握手/心跳/挥手]
    CHK -- 非 0 --> FWD[转发线程 ×256<br/>n = source bid % 256]
    MGR --> YP[(yellow_pages<br/>bid→socket)]
    FWD --> YP
    FWD -->|原样转发| TGT[target bid 的 socket]
```

**预处理校验链**（任一失败即丢弃）：

```mermaid
flowchart TD
    P[取包] --> V1[校验协议头]
    V1 -- 错误 --> DR[丢弃]
    V1 -- OK --> V2{B=1?}
    V2 -- 否 --> DR
    V2 -- 是 --> V3{target=0?}
    V3 -- 是 --> M[交管理线程]
    V3 -- 否 --> V4{source=0?}
    V4 -- 是 --> DR
    V4 -- 否 --> V5{bid↔socket 匹配?}
    V5 -- 否 --> DR
    V5 -- 是 --> UP[更新活跃时间 → 转发线程]
```

| 线程 | 职责 |
|---|---|
| 接收线程 | 绑定单 UDP 端口，收包即入队，不做判断 |
| 预处理线程 | 校验协议头、B=1、target/source 合法性、bid↔socket 匹配，更新活跃时间 |
| 管理线程 | 处理第一次/第三次握手、PING、FIN?；未知 command 丢弃 |
| 转发线程 ×256 | 按 source bid % 256 分片，广度优先轮询，原样转发 |

> source=0 仅存在于第一次握手包（此时 target 必为 0）；若 source=0 而 target≠0 属错误包直接丢弃。

## 3. 管理线程处理

```mermaid
flowchart LR
    Q[管理请求] --> T{识别类型}
    T -->|source=0, SYN?| H1[第一次握手<br/>分配 bid，登记 socket，回 SYN!]
    T -->|ACK!, source≠0| H3[第三次握手<br/>校验 socket，指派转发线程]
    T -->|PING, source≠0| HB[心跳<br/>回 PONG，更新活跃时间]
    T -->|FIN?, source≠0| FW[挥手<br/>删除记录，释放 bid]
    T -->|其他| UN[未知 command 丢弃]
```

## 4. 流量控制

转发线程限流（设定规定时间内最多处理任务数上限）。任务按 `source bid % 256` 拆分给 256 条线程，单条线程达到上限不影响其他线程，将风暴控制在很小的范围内。
