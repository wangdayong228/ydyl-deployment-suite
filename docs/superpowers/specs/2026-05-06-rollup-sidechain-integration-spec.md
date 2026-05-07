# 科技报告 4.2 节写作规格说明
# Rollup 侧链接入方案

**日期**：2026-05-06  
**对应报告章节**：第四章 4.2  
**写作负责人**：大勇  
**写作规范参考**：doc-report/科技报告写作质量指南.markdown

---

## 一、文档定位

本节在整个报告中的位置：

```
第四章 多类型侧链扩展与跨链互操作关键技术研究
  4.1 问题分析与研究目标（李辰星）
  4.2 Rollup 侧链接入方案            ← 本节
  4.3 树图联盟链侧链方案（向荣）
  4.4 多类型侧链规模化部署（大勇）
  ...
```

**本节职责**：论证 OP Stack（乐观 Rollup）和 CDK zkEVM（ZK Rollup）两种主流 Rollup 框架接入 Conflux eSpace 作为 L1 的技术方案，重点在兼容性适配的设计决策和工程实现。不承担对两种 Rollup 原理的介绍，也不承担部署自动化（4.4 节）的内容。

**读者预设**：同领域评审专家，了解 OP Stack 和 ZK Rollup 的基本架构，但不了解 Conflux eSpace 的内部机制，也不了解本项目的具体改动。

---

## 二、总体结构

```
4.2 Rollup 侧链接入方案
│
├── 4.2.1  接入挑战：Conflux eSpace 与标准 Ethereum L1 的五类兼容性差异
│          C1. 区块哈希算法不兼容（最普遍，贯穿两套框架）
│          C2. EVM 执行层行为差异（gas 计算）
│          C3. L1 区块生产速率差异（影响 L2 出块连续性）
│          C4. 交易类型与 Gas 机制限制（EIP-4844 缺失）
│          C5. CDK 架构外部依赖缺失（Agglayer）
│
├── 4.2.2  总体适配方案设计
│          · 问题-方案映射总览
│          · 区块哈希问题的双层方案论证（代理层 + 内核降级）
│          · 其余四类问题的独立方案概述
│
├── 4.2.3  RPC 代理层：jsonrpc-proxy 设计与实现
│          （专门解决 C1 的 RPC 侧 + RPC API 兼容性）
│
├── 4.2.4  OP Stack 接入适配
│          A. 区块哈希校验降级（C1 的内核侧，6 处）
│          B. L1 数据接入适配（C3 L1 origin 追赶 + C4 calldata 强制）
│          C. EVM 执行层适配（C2：FloorDataGas + checkMinGas 合约修改）
│          D. 运行稳定性修复（blobFee 空值 + GameAlreadyExists）
│
└── 4.2.5  CDK zkEVM 接入适配
           A. 架构依赖适配（C5：Agglayer 关闭 + SettlementBackend 切换）
           B. 区块哈希同步适配（C1 的内核侧，evmdownloader）
           C. 运行稳定性修复（ethtx-manager 死循环 + 部署脚本）
```

**节间逻辑链**：
- 4.2.1 完整枚举五类根因，是后续所有适配工作的起点
- 4.2.2 建立问题-方案的总体对应关系，给 4.2.3/4.2.4/4.2.5 各自定位
- 4.2.3 是五类问题中 C1 的 RPC 层解法（公共基础层）
- 4.2.4 是 C1–C4 在 OP Stack 框架内的内核层解法
- 4.2.5 是 C1、C5 在 CDK 框架内的解法

---

## 三、各节详细规格

---

### 4.2.1 接入挑战：Conflux eSpace 与标准 Ethereum L1 的五类兼容性差异

**本节目标**：在任何解决方案出现之前，让读者建立完整的问题地图——理解"为什么接入 Conflux eSpace 作为 L1 需要如此广泛的适配工作"，以及各类问题的严重程度和影响范围。

**核心论点**：Conflux eSpace 提供 Ethereum 兼容的 RPC 接口，但在区块哈希算法、EVM 执行行为、网络特性和上层服务架构四个维度上存在实质性差异，这些差异分别引发了不同层次的适配需求，且相互独立——解决任何一类都不能消除其余类的影响。

**需要写出来的内容**：

#### C1：区块哈希算法不兼容（最普遍）

约 300 字。

技术本质：Conflux eSpace 的区块头包含 Tree-Graph 共识专有字段（如 `espaceGasLimit`），不在以太坊 EIP-3675 定义的标准结构中。Ethereum 客户端本地重算哈希时只处理标准字段，结果与 Conflux 节点计算的哈希不同。这一差异是结构性的、必然的。

影响面（分框架枚举，需列具体代码位置和失败后果）：

*OP Stack*：
- `op-service/sources/types.go`：获取区块后本地重算哈希，失败使 op-node 无法处理该区块
- `op-service/sources/receipts.go`：验证收据根，失败导致 L2 区块派生中断
- `op-node/rollup/derive/attributes.go`（2 处）、`check_l1.go`（2 处）、`l1_traversal.go`（1 处）、`sequencer.go`（1 处）：L1 origin 连续性校验，失败触发 ResetError，L2 停止产块

*CDK*：
- `sync/evmdownloader.go`：事件日志的 `blockHash` 与查询到的区块 `hash` 不一致，L1 事件同步中断

#### C2：EVM 执行层行为差异

约 200 字，说明两个独立的 EVM 行为差异：

*FloorDataGas 计算偏差*：op-batcher 在提交 calldata batch 时，通过 op-geth 的 `FloorDataGas` 逻辑估算 gas 上限。Conflux 对 calldata 字节的 gas 计价与 EIP-7623 标准存在偏差（eSpace 的 align-evm 问题），导致估算值系统性低于链上实际消耗，batch 交易因 gas 不足被拒绝。

*checkMinGas 汇编不兼容*：`OptimismPortal2` 合约的 `checkMinGas` 函数使用内联汇编计算 calldata gas 消耗，用于确保提现调用时目标合约的 gas 充足。该汇编依赖以太坊的特定 gas 规则，在 Conflux EVM 中行为不同，导致提现交易的 gas 估算结果始终低于实际需求，`finalizeWithdrawalTransaction` 调用失败。

#### C3：L1 区块生产速率差异

约 200 字。

问题根源：OP Stack 的 `L1Traversal` 组件每次 L2 出块只将 L1 origin 递增 1，隐含假设是 L1 与 L2 产块频率大致匹配。Conflux eSpace 产块速率高于此假设时，L2 引用的 L1 origin 与真实 L1 头部差距随时间线性扩大。当差距超过 `maxSequencerDrift`（Fjord 分叉后固定为 1800 秒，不可配置），sequencer 拒绝产块，所有 L2 交易（含 L1→L2 deposit）全部阻塞。

说明这是 OP Stack 专有问题：CDK 的 sequencer 机制不依赖相同的 L1 origin 追踪逻辑，不受此影响。

#### C4：交易类型限制（EIP-4844 缺失）

约 100 字。

OP Stack 默认以 EIP-4844 blob 交易向 L1 提交 batch。Conflux eSpace 未实现 EIP-4844，`eth_feeHistory` 响应中无 `blobFee` 字段，op-batcher 在尝试构造 blob 交易时因 nil pointer 崩溃。此问题独立于区块哈希问题，即使 C1 全部解决，op-batcher 仍无法正常运行。

#### C5：CDK 架构外部依赖缺失

约 150 字。

CDK 的 `cdk-node` 在默认配置下依赖 Agglayer 聚合服务：aggregator 将 ZK 证明提交给 Agglayer 而非直接发到 L1，由 Agglayer 将多链证明聚合为悲观证明（Pessimistic Proof）后统一结算。Conflux eSpace 环境未部署 Agglayer，导致证明永远无法最终提交，`Last Verified Batch Number` 停止更新，L2 状态无法最终确认。这是 CDK 独有的架构依赖问题，与上述四类 EVM/网络层面的差异性质不同。

**衔接语**：五类问题影响层次不同，解决路径也不同——C1 需要 RPC 与内核的双层配合，C2 需要代码与合约层修改，C3 需要配置与算法共同解决，C4 是配置选项切换，C5 是架构依赖的绕过。下节统一梳理各类问题的方案选择。

---

### 4.2.2 总体适配方案设计

**本节目标**：在进入各个具体实现之前，建立五类问题与对应方案的完整映射关系，让读者理解整体适配架构，同时对最复杂的 C1 问题深入论证双层方案的必要性。

**核心论点**：五类问题的解法相互独立，各自针对不同层次；其中 C1（区块哈希）的解法最为复杂，需要代理层与内核层协同工作，其设计理由需要单独论证。

**需要写出来的内容**：

1. **问题-方案总览（表格，约 150 字）**

   | 问题类别 | 根因层次 | 适配方案 | 实施位置 |
   |---------|---------|---------|---------|
   | C1 区块哈希不兼容 | RPC 返回值 + 客户端内核校验 | jsonrpc-proxy 修正哈希（代理层）+ 校验点降级（内核层） | jsonrpc-proxy、op-node、cdk-node |
   | C2 EVM 执行差异 | op-geth gas 估算 + 合约汇编 | FloorDataGas 翻倍（op-geth fork）+ 删除 checkMinGas（合约 fork） | op-geth、OptimismPortal2 合约 |
   | C3 产块速率差异 | op-node L1 遍历算法 | 出块时间配置 1s + op-node 追赶机制 | 配置文件、op-node |
   | C4 交易类型限制 | op-batcher 默认配置 | 强制 calldata 模式 + blobFee nil 防护 | op-batcher 启动参数、estimator.go |
   | C5 架构依赖缺失 | cdk-node 证明提交路径 | Agglayer 关闭 + SettlementBackend 改为 l1 | kurtosis-cdk 配置、cdk-node 配置 |

2. **C1 双层方案必要性论证（核心论证，约 400 字）**

   三种备选方案对比：

   | 方案 | 思路 | 覆盖范围 | 不能覆盖的场景 |
   |------|------|---------|--------------|
   | 修改 Conflux 节点 | 让节点直接返回 Ethereum 标准哈希 | 全部 | 需改主链，对测试网/主网不可行 |
   | 纯 RPC 代理层 | 拦截 RPC 响应修正 `hash` 字段 | RPC 新拉取数据时的哈希 | 客户端内部对历史缓存数据做的跨区块哈希比对（不经过新的 RPC 调用） |
   | 纯内核修改 | 各客户端中跳过全部哈希校验 | 全部 | 完全放弃 L1 完整性验证，安全代价过高 |
   | **代理层 + 选择性内核降级（本方案）** | 代理修正 RPC 返回值；内核对无法被代理覆盖的校验点做最小化降级 | 全部 | — |

   选择理由：op-node 推导管线中有 6 处哈希校验使用内存里已有的 L1 区块引用（非新 RPC 调用），代理层无法拦截；对这 6 处采用"降级为告警"而非"彻底删除"，保留了部分容错逻辑，最小化安全代价。

3. **总体架构示意（配图，约 100 字说明）**

   ```
   ┌─────────────────────────────────────┐
   │  OP Stack 客户端 / CDK 客户端        │
   │  内核适配层：                        │
   │  · C1 校验点降级（op-node 6处/cdk 1处）│
   │  · C2 FloorDataGas 翻倍 (op-geth)  │
   │  · C3 L1 origin 追赶 (op-node)     │
   │  · C4 calldata 强制 + blobFee 防护  │
   │  · C5 SettlementBackend=l1 (cdk)   │
   └──────────────┬──────────────────────┘
                  │ RPC 请求
                  ▼
   ┌─────────────────────────────────────┐
   │  jsonrpc-proxy（代理层，解决 C1 RPC侧）│
   │  · 区块哈希修正（RLP 重算）          │
   │  · hash→number 参数转换             │
   │  · SQLite 持久化缓存                │
   │  · batch RPC 支持                  │
   └──────────────┬──────────────────────┘
                  │
                  ▼
        Conflux eSpace（L1）
   ```

---

### 4.2.3 RPC 代理层：jsonrpc-proxy 设计与实现

**本节目标**：深入论述代理层的四个核心机制，以及从正确性原型到生产可用组件的工程迭代过程。

**核心论点**：代理层以区块哈希修正为核心，围绕哈希的"存储（SQLite）、修正（RLP 重算）、查询（双向映射）、透传（batch 支持）"四个问题形成完整解法。

**需要写出来的内容**：

1. **区块哈希修正机制（约 250 字）**

   触发条件：代理拦截所有返回区块数据的 RPC 方法（`eth_getBlockByHash`、`eth_getBlockByNumber` 等）。

   重算过程：从 Conflux 响应中提取 15 个标准 Ethereum 区块头字段（`parentHash`、`sha3Uncles`、`miner`、`stateRoot`、`transactionsRoot`、`receiptsRoot`、`logsBloom`、`difficulty`、`number`、`gasLimit`、`gasUsed`、`timestamp`、`extraData`、`mixHash`、`nonce`），按以太坊标准做 RLP 编码，取 Keccak-256，用结果替换响应中的 `hash` 字段。

   关键约束：只替换 `hash` 字段，Conflux 专有字段（如 `espaceGasLimit`）保持原始值，业务语义不变。

   双向查询支持：同时维护 cfx hash → eth hash 的反向映射。op-challenger 在创建 DisputeGame 时会将当时的 L1 block hash（cfx 原生哈希）写入合约，resolve 阶段再以该 cfx hash 发起 `eth_getBlockByHash` 查询，因此代理必须同时支持以 cfx hash 和 eth hash 定位同一区块。

2. **RPC 参数兼容性转换（约 150 字）**

   部分 Conflux RPC 方法不支持以区块哈希作为参数（如 `eth_getBalance`、`eth_getCode`、`eth_getBlockReceipts`），代理在转发前将请求中的 block hash 参数替换为对应的 block number，查询索引由 SQLite 提供。

   两类处理分工：哈希修正解决"返回值的 hash 字段错误"，参数转换解决"Conflux 不接受 hash 类型参数"。两个问题独立，但共享同一套 SQLite 索引。

3. **SQLite 持久化缓存（约 200 字，论述性能演进）**

   初始实现使用内存映射。将 L2 出块时间压缩为 1 秒后（为解决 C3 问题），代理收到请求频率大幅提升，每次无缓存命中都需要重算哈希并查询 Conflux 节点，RPC 响应延迟超过 L2 出块间隔，L2 出块出现积压——proxybecame the bottleneck。

   迁移到 SQLite 后，已计算的 hash 映射落盘持久化，重启后无需重建，高频重复查询直接命中索引，出块延迟恢复正常。此次迁移是 jsonrpc-proxy 从"可用"升级为"可生产"的关键工程节点，说明了 C1 和 C3 两类问题的解法在运行时存在依赖关系。

4. **batch RPC 支持（约 100 字）**

   op-challenger 以 JSON-RPC batch 格式发送请求（单次 HTTP 请求含多条 JSON-RPC 调用）。代理初始只处理单请求，导致 op-challenger 的所有调用失败，争议游戏无法解析和提交。适配后对 batch 中每条子请求独立处理，结果汇聚后统一返回。

---

### 4.2.4 OP Stack 接入适配

**本节目标**：按问题类别论述 OP Stack 各组件的内核级改动，每类改动直接对应 4.2.1 中的问题编号。

**核心论点**：OP Stack 涉及 C1–C4 四类问题的适配，其中 C2（EVM 差异）对应的两处改动（FloorDataGas、checkMinGas）各自修改于不同层次（执行引擎与合约），共同保障了 batch 提交和跨链提现两条核心路径的正确性。

**A. 区块哈希校验降级（对应 C1 内核侧）**

约 250 字。

代理层修正了 RPC 返回值中的哈希，但 op-node 内部 6 处哈希校验使用内存中的历史缓存数据，不经过新的 RPC 调用，无法被代理覆盖：

- `attributes.go`（2 处）：构造 L2 区块属性时检查 L1 origin 父子关系
- `check_l1.go`（2 处）：验证 L1 canonical 链的连续性
- `l1_traversal.go`（1 处）：推进 L1 遍历时检测 reorg
- `sequencer.go`（1 处）：sequencer 启动新区块前校验 L1 origin 一致性

适配策略：将 `return ResetError(...)` 或 `d.emitter.Emit(rollup.ResetEvent{...})` 统一改为 `log.Warn(...)`，不触发系统级重置。

设计权衡：削弱了对 L1 reorg 的即时检测能力，但在 Conflux eSpace 上这些检查原本就会因哈希不兼容而大量误报，而 Conflux Tree-Graph 共识本身提供了比 PoW 链更强的 reorg 抵抗性，降级处理的安全代价在当前场景下是可接受的。

**B. L1 数据接入适配（对应 C3 + C4）**

*L1 origin 追赶机制（C3，约 300 字）*

问题已在 4.2.1 C3 定义。这里论述解决方案。

解决策略包含两个相互配合的部分：
1. **配置层**：将 L1 和 L2 出块时间均设为 1 秒（`seconds_per_slot: 1`），缩小产块频率差距，减少 origin 滞后的增长速率
2. **代码层**：在 op-node 中增加 L1 origin 追赶逻辑（commit `b3965f416`）：当检测到 L2 的 L1 origin 落后 L1 实际区块超过 30 秒时，允许一次性跨越多个 L1 区块更新 origin，而不是严格按 +1 递增

两部分缺一不可：仅调配置，高频率下 origin 滞后仍会因任何短暂延迟而累积；仅加追赶代码，若 L1 始终比 L2 快很多则追赶无法收敛。

设计代价：追赶机制在跨越多个 L1 区块时，中间区块内的 L1→L2 deposit 事件是否被完整处理需要明确说明（写作时核查 commit `b3965f416` 具体实现，据实描述）。

*calldata 强制模式（C4，约 150 字）*

问题已在 4.2.1 C4 定义。这里论述方案选择。

方案一：填充 `blobFee = 1` 避免崩溃，但 op-batcher 仍尝试发送 blob 交易，因 Conflux 不支持而失败。

方案二：启动参数 `--data-availability-type=calldata`，强制切换到 calldata 模式，不依赖 blob gas market。

选择方案二。代价是 calldata 模式每条批次的 L1 gas 消耗高于 blob，但在当前测试规模下可接受；更根本的原因是方案一只是延后了错误，不能真正解决问题。

**C. EVM 执行层适配（对应 C2）**

*FloorDataGas 翻倍（约 100 字）*

问题已在 4.2.1 C2 定义（FloorDataGas 计算偏差）。在 op-geth fork 中将 `FloorDataGas` 计算结果乘以 2 作为安全余量，使估算值系统性高于实际消耗，避免 batch 交易因 gas 不足被拒。

注：Conflux 在 2025-05-21 修复了 align-evm 问题，该修改可在升级后撤销；在此之前属于必要的临时适配。

*checkMinGas 合约修改（约 200 字）*

问题已在 4.2.1 C2 定义（checkMinGas 汇编不兼容）。解决方案为 fork OP Stack 合约代码（分支 `remove-checkgas-d44bbea24`），在 `OptimismPortal2` 中删除 `checkMinGas` 调用，重新编译后通过脚本（`op-work/republish-contracts.sh`）打包上传，kurtosis 部署时指向该定制合约版本。

说明影响范围：`checkMinGas` 原本防止提现目标调用因 gas 不足静默失败（注意：这不等于提现失败，提现本身仍会成功，只是目标调用不执行）。去掉后调用方需自行保证 gas 充足。当前演示环境可接受此代价。

*提现等待时间配置（约 150 字）*

OP Stack 默认提现等待超过 10 天（dispute game 7 天 + proofMaturity 3.5 天），演示环境无法接受。通过部署时的 `globalDeployOverrides` 将相关参数压缩至秒级：`faultGameMaxClockDuration`、`faultGameClockExtension`、`preimageOracleChallengePeriod`、`proofMaturityDelaySeconds`、`faultGameWithdrawalDelay`。

约束关系需说明：合约构造时强制检查 `max(clockExtension×2, clockExtension+challengePeriod) ≤ maxClockDuration`，三个参数必须同时满足该不等式，否则部署失败。这不是简单的"改小就行"，参数之间存在硬性约束。

**D. 运行稳定性修复**

*blobFee 空值防护（约 80 字）*

即使已切换 calldata 模式，op-batcher 的 metrics 路径仍访问 `blobFee` 字段（`RecordBlobBaseFee`），Conflux `eth_feeHistory` 不返回此字段，导致 nil pointer 崩溃。在 `op-service/txmgr/estimator.go` 增加 nil 检查，`blobFee` 为 nil 时赋值 1，仅防止 panic，不影响交易路径。

*op-proposer GameAlreadyExists 死循环（约 150 字）*

系统运行约 2 天后 op-proposer 陷入永久失败循环，日志显示 `GameAlreadyExists`。根本原因：超过 PollInterval 后，"查询最新游戏"逻辑不再返回已超时游戏的信息，上层误判为"无游戏"，重复创建同一输出根的游戏，合约因已存在而 revert，循环往复。

修复（commit `39e0f007`）：正确处理超出截止时间的游戏状态查询，返回完整信息，避免误判。

---

### 4.2.5 CDK zkEVM 接入适配

**本节目标**：论述 CDK 框架针对 C1 和 C5 两类问题的适配，以及 ZK 证明提交架构特有的稳定性问题。

**核心论点**：CDK 的适配点比 OP Stack 少但更集中，C1 的哈希问题只影响一处（evmdownloader），C5 的架构依赖问题决定了证明提交路径的选择，两者叠加后的 ZK 证明提交稳定性由 ethtx-manager 的替换来保障。

**A. 架构依赖适配（对应 C5）**

*Agglayer 关闭与 SettlementBackend 切换（约 200 字）*

问题已在 4.2.1 C5 定义。适配两步：
1. kurtosis-cdk 关闭 Agglayer 部署（`deploy_agglayer: false`）
2. cdk-node 的 `SettlementBackend` 由 `agglayer` 改为 `l1`，aggregator 直接向 `PolygonRollupManager` 合约提交证明

技术含义：`l1` 模式下每条 L2 证明独立提交，放弃了多链证明聚合为悲观证明（Pessimistic Proof）的能力，换取对外部 Agglayer 服务的零依赖。当 Conflux 主网部署 Agglayer 后，可通过切回 `agglayer` 模式恢复聚合能力。

**B. 区块哈希同步适配（对应 C1 内核侧）**

*evmdownloader hash 覆盖（约 200 字）*

`cdk-node` 的 `sync/evmdownloader.go` 在拉取 L1 事件日志后，以事件中的 `blockHash` 查询完整区块，然后校验查询结果的 `hash` 字段是否与 `blockHash` 参数一致。

代理层将区块的 `hash` 字段修正为 eth 标准哈希，但事件日志中记录的 `blockHash` 是 Conflux 节点原始写入的 cfx 哈希（事件在 Conflux 区块中产生，其 blockHash 字段由 Conflux 节点填写，不经过代理修正），两者不匹配，校验失败，同步中断。

适配策略：在校验前用事件的 `blockHash` 直接覆盖区块数据中的 `Hash` 字段（`b.Hash = l.BlockHash`），统一两者来源。

与 OP Stack 策略对比：OP Stack 是"保留校验逻辑，降级错误"，CDK 是"统一数据来源，消除不一致"。CDK 此处的哈希问题来源单一（仅 evmdownloader 一处），采用覆盖策略更简洁直接。

**C. 运行稳定性修复**

*zkevm-ethtx-manager 死循环修复（约 200 字）*

`cdk-node` aggregator 通过 `zkevm-ethtx-manager` 管理 L1 上的证明提交交易。当 L1 交易因合约状态问题 revert 时（如 gas 误差、合约临时不可用），原版库进入无限重试循环，aggregator 永久阻塞，`Last Verified Batch Number` 停止更新。测试中观察到一次 revert 可导致系统数小时不可恢复，需手动重启。

解决方案：通过 `go.mod` 的 `replace` 指令将依赖替换为 fork 版本（`pana/zkevm-ethtx-manager`）。该 fork 对 revert 结果有明确的失败终止逻辑，失败后上报错误并退出重试，由上层决定是否重新提交。上层代码无改动。

说明这里存在的根本矛盾：ethtx-manager 的无限重试本是为了处理网络抖动等临时错误，但当错误是合约 revert（永久性失败）时，重试没有意义且会阻塞整条流水线。fork 的本质是区分了"临时错误应重试"和"确定失败应终止"两类场景。

*合约部署脚本 exit code 适配（约 100 字）*

kurtosis-cdk 的 Starlark 脚本通过 `plan.exec` 调用 shell 脚本部署 L1 合约，原始方式无法正确捕获 shell exit code，脚本失败时 kurtosis 不中止流程，在错误状态下继续启动后续服务，问题延迟暴露。改为通过 `bash -c` 包装执行，确保 exit code 正确传播。

---

## 四、各节篇幅建议

| 节 | 子节 | 建议字数 | 权重说明 |
|----|------|---------|---------|
| 4.2.1 | C1–C5 五类问题 | 1000–1200 字 | 奠定全节论证基础，必须全面 |
| 4.2.2 | 总览表 + C1 双层论证 + 架构图 | 700–900 字 | 核心设计判断力所在 |
| 4.2.3 | 哈希修正+参数转换+SQLite+batch | 700–900 字 | 公共基础层，原创贡献高 |
| 4.2.4 | A: C1 校验降级 | 350–400 字 | 有 4.2.2 铺垫，不重复论证 |
|        | B: C3 追赶+C4 calldata | 500–600 字 | L1 origin 追赶是重点 |
|        | C: C2 FloorDataGas+checkMinGas+提现时间 | 450–550 字 | checkMinGas 是原创贡献 |
|        | D: 稳定性修复 | 250–300 字 | 简洁描述即可 |
| 4.2.5 | A: C5 Agglayer | 300–350 字 | |
|        | B: C1 evmdownloader | 250–300 字 | |
|        | C: ethtx-manager+脚本 | 300–350 字 | ethtx-manager 是重点 |
| **全节合计** | | **约 5800–6900 字** | |

---

## 五、需要补充的数据与素材

| 类别 | 所需内容 | 用在哪节 |
|------|---------|---------|
| 性能数据 | SQLite 缓存前后 RPC 响应延迟对比（如有测量） | 4.2.3 SQLite 部分 |
| 性能数据 | L1 origin 追赶机制前后 safe/unsafe 差距数据（如日志截图） | 4.2.4-B |
| 技术细节 | 追赶机制触发阈值（>30s）的来源依据 | 4.2.4-B |
| 技术细节 | 追赶时是否逐块扫描 deposit（核查 commit b3965f416） | 4.2.4-B |
| 技术细节 | checkMinGas 原始汇编代码及 Conflux EVM 具体不兼容点 | 4.2.4-C |
| 数据 | 提现时间参数压缩后实测完整提现流程耗时 | 4.2.4-C |
| 架构图 | 4.2.2 中的总体适配架构图（正式绘制，配图说明） | 4.2.2 |

---

## 六、写作质量自查清单（写完初稿后对照）

- [ ] 4.2.1 五类问题之间有明确的"为什么相互独立"说明，不是简单罗列
- [ ] 4.2.1 C1 的影响面枚举包含具体代码位置和失败后果
- [ ] 4.2.1 C3 说明了 `maxSequencerDrift` 的 1800 秒上限在 Fjord 后不可配置这一关键约束
- [ ] 4.2.2 的问题-方案总览表填写了"实施位置"列，不留空
- [ ] 4.2.2 的 C1 双层方案论证填写了"不能覆盖的场景"，不留空
- [ ] 4.2.4-B 的 L1 origin 追赶说明了两部分（配置+代码）缺一不可的原因
- [ ] 4.2.4-B 的 L1 origin 追赶说明了追赶时对 deposit 事件处理的实际情况
- [ ] 4.2.4-C 的 checkMinGas 说明了去掉检查对用户操作的影响
- [ ] 4.2.4-C 的提现时间参数说明了参数间约束关系
- [ ] 4.2.5-A 明确说明放弃了聚合能力，以及未来可恢复的条件
- [ ] 4.2.5-C 的 ethtx-manager 说明了"临时错误/确定失败"的区分是修复的本质
- [ ] 全节每个解决方案都在 4.2.1 中有对应的问题编号（C1–C5）
- [ ] 全节无"这种设计不仅……还……"类型的尾巴句
- [ ] 全节无"综合考虑后选择"类型的空洞论证
- [ ] 原创工作篇幅占全节 80% 以上
