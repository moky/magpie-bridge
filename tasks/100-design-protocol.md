# Magpie Bridge Protocol

通讯协议格式主要由**协议头(head)**和**协议体(body)**两部分组成。


## 协议头 (Head)

协议头包括固定的 20 字节和可变的参数区组成。
接收方收到信息包之后，需要逐个检查协议头中各个字段，如果不符合规范可直接丢弃。

### 0. Magic Code (固定4字节）

> 'M', 'B', '\0', '\1'

表示 Magic Bridge v1

### 1. 测量校验区 （固定4字节）

这里包含 3 个参数，用于判断包类型、检查参数长度等。

#### 1.1. 类型 Type （1字节）

这里定义了包类型（数据包、应答包）以及参数 (index, count) 长度，
其中 count 是分包总数，index 是当前数据包编号。

- 0 - 无参数（无需分包的微型数据包）
- 1 - 参数长度为 1 字节（1 <= K < 256)
- 2 - 参数长度为 2 字节 (256 <= K < 65536)
- 4 - 参数长度为 4 字节 (65536 <= K < 4294967296 = 4G)

最高位为应答标识符，所以应答包的取值也是4个，与上面一一对应：

- 0x80
- 0x81
- 0x82
- 0x84

4种规格分别对应：

- 微型数据包
- 一般数据包
- 大文件
- 超大文件

#### 1.2. 协议头长度 （1字节）

无分包时固定为 20，有分包时分别为 22、24、28（包含参数区）。

#### 1.3. 协议体长度 （2字节）

头长度 + 体长度 = 整个数据包总长度 <= MSS

### 2. Envelope （固定12字节）

这里包含门牌号（bid）和数据序列号（sn）。

1. Target Bridge ID (4 bytes)
2. Source Bridge ID (4 bytes)
3. Serial Number    (4 bytes)

其中，序列号 sn 根据需要发送的原始数据包自增。
这里需要注意：不是针对单个包自增，如果是拆分包（type 最高标志位为 1），则 sn 相同，此时需要根据 sn + index 拼接去重：

```
if type & 0x80 == 0:
    mid = sn
else:
    mid = (sn << (type & 0x0F)) | index
```

### 3. 参数区

当需要发送的数据（文件）较大时，需要分包并给出 index, count 参数。无需分包时数据区为空。

2. index (1/2/4 bytes)
3. count (1/2/4 bytes)

其中 0 <= index < count

## 协议体 (Body)

协议体最大长度不超过 N 字节。
取值 N = 1200 的依据：
假设前提是协议打包后，在整个网络传输过程中，不超过任意现行网关的网络数据帧大小要求，从而减少再次被分包带来的额外成本。

```

    """
        Maximum Segment Size
        ~~~~~~~~~~~~~~~~~~~~
        Buffer size for receiving package

        Ethernet MTU      : 1500 bytes (L3 IP packet limit, excludes 14B ethernet header & 4B FCS)
        IPv4 min header   :   20 bytes
        IPv6 fixed header :   40 bytes
        TCP header        :   20 bytes
        UDP header        :    8 bytes

        RFC2460: IPv6 minimum guaranteed IP packet size = 1280 bytes
    """
    # IPv4 UDP theoretical limit: 1500 - 20 - 8 = 1472
    # IPv6 UDP theoretical limit under MTU=1500: 1500 - 40 - 8 = 1452
    # Global dual-stack safe payload (avoid IP fragmentation):
    MSS = 1232  # 1280 - 40 - 8
```

考虑到本协议的头部大小预留值为32字节，因而取包体的最大值为 1200。
这是一个值得讨论的值，请在查阅相关资料后重新评估并给出最佳的建议。
