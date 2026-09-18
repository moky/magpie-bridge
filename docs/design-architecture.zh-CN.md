# Magpie Bridge 架构设计

## 网络拓扑

N:1 C-S 结构。服务器 S 为独立转发节点，仅服务于在本服务器注册的客户端。

```mermaid
flowchart TD
    subgraph 客户端
        A["客户端 A<br/>bid=100"]
        B["客户端 B<br/>bid=200"]
        C["客户端 C<br/>bid=300"]
    end
    A -.->|"直连 B=0"| B
    A -->|"转发 B=1"| S
    B -->|"转发 B=1"| S
    C -->|"转发 B=1"| S
    S["服务器 S<br/>yellow_pages: bid to socket"]
```

## 服务器线程模型

收发分离：

```mermaid
flowchart TD
    UDP["UDP 端口"] --> R["接收线程"]
    R --> WQ["预处理等待队列"]
    WQ --> P["预处理线程"]
    P -->|"target=0 或管理指令"| MQ["管理请求队列"]
    P -->|"转发包"| D["转发线程 N=256"]
    MQ --> M["管理线程"]
    D --> T["发送至 target socket"]
    M --> SYS["分配 bid / 验证 / 心跳 / 挥手"]
```

### 接收线程

绑定单一 UDP 端口，收到包后连同 socket 直接塞入预处理队列。不随用户数增加 fd 占用。

### 预处理线程

```mermaid
flowchart TD
    P["取出数据包"] --> V1["校验协议头"]
    V1 -->|"失败"| DROP["丢弃"]
    V1 --> V2{"B = 1?"}
    V2 -- "否" --> DROP
    V2 -- "是" --> T{"target = 0?"}
    T -- "是" --> MGT["交管理线程"]
    T -- "否" --> SRC{"source = 0?"}
    SRC -- "是" --> DROP
    SRC -- "否" --> CHK{"socket 匹配 yellow_pages?"}
    CHK -- "否" --> DROP
    CHK -- "是" --> UPD["更新活跃时间"]
    UPD --> DISP["n = source % N, 指派转发线程 n"]
```

### 管理线程

处理 target=0 的管理类包：

| 类型 | 判断依据 | 动作 |
|------|---------|------|
| SYN? | source=0 | 分配 bid，绑定 socket，回 SYN! |
| ACK! | command=ACK! 且 source>0 | 验证 socket，指派转发线程 |
| PING | command=PING | 回 PONG，更新活跃时间 |
| FIN? | command=FIN? | 删除记录，释放 bid |

### 转发线程（N=256）

按 `n = source_bid % N` 分片，每条转发线程维护多个 source bid 的发送队列。

```mermaid
flowchart TD
    L["轮询辖下 source bid"] --> Q{"队列非空?"}
    Q -- "否" --> SLEEP["sleep 一会"] --> L
    Q -- "是" --> POP["取出队首包"]
    POP --> T{"target 存在且活跃?"}
    T -- "否" --> DROP["丢弃"] --> L
    T -- "是" --> SEND["发送至 target socket"] --> L
```

**流量控制**：每线程限流，单用户打满不影响其他线程。
