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

**本节职责**：论证 OP Stack（乐观 Rollup）和 CDK zkEVM（ZK Rollup）两种主流 Rollup 框架接入 Conflux eSpace 作为 L1 的技术方案，重点在兼容性适配的设计决策和工程实现，不承担对两种 Rollup 原理的介绍，也不承担部署自动化（4.4 节）的内容。

**读者预设**：同领域评审专家，了解 OP Stack 和 ZK Rollup 的基本架构，但不了解 Conflux eSpace 的内部机制，也不了解本项目的具体改动。

---

## 二、总体结构

```
4.2 Rollup 侧链接入方案
│
├── 4.2.1  接入挑战：Conflux eSpace 与 Ethereum 的区块哈希不兼容性
│
├── 4.2.2  两层适配总体方案设计
│
├── 4.2.3  RPC 代理层：jsonrpc-proxy 设计与实现
│
├── 4.2.4  OP Stack 接入适配
│          A. L1 数据接入适配（calldata 强制模式 + L1 origin 追赶机制）
│          B. 区块哈希校验降级（推导管线 + 数据完整性验证）
│          C. 提现路径适配（checkMinGas 合约修改 + 提现时间配置）
│          D. 运行稳定性修复（GameAlreadyExists + blobFee 空值）
│
└── 4.2.5  CDK zkEVM 接入适配
           A. 架构配置适配（Agglayer 关闭 + SettlementBackend 切换）
           B. 区块哈希同步适配（evmdownloader block hash 覆盖）
           C. 运行稳定性修复（ethtx-manager 死循环 + 合约部署脚本）
```

节间逻辑链：
- 4.2.1 精确定义问题，所有后续改动的存在都源于这里
- 4.2.2 建立双层适配框架，给 4.2.3/4.2.4/4.2.5 各自定位
- 4.2.3 是公共基础层，论述完毕后 4.2.4/4.2.5 各自引用它
- 4.2.4 和 4.2.5 并列但不重复，各自聚焦 Rollup 框架专有的适配

---

## 三、各节详细规格

---

### 4.2.1 接入挑战：Conflux eSpace 与 Ethereum 的区块哈希不兼容性

**本节目标**：让读者在看到任何解决方案之前，先理解问题本身的精确边界，以及为什么这个问题会同时影响两套独立的 Rollup 框架。

**核心论点**：使用 Conflux eSpace 作为 Rollup L1 的根本障碍是区块哈希算法不兼容。Conflux eSpace 提供 Ethereum 兼容的 JSON-RPC 接口，但其区块哈希不按 Ethereum 标准计算（对区块头 RLP 编码后取 Keccak-256），导致任何从 Conflux 获取区块数据后本地重算哈希的操作都会失败。

**需要写出来的内容**：

1. **问题的技术本质（一段，约 200 字）**  
   Conflux eSpace 的区块头包含 Tree-Graph 共识专有字段（如 `espaceGasLimit`），这些字段不在以太坊 EIP-3675 定义的区块头结构中。Ethereum 客户端在做 RLP 编码时只处理标准字段，因此本地重算得到的哈希与 Conflux 节点内部计算的哈希不同。这一差异不是偶发的，而是结构性的——只要 Conflux 区块头的字段集合与 Ethereum 不完全一致，任何依赖本地重算哈希的校验就必然失败。

2. **影响面枚举（分两个 Rollup 框架，用小标题区分）**  

   *OP Stack 受影响点*（需列出具体代码位置，说明"哪里校验、校验什么、失败后什么后果"）：
   - `op-service/sources/types.go`：获取区块后本地重算哈希与 RPC 返回值对比，失败返回 error，导致 op-node 无法处理该区块
   - `op-service/sources/receipts.go`：验证收据根，失败导致 L2 区块派生中断
   - `op-node/rollup/derive/attributes.go`、`check_l1.go`、`l1_traversal.go`、`sequencer.go`：L1 origin 连续性校验（父子区块哈希匹配），失败触发 ResetError，op-node 进入重置流程，L2 停止产块
   - `op-service/txmgr/estimator.go`：`blobFee` 为 nil（Conflux 不支持 EIP-4844）导致 op-batcher panic

   *CDK 受影响点*：
   - `sync/evmdownloader.go`：从 L1 拉取事件后，用事件中的 `blockHash` 查询完整区块，校验两者哈希一致性，失败导致 L1 事件同步中断，`cdk-node` 无法获取新的 L1 状态

3. **次要兼容性问题（一段，简要列出）**  
   - `eth_getLogs` 不支持 `fromBlock=earliest` 参数
   - `eth_getTransactionByBlockHashAndIndex` 行为差异
   - Conflux Gas limit > 1500 万的交易不被打包（EIP-7623 gas 计算与 Conflux 对齐问题）

**衔接语**：问题横跨 RPC 接口和客户端内核两个层次，单一解法无法覆盖全部，由此引出下节的双层适配方案。

---

### 4.2.2 两层适配总体方案设计

**本节目标**：在展示具体实现之前，让读者理解为什么需要两层，以及每层负责什么、不负责什么。

**核心论点**：代理层与内核适配层各自解决对方无法解决的子问题，两者缺一不可。

**需要写出来的内容**：

1. **设计空间展示（表格或对比段落）**  
   列出三种备选方案，逐一分析其覆盖范围和局限：

   | 方案 | 思路 | 覆盖范围 | 不能覆盖的场景 |
   |------|------|----------|--------------|
   | 修改 Conflux 节点 | 让节点直接返回 Ethereum 兼容哈希 | 全部 | 需改主链，不可行 |
   | 纯 RPC 代理层 | 拦截 RPC 响应并修正哈希 | RPC 返回值中的哈希 | 客户端内部用缓存数据做的跨区块哈希对比（不经过新的 RPC 调用） |
   | 纯内核修改 | 在各客户端中跳过所有哈希校验 | 全部 | 完全放弃 L1 完整性验证，安全风险过高 |
   | **代理层 + 选择性内核适配（本方案）** | 代理修正 RPC 返回值；内核只对无法被代理覆盖的校验点做最小化降级 | 全部 | — |

2. **选择理由（一段）**  
   代理层能覆盖"从 RPC 新拉取数据时的哈希"，但 op-node 推导管线存在对历史缓存数据的再次哈希比对（例如检查 L1 origin 的父子关系时，使用的是内存中已有的 L1 区块引用，而非重新发起 RPC），这些路径无法被代理拦截。因此代理层是必要但不充分的；对这些特定检查点，采用"保留逻辑，降级错误级别（从触发系统重置降为记录告警）"的策略，以最小改动保留部分容错能力，同时不因误报导致系统频繁重置。

3. **架构示意（配图或文字描述）**  
   ```
   OP Stack / CDK 客户端
        │  RPC 请求（eth_getBlockByHash 等）
        ▼
   jsonrpc-proxy（代理层）
     · 修正区块哈希
     · 参数转换（hash→number）
     · SQLite 缓存
     · batch RPC 支持
        │  已修正的响应
        ▼
   Conflux eSpace（L1）

   内核适配层（各 Rollup 客户端内部）：
     · 哈希校验点降级（OP Stack 6 处）
     · evmdownloader hash 覆盖（CDK 1 处）
   ```

---

### 4.2.3 RPC 代理层：jsonrpc-proxy 设计与实现

**本节目标**：深入论述代理层的核心技术机制，包括为什么单纯"替换哈希字段"还不够、以及从正确性到生产可用所经历的工程迭代。

**核心论点**：代理层的核心是用 Ethereum 标准算法为 Conflux 区块重新计算哈希，并以此为锚点解决一系列衍生的查询兼容性问题；性能问题驱动了从内存计算到 SQLite 持久化的架构升级。

**需要写出来的内容**：

1. **区块哈希修正机制（一段，约 250 字）**  
   - 触发条件：代理拦截所有返回区块数据的 RPC 方法（`eth_getBlockByHash`、`eth_getBlockByNumber` 等）
   - 重算过程：从 Conflux 响应中提取标准 Ethereum 区块头字段（`parentHash`、`sha3Uncles`、`miner`、`stateRoot`、`transactionsRoot`、`receiptsRoot`、`logsBloom`、`difficulty`、`number`、`gasLimit`、`gasUsed`、`timestamp`、`extraData`、`mixHash`、`nonce`），按 Ethereum 标准做 RLP 编码，取 Keccak-256，用结果替换响应中的 `hash` 字段
   - 关键约束：只替换 `hash` 字段，其他字段（包括 Conflux 专有字段）保持原始值，保证业务语义不变
   - 双向查询支持：`eth_getBlockByHash` 同时维护 cfx hash → eth hash 映射，使 op-challenger 传入 cfx hash 时也能定位到正确区块

2. **RPC 参数兼容性转换（一段）**  
   部分 Conflux RPC 方法不支持以区块哈希为参数（如 `eth_getBalance`、`eth_getCode`、`eth_getBlockReceipts`），代理在转发前将请求中的 block hash 参数替换为对应的 block number。这要求代理维护 eth hash → block number 的查询索引，由 SQLite 提供。
   
   说明两类处理的分工：哈希修正解决"返回值里的 hash 字段不对"，参数转换解决"Conflux 不认识 hash 类型参数"，两类问题互相独立。

3. **SQLite 持久化缓存（一段，论述性能演进）**  
   初始实现为内存映射（每次重启清空），在 L2 出块时间缩短为 1 秒后，代理收到请求的频率大幅提升，内存缓存命中率低，每次需要实时重算 + 查询 Conflux 节点，导致 RPC 响应延迟超过 L2 出块间隔，L2 出块开始积压。
   
   迁移到 SQLite 后，已计算的 hash 映射落盘持久化，重启后无需重建，单次查询延迟从毫秒级降至微秒级，解除了出块延迟的瓶颈。这一改进使 jsonrpc-proxy 从功能正确的"原型工具"升级为能承载持续生产流量的可用组件。

4. **batch RPC 支持（一段）**  
   op-challenger 以 JSON-RPC batch 格式发送请求（单次 HTTP 请求包含多个 JSON-RPC 方法调用）。初始代理只处理单条请求，op-challenger 的调用均以错误响应结束，导致争议游戏无法正常解析和提交。适配后代理支持对 batch 请求中每条子请求独立处理，结果汇聚后统一返回。

---

### 4.2.4 OP Stack 接入适配

**本节目标**：系统论述 OP Stack 各组件中所有针对 Conflux eSpace 的内核级改动，覆盖从能运行到稳定运行的完整路径。

**核心论点**：OP Stack 的适配工作分为四个层次，按顺序解决"能启动→能同步→能提现→能长期运行"四个问题，每个层次都有对应的技术难点和设计决策。

**A. L1 数据接入适配**

*op-batcher 强制 calldata 模式（约 150 字）*  
OP Stack 默认以 EIP-4844 blob 交易向 L1 提交 batch 数据，Conflux eSpace 不支持该交易类型（`blobFee` 字段在 `eth_feeHistory` 响应中缺失，导致 op-batcher 在估算 gas 时访问 nil 指针崩溃）。方案一是填充默认值（`blobFee = 1`）避免崩溃但仍以 blob 方式发送，方案二是在启动参数中设置 `--data-availability-type=calldata` 强制切换为 calldata 模式。
选择方案二，原因：calldata 是 Conflux 已支持的标准交易字段，不依赖 blob gas market 的存在；方案一无法真正发出有效 blob 交易，只是延后暴露错误。代价是 calldata 模式每条批次的 L1 gas 消耗高于 blob，但在当前演示和测试规模下可接受。

*L1 origin 追赶机制（约 300 字）*  
这是影响 L2 基本可用性最关键的一个问题，值得深入论述。

问题根源：op-node 的 `L1Traversal` 组件每次出块只将 L1 origin 递增 1，设计假设是 L1 和 L2 出块频率大致相当。Conflux eSpace 产块速率与 OP Stack 默认配置不对齐时，L2 的 L1 origin 会滞后于真实 L1 头部，差距随时间线性增大。当差距超过 `maxSequencerDrift`（1800 秒的固定常量，Fjord 分叉后不可配置），sequencer 拒绝出块，所有 L2 交易（包括 L1→L2 跨链交易）全部阻塞。

解决策略包含两部分：
1. **配置层**：将 L1 和 L2 出块时间均设为 1 秒，缩小产块频率差距（`seconds_per_slot: 1`）
2. **代码层**：在 op-node 中增加 L1 origin 追赶逻辑（commit `b3965f416`）：当检测到 L2 的 L1 origin 落后 L1 实际区块超过 30 秒时，允许一次性跨越多个 L1 区块更新 origin，而不是严格按 +1 递增。

说明代价：追赶机制加快了 L1 origin 的更新速度，但跨越多个 L1 区块时，中间区块内的 L1→L2 deposit 事件是否被完整处理需要明确说明——若当前实现在追赶时仍逐块扫描 deposit，则不遗漏；若跳过了中间区块的扫描，则存在 deposit 丢失风险。写作时应核查 commit `b3965f416` 的具体实现，据实描述。

**B. 区块哈希校验降级**

（约 250 字，沿用 4.2.2 中的论证，此处聚焦实现细节）

代理层修正了 RPC 返回值中的哈希，但 op-node 内部有 6 处哈希一致性校验使用的是内存中的历史缓存数据，不经过新的 RPC 调用：

- `attributes.go`（2 处）：构造 L2 区块属性时检查 L1 origin 父子关系
- `check_l1.go`（2 处）：验证 L1 canonical 链的连续性
- `l1_traversal.go`（1 处）：推进 L1 遍历时检测 reorg
- `sequencer.go`（1 处）：sequencer 启动新区块前校验 L1 origin 一致性

所有 6 处的适配策略统一：将 `return ResetError(...)` 或 `d.emitter.Emit(rollup.ResetEvent{...})` 改为 `log.Warn(...)`，不触发系统级重置。

设计权衡：这削弱了对 L1 reorg 的即时检测能力。在 Ethereum 主网上，这些检查保护系统免于在 L1 发生浅层 reorg 时产生基于错误 L1 历史的 L2 区块；在 Conflux eSpace 上，由于哈希不兼容，这些检查会产生大量误报，而 Conflux 自身的 Tree-Graph 共识也提供了比 Ethereum 更强的 reorg 抵抗性，降级处理的安全代价在当前场景下是可接受的。

**C. 提现路径适配**

*checkMinGas 合约修改（约 200 字）*  
L2→L1 提现的最后一步 `finalizeWithdrawalTransaction` 在调用时 gas 估算始终低于实际消耗，交易因 out-of-gas 失败。根因定位到 `OptimismPortal2` 合约中的 `checkMinGas` 函数，该函数使用内联汇编检查 calldata 的 gas 消耗，其行为依赖特定的 EVM gas 计算规则，而 Conflux EVM 在这一规则上与标准 Ethereum 不一致。

解决方案：fork OP Stack 合约代码（分支 `remove-checkgas-d44bbea24`），在 `OptimismPortal2` 中删除 `checkMinGas` 调用，重新编译并通过脚本（`op-work/republish-contracts.sh`）打包上传，在 kurtosis 部署时指向该定制版合约。

说明这一修改的影响范围：`checkMinGas` 的作用是防止提现时目标合约因 gas 不足执行失败（这不等于提现失败，只是不执行目标调用），去掉后这一检查不再进行，调用方需自行保证 gas 充足。对于当前演示环境，这是可接受的。

*提现等待时间缩短（约 150 字）*  
OP Stack 默认的 dispute game 生命周期为 7 天（`faultGameMaxClockDuration`），提现还需额外等待 `proofMaturityDelaySeconds`（3.5 天），总等待超过 10 天。演示环境需要在分钟级内完成跨链流程。

修改通过部署时的 `globalDeployOverrides` 配置实现，将以下参数压缩至秒级：`faultGameMaxClockDuration`、`faultGameClockExtension`、`preimageOracleChallengePeriod`、`proofMaturityDelaySeconds`、`faultGameWithdrawalDelay`。

需要说明参数之间的约束关系：合约构造时检查 `maxClockExtension ≤ maxClockDuration`，而 `maxClockExtension = max(clockExtension×2, clockExtension+challengePeriod)`，因此三个参数必须同时满足该不等式，任意一个设置不当都会导致合约部署失败。

**D. 运行稳定性修复**

*op-geth FloorDataGas 适配（约 100 字）*  
op-batcher 以 calldata 模式提交 batch 时，通过 op-geth 的 `FloorDataGas` 逻辑估算 calldata gas。Conflux eSpace 对 calldata 字节的 gas 计算与 EIP-7623 标准存在偏差，导致估算值低于链上实际消耗，交易提交失败。解决方案：在 op-geth fork 中将 `FloorDataGas` 计算结果乘以 2 作为安全余量。注：Conflux 在 2025-05-21 后已修复 align-evm 问题，该修改可在升级后撤销，不影响正确性。

*blobFee 空值防护（约 80 字）*  
即使切换为 calldata 模式，op-batcher 内部仍有 metrics 路径会访问 `blobFee` 字段用于指标记录。Conflux `eth_feeHistory` 不返回 `blobFee`，该字段为 nil，导致 `RecordBlobBaseFee` 中的浮点数转换访问空指针崩溃。在 `op-service/txmgr/estimator.go` 中增加 nil 检查，`blobFee` 为 nil 时赋值为 1，防止 panic 同时不影响交易逻辑。

*op-proposer GameAlreadyExists 修复（约 150 字）*  
系统运行约 2 天后，op-proposer 开始陷入永久失败循环，日志显示 `GameAlreadyExists`。根本原因：op-proposer 每隔固定间隔提交新的 DisputeGame；当提案时间超过 PollInterval 后，op-proposer 中的"查询最新游戏"逻辑不再返回已超时游戏的信息，导致上层误判为"尚无游戏"，重复创建同一输出根的游戏，合约因已存在而 revert。

修复（commit `39e0f007`）：在查询最新 DisputeGame 时，正确处理超出截止时间的游戏状态，返回其完整信息，避免误判为"无游戏"。

---

### 4.2.5 CDK zkEVM 接入适配

**本节目标**：论述 CDK 框架的适配工作，重点说明与 OP Stack 相比适配点更集中、但根因相同、且 CDK 的 ZK 证明架构带来了 OP Stack 没有的特定问题（如 Agglayer 依赖、ethtx-manager 行为）。

**核心论点**：CDK 的适配工作集中在三类问题——架构依赖调整、区块哈希同步一致性、以及 ZK 证明提交的稳定性——每类都有对应的最小化修改方案。

**A. 架构配置适配**

*Agglayer 模块关闭与 SettlementBackend 切换（约 200 字）*  
CDK 默认将 ZK 证明通过 Agglayer 聚合服务提交 L1，`cdk-node` 的 aggregator 组件在提交证明时向 Agglayer 服务而非 L1 合约发送事务。Conflux eSpace 环境中未部署 Agglayer，若不修改则 `Last Verified Batch Number` 永远不更新，L2 状态无法最终确认。

适配包含两步：
1. 在 kurtosis-cdk 配置中关闭 Agglayer 部署（`deploy_agglayer: false`）
2. 修改 cdk-node 的 `SettlementBackend` 配置由 `agglayer` 改为 `l1`，使 aggregator 直接向 L1 合约（`PolygonRollupManager`）提交证明

说明这一修改的技术含义：`l1` 模式下，每条 L2 证明独立提交 L1，无跨链聚合；`agglayer` 模式下，多链证明可以被聚合成悲观证明（Pessimistic Proof）统一结算。当前接入方案放弃了聚合能力，换取了对外部 Agglayer 服务的零依赖。

**B. 区块哈希同步适配**

*evmdownloader hash 覆盖（约 200 字）*  
`cdk-node` 的 `sync/evmdownloader.go` 在拉取 L1 事件日志后，会以事件中的 `blockHash` 为参数查询完整区块，然后校验查询结果的 `hash` 字段与 `blockHash` 参数是否一致。由于代理层将区块的 `hash` 字段修正为 eth 标准哈希，而事件日志中记录的 `blockHash` 是 Conflux 节点原始写入的 cfx 哈希，两者不同，校验失败导致同步中断。

适配策略：在校验前用事件的 `blockHash` 直接覆盖区块数据中的 `Hash` 字段（`b.Hash = l.BlockHash`），以事件侧为准，统一两者来源，绕过不一致性。

与 OP Stack 适配策略的对比：OP Stack 是"保留校验逻辑，降级错误级别"，CDK 是"统一数据来源，消除不一致"，后者更简洁，适用于 CDK 哈希问题来源单一（仅 evmdownloader）的场景。

**C. 运行稳定性修复**

*zkevm-ethtx-manager 死循环修复（约 200 字）*  
`cdk-node` 的 aggregator 在向 L1 提交 ZK 证明时，通过 `zkevm-ethtx-manager` 管理交易生命周期。当 L1 上的证明交易因合约状态问题 revert 时（例如 gas 估算误差、合约临时不可用），原版 `zkevm-ethtx-manager` 进入无限重试循环，aggregator 永久阻塞，整个证明提交流程卡死，`Last Verified Batch Number` 停止更新。在测试中观察到一次 revert 可导致系统在数小时内不可恢复，必须手动重启。

解决方案：将 `go.mod` 中的依赖替换为 fork 版本（`pana/zkevm-ethtx-manager`），该 fork 对 revert 结果有明确的失败终止逻辑，失败后上报错误并退出重试，由上层决策是否重新提交。

技术实现：通过 `go.mod` 的 `replace` 指令替换依赖，上层代码无改动，仅替换依赖包版本。

*合约部署脚本 exit code 适配（约 100 字）*  
kurtosis-cdk 在 Starlark 脚本中通过 `plan.exec` 调用 shell 脚本部署 L1 合约，原始调用方式无法正确捕获 shell exit code，脚本失败时 kurtosis 不中止部署流程，导致在错误状态下继续启动后续服务，问题延迟暴露且难以诊断。

适配：改为通过 `bash -c '脚本内容; exit $?'` 包装执行，确保 shell 脚本的 exit code 被 `plan.exec` 正确接收。

---

## 四、各节篇幅建议

| 节 | 子节 | 建议字数 | 权重说明 |
|----|------|---------|---------|
| 4.2.1 | — | 800–1000 字 | 奠定全文论证基础 |
| 4.2.2 | — | 800–1000 字，含表格+架构图 | 核心设计判断力所在 |
| 4.2.3 | 哈希修正+参数转换+SQLite+batch | 800–1000 字 | 公共基础设施，原创贡献高 |
| 4.2.4 | A: calldata+追赶机制 | 500–700 字 | L1 origin 追赶是重点 |
|        | B: 校验降级 | 400–500 字 | 有 4.2.2 铺垫，不重复论证 |
|        | C: 提现适配 | 400–500 字 | checkMinGas 是原创贡献 |
|        | D: FloorDataGas+blobFee+GameAlreadyExists | 400 字 | 简洁描述即可 |
| 4.2.5 | A: Agglayer+SettlementBackend | 400 字 | |
|        | B: evmdownloader | 300 字 | |
|        | C: ethtx-manager+脚本 | 300 字 | ethtx-manager 是重点 |
| **全节合计** | | **约 5800–6800 字** | |

---

## 五、需要补充的数据与素材

写作过程中，以下信息需要作者补充，当前 spec 中已留空：

| 类别 | 所需内容 | 用在哪节 |
|------|---------|---------|
| 性能数据 | SQLite 缓存前后 RPC 响应延迟对比（如有测量） | 4.2.3 SQLite 部分 |
| 性能数据 | L1 origin 追赶机制前后 L2 出块延迟或 safe/unsafe 差距数据 | 4.2.4-A |
| 技术细节 | op-node 追赶逻辑的具体触发条件（>30s 的依据来源） | 4.2.4-A |
| 技术细节 | checkMinGas 的原始汇编实现及 Conflux EVM 具体不兼容点 | 4.2.4-C |
| 数据 | 提现等待时间压缩后的实测完整提现流程时长 | 4.2.4-C |
| 架构图 | 两层适配总体架构图（建议配一张） | 4.2.2 |

---

## 六、写作质量自查清单（写完初稿后对照）

- [ ] 每节开头有一句说明"本节动机来自上节什么结论"的衔接语
- [ ] 4.2.1 中的影响面枚举包含了具体代码位置和失败后果，不只是列名称
- [ ] 4.2.2 的方案对比表填写了"不能覆盖的场景"一列，不留空
- [ ] 4.2.3 的 SQLite 改进节包含了前后对比的描述（不一定要数据，但要说清楚变化）
- [ ] 4.2.4-A 的 L1 origin 追赶机制说明了追赶的代价（可能遗漏 deposit 事件的边界情况）
- [ ] 4.2.4-B 对 6 处降级改动有分类论述，不是逐一罗列
- [ ] 4.2.4-C 的 checkMinGas 部分说明了去掉该检查对用户的影响
- [ ] 4.2.5-A 明确说明了选择 `l1` 模式相比 `agglayer` 模式放弃了什么能力
- [ ] 全节无"这种设计不仅……还……"类型的尾巴句
- [ ] 全节无"综合考虑后选择"类型的空洞论证
- [ ] 原创工作（各节的具体方案和实现）篇幅占全节 80% 以上
