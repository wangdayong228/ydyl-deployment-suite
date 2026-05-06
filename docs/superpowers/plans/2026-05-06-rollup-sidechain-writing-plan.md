# Rollup 侧链接入方案（4.2 节）写作实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成科技报告第 4.2 节正文约 5800–6900 字，论述 OP Stack 与 CDK zkEVM 接入 Conflux eSpace 作为 L1 的兼容性适配方案。

**Architecture:** 采用"问题根因 → 总体方案 → 分层实现"三段结构：4.2.1 枚举五类根因（C1–C5），4.2.2 建立问题-方案总览并深入论证 C1 双层方案，4.2.3–4.2.5 分别深入各实现层。每节写作前从代码库核实技术事实，确保描述准确。

**Tech Stack:** Markdown 写作；源材料：optimism/（op-node、op-service 子目录）、cdk/ 子模块、op-work/doc/note.md、kurtosis-cdk/work.md；参考规格：docs/superpowers/specs/2026-05-06-rollup-sidechain-integration-spec.md

---

## 文件结构

| 操作 | 路径 | 说明 |
|------|------|------|
| 创建 | `doc-report/4.2-rollup-sidechain-integration.md` | 正文输出文件 |
| 参考 | `docs/superpowers/specs/2026-05-06-rollup-sidechain-integration-spec.md` | 写作规格（各节内容指导）|
| 参考 | `op-work/doc/note.md` | OP Stack 适配笔记，含 issue #6–#18 |
| 参考 | `kurtosis-cdk/work.md` | CDK 适配笔记 |
| 参考 | `optimism/op-node/rollup/derive/attributes.go` | C1 校验降级（2 处）|
| 参考 | `optimism/op-node/rollup/derive/check_l1.go` | C1 校验降级（2 处）|
| 参考 | `optimism/op-node/rollup/derive/l1_traversal.go` | C1 校验降级（1 处）|
| 参考 | `optimism/op-node/rollup/sequencing/sequencer.go` | C1 校验降级（1 处）|
| 参考 | `optimism/op-service/sources/types.go` | C1 本地重算哈希 |
| 参考 | `optimism/op-service/sources/receipts.go` | C1 收据根校验 |
| 参考 | `optimism/op-service/txmgr/estimator.go` | C4 blobFee nil 防护 |
| 参考 | `cdk/sync/evmdownloader.go` | CDK C1 hash 覆盖 |
| 参考 | `cdk/go.mod` | CDK ethtx-manager replace 指令 |

---

### Task 1: 创建输出文件框架

**Files:**
- Create: `doc-report/4.2-rollup-sidechain-integration.md`

- [ ] **Step 1: 创建文件并写入各节标题骨架**

```markdown
## 4.2 Rollup 侧链接入方案

### 4.2.1 接入挑战：Conflux eSpace 与标准 Ethereum L1 的五类兼容性差异

### 4.2.2 总体适配方案设计

### 4.2.3 RPC 代理层：jsonrpc-proxy 设计与实现

### 4.2.4 OP Stack 接入适配

### 4.2.5 CDK zkEVM 接入适配
```

- [ ] **Step 2: Commit**

```bash
git add doc-report/4.2-rollup-sidechain-integration.md
git commit -m "docs: create 4.2 section skeleton"
```

---

### Task 2: 核实 C1 技术事实（区块哈希不兼容）

**Files:**
- Read: `optimism/op-service/sources/types.go`
- Read: `optimism/op-service/sources/receipts.go`
- Read: `optimism/op-node/rollup/derive/attributes.go`
- Read: `optimism/op-node/rollup/derive/check_l1.go`
- Read: `optimism/op-node/rollup/derive/l1_traversal.go`
- Read: `optimism/op-node/rollup/sequencing/sequencer.go`
- Read: `cdk/sync/evmdownloader.go`

- [ ] **Step 1: 读取 OP Stack C1 六处改动，记录每处的原始校验逻辑和失败后果**

对每个文件，找到与 Conflux 适配相关的变更，记录：
- 文件名及简短功能说明
- 原始代码是什么（`return ResetError(...)` 还是 `d.emitter.Emit(rollup.ResetEvent{...})`）
- 降级后改为什么（`log.Warn(...)`）
- 失败时的实际后果（L2 停止产块？L2 区块派生中断？）

`types.go` 核查：确认本地重算哈希的逻辑位置，失败时抛出的错误类型和上层影响。
`receipts.go` 核查：确认收据根校验，失败后是拒绝处理该区块还是其他行为。

- [ ] **Step 2: 读取 CDK evmdownloader.go，记录 hash 覆盖的上下文**

核查：
- 找到 `b.Hash = l.BlockHash` 这行代码的位置
- 确认原始校验逻辑：`if b.Hash != l.BlockHash { ... }` 的错误处理
- 确认修改顺序：是先 `b.Hash = l.BlockHash` 再做后续处理，还是直接跳过校验

- [ ] **Step 3: 整理 C1 技术事实备忘（在本文档末尾的草稿区记录，写作时引用）**

格式：
```
## 写作草稿区（不进入正文）

### C1 OP Stack 六处改动
1. types.go: [功能] / [原始失败后果] / [改动方式]
2. receipts.go: ...
3. attributes.go (第1处): ...
4. attributes.go (第2处): ...
5. check_l1.go (第1处): ...
6. check_l1.go (第2处): ...
7. l1_traversal.go: ...（注：与 sequencer.go 合计 8 处？核实准确数量）
8. sequencer.go: ...

### C1 CDK 一处改动
evmdownloader.go: [原校验逻辑] / [覆盖策略]
```

---

### Task 3: 核实 C2/C3/C4 技术事实

**Files:**
- Read: `op-work/doc/note.md`（重点 issue #6、#7、#10、#15）
- Read: `optimism/op-service/txmgr/estimator.go`（blobFee nil 检查）
- Read: `optimism-package/main.star` 或相关配置（seconds_per_slot 设置）

- [ ] **Step 1: 从 note.md 提取 C2 FloorDataGas 细节（issue #7）**

核查：
- 问题描述：batch 交易因什么具体原因被拒（gas 不足 vs. 其他）
- Conflux 修复日期：是否为 2025-05-21，还是其他日期
- op-geth fork 中的具体改法：是 `×2` 还是其他倍数或固定值

- [ ] **Step 2: 从 note.md 提取 C2 checkMinGas 细节（issue #15）**

核查：
- OptimismPortal2 合约的 fork 分支名是否为 `remove-checkgas-d44bbea24`
- 工程流程：`op-work/republish-contracts.sh` 是否真实存在，做什么
- 失败现象：`finalizeWithdrawalTransaction` 调用失败的具体错误（gas 估算过低）
- 影响说明：去掉 checkMinGas 后，提现目标调用静默失败的场景

- [ ] **Step 3: 从 note.md 提取 C3 L1 origin 追赶细节（issue #10）**

核查：
- maxSequencerDrift 1800 秒上限：确认 Fjord 分叉后不可配置（非参数，硬编码）
- seconds_per_slot=1 的配置位置（optimism-package 的哪个文件哪个字段）
- commit b3965f416 的内容：追赶逻辑的触发阈值是"落后 >30s"还是其他条件
- 追赶时是否逐块扫描 deposit：追赶跨越多个 L1 区块时，中间区块的 L1→L2 deposit 事件是否被完整处理

- [ ] **Step 4: 从 note.md 提取 C4 EIP-4844 细节（issue #6）**

核查：
- 崩溃的具体现象：nil pointer panic 在哪行代码，是否有 stack trace
- 启动参数的确切拼写：`--data-availability-type=calldata`

- [ ] **Step 5: 查看 estimator.go 确认 blobFee nil 防护的代码位置和方式**

找到具体代码行：
```go
if blobFee == nil {
    blobFee = big.NewInt(1)
}
```
确认：
- 这段代码在哪个函数中
- 是否有注释说明这是 Conflux 适配

- [ ] **Step 6: 整理 C2/C3/C4 事实备忘（追加到草稿区）**

---

### Task 4: 核实 C5 技术事实（CDK Agglayer 依赖）

**Files:**
- Read: `kurtosis-cdk/work.md`
- Read: `cdk/go.mod`（zkevm-ethtx-manager replace 指令）
- Read: `kurtosis-cdk/` 中的配置文件（找到 deploy_agglayer: false 的位置）

- [ ] **Step 1: 从 work.md 提取 C5 Agglayer 依赖细节**

核查：
- SettlementBackend 的默认值（agglayer）和修改后的值（l1）
- 关闭 Agglayer 后 Last Verified Batch Number 的变化情况
- Pessimistic Proof 的简要技术含义（聚合多链证明的方式）

- [ ] **Step 2: 从 work.md 提取 ethtx-manager 死循环细节**

核查：
- 具体触发场景：什么操作导致 L1 交易 revert（合约状态问题是什么？）
- 死循环的具体表现（日志特征）
- pana/zkevm-ethtx-manager fork 的具体改法（增加了什么终止条件）
- go.mod 中 replace 指令的原版本号和 fork commit 哈希

- [ ] **Step 3: 确认 deploy_agglayer_contracts.star 的改动内容**

核查：
- 从 `plan.run_sh` 改为 `bash -c` 包装的具体方式
- exit code 不传播的原始问题是否记录在 work.md 或 commit 信息中

- [ ] **Step 4: 整理 C5 事实备忘（追加到草稿区）**

---

### Task 5: 撰写 4.2.1——五类兼容性差异（约 1100 字）

**Files:**
- Modify: `doc-report/4.2-rollup-sidechain-integration.md`

- [ ] **Step 1: 撰写 C1 区块哈希不兼容（约 300 字）**

结构：
```
段落1（约 120 字，技术本质）：
Conflux eSpace 的区块头包含 Tree-Graph 共识专有字段（如 espaceGasLimit），
不在以太坊 EIP-3675 定义的标准区块头结构中。Ethereum 客户端本地重算哈希时
仅处理标准字段，结果与 Conflux 节点计算的哈希不同。这一差异是结构性的，
不因版本更新自动消除。

影响面枚举（约 180 字，每处格式："组件/文件：功能说明，失败后果"）：
OP Stack 框架（共 N 处，填入核实后的准确数量）：
- op-service/sources/types.go：[填入核实内容]
- op-service/sources/receipts.go：[填入核实内容]
- op-node/rollup/derive/attributes.go（2 处）：[填入核实内容]
- op-node/rollup/derive/check_l1.go（2 处）：[填入核实内容]
- op-node/rollup/derive/l1_traversal.go（1 处）：[填入核实内容]
- op-node/rollup/sequencing/sequencer.go（1 处）：[填入核实内容]

CDK 框架（1 处）：
- sync/evmdownloader.go：[填入核实内容]
```

- [ ] **Step 2: 撰写 C2 EVM 执行层行为差异（约 200 字）**

结构：
```
小标题："FloorDataGas 计算偏差"（约 100 字）
- op-batcher 提交 calldata batch 时，通过 op-geth 的 FloorDataGas 逻辑估算 gas 上限
- Conflux eSpace 对 calldata 字节的 gas 计价与 EIP-7623 标准存在偏差（align-evm 问题）
- 导致估算值系统性低于链上实际消耗，batch 交易因 gas 不足被拒绝

小标题："checkMinGas 汇编不兼容"（约 100 字）
- OptimismPortal2 合约的 checkMinGas 函数使用内联汇编计算 calldata gas 消耗
- 用于确保提现调用时目标合约的 gas 充足
- 该汇编依赖以太坊的特定 gas 规则，在 Conflux EVM 中行为不同
- finalizeWithdrawalTransaction 调用时 gas 估算始终低于实际需求，提现失败
```

- [ ] **Step 3: 撰写 C3 L1 区块生产速率差异（约 200 字）**

结构：
```
段落1 问题根源（约 100 字）：
- OP Stack 的 L1Traversal 组件每次 L2 出块将 L1 origin 递增 1
- 隐含假设：L1 与 L2 产块频率大致匹配
- Conflux eSpace 产块速率高于此假设
- L2 引用的 L1 origin 与真实 L1 头部差距随时间线性扩大

段落2 后果（约 60 字）：
- 差距超过 maxSequencerDrift（Fjord 分叉后固定为 1800 秒，不可配置）
- sequencer 拒绝产块
- 所有 L2 交易（含 L1→L2 deposit）全部阻塞

范围说明（约 40 字）：
- 这是 OP Stack 专有问题
- CDK 的 sequencer 机制不依赖相同的 L1 origin 追踪逻辑，不受此影响
```

- [ ] **Step 4: 撰写 C4 交易类型限制（约 100 字）**

结构：
```
- OP Stack 默认以 EIP-4844 blob 交易向 L1 提交 batch
- Conflux eSpace 未实现 EIP-4844，eth_feeHistory 响应中无 blobFee 字段
- op-batcher 构造 blob 交易时因 nil pointer 崩溃（填入核实后的具体位置）
- 明确：此问题独立于 C1，即使 C1 全部解决，op-batcher 仍无法正常运行
```

- [ ] **Step 5: 撰写 C5 CDK 架构外部依赖缺失（约 150 字）**

结构：
```
段落1 CDK 默认依赖（约 70 字）：
- cdk-node 在默认配置下依赖 Agglayer 聚合服务
- aggregator 将 ZK 证明提交给 Agglayer，而非直接发到 L1
- Agglayer 将多链证明聚合为悲观证明（Pessimistic Proof）后统一结算

段落2 Conflux 环境下的影响（约 50 字）：
- Conflux eSpace 环境未部署 Agglayer
- 证明永远无法最终提交，Last Verified Batch Number 停止更新，L2 状态无法最终确认

性质说明（约 30 字）：
- 这是 CDK 独有的架构依赖问题，与 C1–C4 的 EVM/网络层差异性质不同
```

- [ ] **Step 6: 撰写 4.2.1 结尾衔接语（约 60 字）**

```
"五类问题影响层次不同，解决路径也不同——
C1 需要 RPC 与内核的双层配合，
C2 需要代码与合约层修改，
C3 需要配置与算法共同解决，
C4 是配置选项切换，
C5 是架构依赖的绕过。
下节统一梳理各类问题的方案选择。"
```

- [ ] **Step 7: 自查 4.2.1**

- [ ] 五类问题之间有明确的"相互独立"说明，不是简单罗列
- [ ] C1 影响面枚举包含具体代码位置和失败后果
- [ ] C3 说明了 maxSequencerDrift 1800 秒、Fjord 后不可配置（关键约束）
- [ ] C3 说明这是 OP Stack 专有问题（CDK 不受影响）
- [ ] C4 说明了独立性（与 C1 是两个独立问题）
- [ ] C5 的"性质不同"有具体说明，不是空洞断言

- [ ] **Step 8: Commit**

```bash
git add doc-report/4.2-rollup-sidechain-integration.md
git commit -m "docs: complete 4.2.1 five root causes"
```

---

### Task 6: 撰写 4.2.2——总体适配方案设计（约 800 字）

**Files:**
- Modify: `doc-report/4.2-rollup-sidechain-integration.md`

- [ ] **Step 1: 撰写问题-方案总览表（约 150 字）**

```markdown
| 问题类别 | 根因层次 | 适配方案 | 实施位置 |
|---------|---------|---------|---------|
| C1 区块哈希不兼容 | RPC 返回值 + 客户端内核校验 | jsonrpc-proxy 修正哈希（代理层）+ 校验点降级（内核层） | jsonrpc-proxy、op-node、cdk-node |
| C2 EVM 执行差异 | op-geth gas 估算 + 合约汇编 | FloorDataGas 翻倍（op-geth fork）+ 删除 checkMinGas（合约 fork） | op-geth、OptimismPortal2 合约 |
| C3 产块速率差异 | op-node L1 遍历算法 | 出块时间配置 1s + op-node 追赶机制 | 配置文件、op-node |
| C4 交易类型限制 | op-batcher 默认配置 | 强制 calldata 模式 + blobFee nil 防护 | op-batcher 启动参数、estimator.go |
| C5 架构依赖缺失 | cdk-node 证明提交路径 | Agglayer 关闭 + SettlementBackend 改为 l1 | kurtosis-cdk 配置、cdk-node 配置 |
```

表格后加 1-2 句说明：五类问题的解法相互独立，各自针对不同层次；其中 C1 的解法最为复杂，需代理层与内核层协同，下面单独论证。

- [ ] **Step 2: 撰写 C1 双层方案必要性论证（约 400 字）**

结构：
```
引导句（约 30 字）：
"五类问题中，C1（区块哈希不兼容）的解法最为复杂，
需要 RPC 代理层与客户端内核层协同配合。本节论证双层方案的必要性。"

三种备选方案对比表：
| 方案 | 思路 | 覆盖范围 | 不能覆盖的场景 |
|------|------|---------|--------------|
| 修改 Conflux 节点 | 让节点直接返回以太坊标准哈希 | 全部 | 需改主链，对测试网/主网不可行 |
| 纯 RPC 代理层 | 拦截 RPC 响应修正 hash 字段 | RPC 新拉取的数据 | op-node 推导管线内部对内存缓存数据做的跨块哈希比对（不经过新 RPC 调用）|
| 纯内核修改 | 各客户端中跳过全部哈希校验 | 全部 | 完全放弃 L1 完整性验证，安全代价过高 |
| 代理层 + 选择性内核降级（本方案）| 代理修正 RPC 返回值；内核对无法被代理覆盖的校验点做最小化降级 | 全部 | — |

选择论证（约 150 字，三个论点）：
1. 为什么纯代理层不够：
   op-node 推导管线中有 6 处哈希校验使用内存中已有的 L1 区块引用（非新 RPC 调用），
   这些校验发生在数据已进入管线内部后，代理无法拦截其输入。

2. 为什么纯内核修改代价过高：
   这些校验的目的是检测 L1 重组（reorg）——完全删除等于放弃了重组防护。
   "降级为告警"（而非删除）在校验失败时仍输出日志，保留了排查手段。

3. 为什么本方案的安全代价可接受：
   Conflux Tree-Graph 共识本身提供比 PoW 链更强的 reorg 抵抗性，
   且上述校验在 Conflux 环境中原本就因哈希不兼容大量误报，
   降级处理不会引入额外的安全风险。
```

- [ ] **Step 3: 撰写总体适配架构示意图（约 100 字说明）**

插入以下 ASCII 图（从 spec 取用），加说明文字：

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

说明文字（约 100 字）：
"如图所示，适配架构分为两层。代理层（jsonrpc-proxy）位于所有 Rollup 客户端与 Conflux eSpace 之间，集中处理 C1 的 RPC 侧问题——修正区块哈希、转换参数格式，为上层提供符合以太坊规范的 RPC 接口。内核层针对每类框架的专有问题在源代码层面适配，包含 C1 无法被代理覆盖的校验点降级，以及 C2–C5 各自的修改。两层各司其职，代理层改动对上层透明。"

- [ ] **Step 4: 自查 4.2.2**

- [ ] 问题-方案总览表"实施位置"列全部填写，无空白
- [ ] C1 双层方案对比表"不能覆盖的场景"列全部填写
- [ ] 选择论证中说明了为什么"纯代理层"不够（内存缓存 6 处）
- [ ] 架构图说明了两层的分工，不是对图的单纯复述

- [ ] **Step 5: Commit**

```bash
git add doc-report/4.2-rollup-sidechain-integration.md
git commit -m "docs: draft 4.2.2 overall design mapping"
```

---

### Task 7: 撰写 4.2.3——jsonrpc-proxy 设计与实现（约 800 字）

**Files:**
- Read: `op-work/doc/note.md`（issue #11 SQLite 性能，issue #13 batch RPC，issue #14 cfx/eth 双向查询）
- Modify: `doc-report/4.2-rollup-sidechain-integration.md`

- [ ] **Step 1: 核实 jsonrpc-proxy 四个机制的工程细节**

从 note.md 提取：
- issue #11：SQLite 迁移前的具体性能瓶颈（延迟数字？何时触发积压？）
- issue #13：op-challenger 使用 batch RPC 的具体场景（哪个操作、哪类请求）
- issue #14：cfx hash 存入 DisputeGame 合约的时序——创建时写入 cfx hash，resolve 时再以 cfx hash 查询
- 15 个标准以太坊区块头字段的完整列表（核实是否准确）

- [ ] **Step 2: 撰写区块哈希修正机制（约 250 字）**

```
触发条件（约 40 字）：
"代理拦截所有返回区块数据的 RPC 方法（eth_getBlockByHash、eth_getBlockByNumber 等）。"

重算过程（约 100 字）：
"从 Conflux 响应中提取 15 个标准以太坊区块头字段：
parentHash、sha3Uncles、miner、stateRoot、transactionsRoot、receiptsRoot、
logsBloom、difficulty、number、gasLimit、gasUsed、timestamp、extraData、mixHash、nonce，
按以太坊标准做 RLP 编码，取 Keccak-256 哈希，用结果替换响应中的 hash 字段。"

关键约束（约 30 字）：
"仅替换 hash 字段，Conflux 专有字段（如 espaceGasLimit）保持原始值，业务语义不变。"

双向查询必要性（约 80 字）：
"op-challenger 在创建 DisputeGame 时将当时的 L1 block hash（Conflux 原生 cfx 哈希）写入合约；
resolve 阶段再以该 cfx hash 发起 eth_getBlockByHash 查询。
因此代理必须维护 cfx hash → eth hash 的反向映射，
同时支持以 cfx hash 和 eth hash 定位同一区块。"
```

- [ ] **Step 3: 撰写 RPC 参数兼容性转换（约 150 字）**

```
段落1 问题（约 60 字）：
"Conflux 部分 RPC 方法不支持以区块哈希作为参数，如 eth_getBalance、eth_getCode、
eth_getBlockReceipts 均要求 block number 而非 block hash。
Rollup 客户端以 hash 形式发起这些请求时，Conflux 节点返回错误。"

段落2 方案（约 50 字）：
"代理在转发前将请求中的 block hash 参数替换为对应的 block number，
替换依据由 SQLite 的哈希-高度映射索引提供。"

分工说明（约 40 字）：
"哈希修正解决'返回值中 hash 字段错误'，参数转换解决'Conflux 不接受 hash 类型参数'。
两个问题独立存在，但共享同一套 SQLite 索引。"
```

- [ ] **Step 4: 撰写 SQLite 持久化缓存（约 200 字）**

```
初始实现（约 30 字）：
"初始实现使用内存映射存储 hash 计算结果，重启后需从头重建。"

性能问题的触发（约 70 字）：
"将 L2 出块时间压缩为 1 秒后（为解决 C3 问题），
代理收到请求频率大幅提升。每次缓存未命中都需要重算哈希并查询 Conflux 节点，
RPC 响应延迟超过 L2 出块间隔，L2 出块积压，jsonrpc-proxy 成为瓶颈。"

SQLite 迁移效果（约 60 字）：
"迁移到 SQLite 后，已计算的 hash 映射落盘持久化，重启后无需重建；
高频重复查询直接命中索引，出块延迟恢复正常。"

工程意义（约 40 字）：
"这次迁移揭示了 C1 和 C3 两类问题的解法在运行时存在依赖关系——
C3 的 1s 出块配置放大了 C1 代理层的性能需求，
SQLite 是让两者共同可用的工程节点。"
```

- [ ] **Step 5: 撰写 batch RPC 支持（约 100 字）**

```
问题（约 50 字）：
"op-challenger 以 JSON-RPC batch 格式发送请求（单次 HTTP 请求含多条 JSON-RPC 调用）。
初始代理仅处理单请求格式，op-challenger 的所有调用失败，争议游戏无法解析和提交。"

方案（约 50 字）：
"适配后对 batch 中每条子请求独立处理（哈希修正、参数转换等逻辑复用单请求路径），
结果汇聚后统一返回。"
```

- [ ] **Step 6: 自查 4.2.3**

- [ ] 区块哈希修正说明了为何需要双向映射（cfx hash 在 DisputeGame 合约中的存储时序）
- [ ] SQLite 部分说明了 C3 解法（1s 出块）触发了 C1 代理层的性能问题（两类解法的运行时依赖）
- [ ] 每个机制有"为什么需要"的论证，不是纯描述

- [ ] **Step 7: Commit**

```bash
git add doc-report/4.2-rollup-sidechain-integration.md
git commit -m "docs: draft 4.2.3 jsonrpc-proxy"
```

---

### Task 8: 撰写 4.2.4——OP Stack 接入适配（约 1600 字）

**Files:**
- Read: `op-work/doc/note.md`（issue #10、#15、#18；提现参数约束）
- Read: `optimism/op-service/txmgr/estimator.go`（blobFee nil 防护代码）
- Modify: `doc-report/4.2-rollup-sidechain-integration.md`

- [ ] **Step 1: 撰写 A 节——区块哈希校验降级（C1 内核侧，约 350 字）**

```
引导句（约 40 字）：
"4.2.3 的代理层修正了 RPC 返回值中的哈希，但 op-node 推导管线中有 N 处校验
使用内存中已有的 L1 区块引用，不经过新的 RPC 调用，代理无法覆盖。"
（N 填入 Task 2 核实后的准确数量）

六处具体描述（约 150 字，每处一句）：
- attributes.go（第1处）：[从 Task 2 草稿区取用]
- attributes.go（第2处）：[从 Task 2 草稿区取用]
- check_l1.go（第1处）：[从 Task 2 草稿区取用]
- check_l1.go（第2处）：[从 Task 2 草稿区取用]
- l1_traversal.go（1处）：[从 Task 2 草稿区取用]
- sequencer.go（1处）：[从 Task 2 草稿区取用]

适配策略（约 70 字）：
"将上述各处的 return ResetError(...) 或 emit ResetEvent 统一改为 log.Warn(...)，
不触发系统级重置。这一改法保留了异常信号（告警日志），
同时避免了因哈希不兼容导致的误报性重置。"

设计权衡（约 90 字）：
"降级削弱了对 L1 reorg 的即时检测能力。但在 Conflux eSpace 环境中，
这些校验原本就因哈希不兼容而大量误报，无法区分真正的 reorg 和哈希差异。
Conflux 的 Tree-Graph 共识本身提供了比 PoW 链更强的 reorg 抵抗性，
在这一前提下，降级处理的安全代价是可接受的。"
```

- [ ] **Step 2: 撰写 B 节——L1 数据接入适配（C3+C4，约 450 字）**

B-1 L1 origin 追赶机制（C3，约 300 字）：
```
回顾 4.2.1 C3（一句话引用，不重复阐述）

解决策略两部分：

1. 配置层（约 80 字）：
"将 L1 和 L2 出块时间均配置为 1 秒（[填入核实后的配置文件路径和字段名]），
缩小 Conflux 与 OP Stack 之间的产块频率差距，降低 L1 origin 滞后的增长速率。"

2. 代码层（约 150 字）：
"在 op-node 中增加 L1 origin 追赶逻辑（commit b3965f416）：
当 L2 的 L1 origin 落后 L1 实际区块超过 [核实后填入阈值] 时，
允许一次性跨越多个 L1 区块更新 origin，而非严格按 +1 递增。
追赶时，跨越的 L1 区块内的 L1→L2 deposit 事件 [据 Task 3 核实结果填写：
'会逐块扫描确保完整处理' 或 '按跨越范围批量处理' 等]。"

两部分缺一不可（约 70 字）：
"仅调配置：L2 产块频率提高后，任何短暂延迟都会导致 origin 再次积压，
仅靠频率匹配无法保证持续收敛。
仅加追赶代码：若 L1 产块速率始终显著快于 L2，
追赶逻辑频繁触发但间隔不足，L2 仍会阻塞。
两者配合才能在快速产块的同时保持 origin 稳定追赶。"
```

B-2 calldata 强制模式（C4，约 150 字）：
```
回顾 4.2.1 C4（一句话引用）

方案比较：
"方案一：在 estimator.go 中为 nil 的 blobFee 赋值 1，避免崩溃；
但 op-batcher 仍尝试发送 blob 交易，因 Conflux 不支持而失败——仅推迟了错误。
方案二：启动参数 --data-availability-type=calldata，
强制 op-batcher 使用 calldata 模式，完全不依赖 blob gas market。"

选择方案二，理由两点（约 60 字）：
1. 方案一只延后错误，不是真正的解决
2. calldata 模式下每批的 L1 gas 消耗高于 blob，但在当前测试规模下可接受；
   若未来 Conflux 支持 EIP-4844，可平滑切换回 blob 模式
```

- [ ] **Step 3: 撰写 C 节——EVM 执行层适配（C2，约 450 字）**

C-1 FloorDataGas 翻倍（约 100 字）：
```
回顾 4.2.1 C2 中 FloorDataGas 问题（一句话）

方案：
"在 op-geth fork 中将 FloorDataGas 计算结果乘以 [核实倍数，通常为 2]
作为安全余量，使估算值系统性高于实际消耗，避免 batch 交易因 gas 不足被拒。"

时效说明：
"Conflux eSpace 于 [核实后填入确切日期] 修复了 align-evm 问题，
该 fork 改动在升级后可撤销。"
```

C-2 checkMinGas 合约修改（约 200 字）：
```
回顾 4.2.1 C2 中 checkMinGas 问题（一句话）

方案：
"fork OptimismPortal2 合约代码（分支 remove-checkgas-d44bbea24），
在 finalizeWithdrawalTransaction 调用路径上删除 checkMinGas 调用，
重新编译后通过 op-work/republish-contracts.sh 打包上传，
kurtosis 部署时指向该定制合约版本。"

影响说明（约 80 字）：
"checkMinGas 原本防止提现目标调用因 gas 不足而静默失败——
提现本身仍然成功，但目标合约的执行不会发生。
删除该检查后，目标调用的 gas 充足性由调用方自行保证。
在当前演示环境中，提现均由明确知晓 gas 需求的脚本发起，此代价可接受。"
```

C-3 提现等待时间配置（约 150 字）：
```
背景（约 40 字）：
"OP Stack 默认提现等待时间超过 10 天（DisputeGame 挑战期 7 天 + proofMaturity 3.5 天），
演示环境无法接受。"

方案（约 60 字）：
"通过部署时的 globalDeployOverrides 将相关参数压缩至秒级：
faultGameMaxClockDuration、faultGameClockExtension、
preimageOracleChallengePeriod、proofMaturityDelaySeconds、faultGameWithdrawalDelay。"

约束关系（关键，约 50 字）：
"合约构造时强制检查：
max(clockExtension×2, clockExtension + challengePeriod) ≤ maxClockDuration。
三个参数必须同时满足该不等式，否则部署失败。
这不是简单的'改小就行'，参数之间存在硬性约束，需联动调整。"
```

- [ ] **Step 4: 撰写 D 节——运行稳定性修复（约 230 字）**

D-1 blobFee 空值防护（约 80 字）：
```
场景（约 40 字）：
"即使已切换 calldata 模式，op-batcher 的 metrics 路径中
RecordBlobBaseFee 函数仍访问 blobFee 字段。
Conflux eth_feeHistory 响应不包含该字段，nil pointer 崩溃。"

修复（约 40 字）：
"在 op-service/txmgr/estimator.go 的 [具体函数名] 中，
blobFee 为 nil 时赋值 big.NewInt(1)，仅防止 panic，不影响交易提交路径。"
```

D-2 op-proposer GameAlreadyExists 死循环（约 150 字）：
```
现象（约 30 字）：
"系统运行约 2 天后，op-proposer 陷入永久失败循环，
日志持续出现 GameAlreadyExists 错误。"

根本原因（约 70 字）：
"当游戏存在时间超过 PollInterval 后，
'查询最新游戏'的逻辑不再返回该游戏的信息；
op-proposer 误判为'当前无游戏'，
针对同一输出根重复创建新游戏；
合约因该输出根的游戏已存在而 revert，
op-proposer 捕获 revert 后再次查询，循环往复。"

修复（约 50 字）：
"commit 39e0f007：修正超出截止时间的游戏状态查询，
使其返回完整游戏信息，避免 op-proposer 对游戏存在性的误判。"
```

- [ ] **Step 5: 自查 4.2.4**

- [ ] 每个子节以"对应 C1/C2/C3/C4"标注开头或正文中明确提及
- [ ] B 节 L1 origin 追赶说明了"两部分缺一不可"的原因
- [ ] B 节说明了追赶时 deposit 事件的实际处理情况（据核实填写）
- [ ] C 节 checkMinGas 说明了去掉检查对用户操作的影响
- [ ] C 节提现时间参数说明了约束关系（max(...) ≤ maxClockDuration）
- [ ] 无"综合考虑后选择"类型的空洞表达
- [ ] blobFee 防护代码位置已核实并填写（不留"[具体函数名]"占位）

- [ ] **Step 6: Commit**

```bash
git add doc-report/4.2-rollup-sidechain-integration.md
git commit -m "docs: draft 4.2.4 OP Stack adaptation"
```

---

### Task 9: 撰写 4.2.5——CDK zkEVM 接入适配（约 850 字）

**Files:**
- Read: `kurtosis-cdk/work.md`
- Read: `cdk/go.mod`
- Modify: `doc-report/4.2-rollup-sidechain-integration.md`

- [ ] **Step 1: 撰写 A 节——架构依赖适配（C5，约 300 字）**

```
回顾 4.2.1 C5（一句话引用）

适配步骤（约 100 字）：
"适配分两步：
第一步，在 kurtosis-cdk 的 [核实后填入配置文件路径] 中设置 deploy_agglayer: false，
不部署 Agglayer 服务；
第二步，cdk-node 的 [核实后填入配置字段路径] 中将 SettlementBackend 由 agglayer 改为 l1，
aggregator 直接向 PolygonRollupManager 合约提交 ZK 证明，不经过聚合服务。"

技术含义（约 100 字）：
"l1 模式下，每条 L2 批次证明独立提交，放弃了将多链证明聚合为悲观证明
（Pessimistic Proof）的能力——悲观证明由 Agglayer 在跨链安全证明层面提供更强保障。
换取的是对外部 Agglayer 服务的零依赖：证明提交路径完全在 Conflux eSpace L1 内闭合。"

可逆性说明（约 40 字）：
"Conflux 主网部署 Agglayer 后，将 SettlementBackend 切回 agglayer
即可恢复多链证明聚合能力，上层 CDK 代码无需修改。"
```

- [ ] **Step 2: 撰写 B 节——区块哈希同步适配（C1 内核侧，约 250 字）**

```
与 4.2.4-A 的差异（约 30 字）：
"CDK 的 C1 适配与 OP Stack 不同——影响范围仅一处，
且采用了不同的适配策略。"

问题描述（约 100 字）：
"cdk-node 的 sync/evmdownloader.go 在拉取 L1 事件日志后，
以事件中的 blockHash 字段查询完整区块，
随后校验查询结果的 hash 字段是否与 blockHash 一致。

代理层将区块的 hash 字段修正为 eth 标准哈希；
但事件日志中的 blockHash 由 Conflux 节点在事件产生时写入，是 Conflux 原生哈希（cfx hash），
不经过代理修正。
两者来源不同，校验失败，L1 事件同步中断。"

适配策略（约 60 字）：
"在校验前用事件的 blockHash 直接覆盖区块数据中的 Hash 字段
（b.Hash = l.BlockHash），统一两者来源，消除不一致。"

与 OP Stack 策略的对比（约 60 字）：
"OP Stack（4.2.4-A）的策略是'保留校验逻辑，将 ResetError 降级为告警'；
CDK 的策略是'统一数据来源，消除校验前的不一致'。
CDK 此处哈希问题来源单一（仅 evmdownloader 一处），
覆盖策略更简洁，不需要引入降级逻辑。"
```

- [ ] **Step 3: 撰写 C 节——运行稳定性修复（约 300 字）**

C-1 zkevm-ethtx-manager 死循环修复（约 200 字）：
```
背景（约 30 字）：
"cdk-node aggregator 通过 zkevm-ethtx-manager 管理 L1 上的 ZK 证明提交交易。"

问题（约 60 字）：
"当 L1 交易因合约状态问题 revert 时，
原版库对交易进入无限重试循环；
aggregator 永久阻塞，Last Verified Batch Number 停止更新。
测试中一次 revert 可导致系统数小时不可恢复，需手动重启。"

解决方案（约 60 字）：
"通过 cdk/go.mod 中的 replace 指令，
将 zkevm-ethtx-manager 替换为 pana/zkevm-ethtx-manager fork
（原版本 [核实后填入]，fork 版本 [核实后填入]）。
该 fork 对 revert 结果有明确的失败终止逻辑：
失败后上报错误并退出重试，由上层决定是否重新提交。
上层 cdk-node 代码无改动。"

根本矛盾说明（约 50 字）：
"无限重试的设计本意是应对网络抖动等临时性错误；
但合约 revert 是确定性失败，重试不改变结果，只阻塞整条证明流水线。
fork 的本质是区分了'临时错误应重试'和'确定失败应终止'两类场景。"
```

C-2 合约部署脚本 exit code 适配（约 100 字）：
```
问题（约 50 字）：
"kurtosis-cdk 的 Starlark 脚本通过 plan.exec 调用 shell 脚本部署 L1 合约。
原始调用方式无法正确捕获 shell exit code：
脚本失败时 kurtosis 不中止流程，在错误状态下继续启动后续服务，
问题在更后期才暴露，难以定位根因。"

方案（约 50 字）：
"改为通过 bash -c 包装执行脚本，使 shell exit code 正确传播至 kurtosis，
部署失败时立即中止，避免在错误状态下继续运行。"
```

- [ ] **Step 4: 自查 4.2.5**

- [ ] A 节明确说明放弃了聚合能力（Pessimistic Proof），并说明未来可恢复的条件
- [ ] B 节有与 4.2.4-A 的策略对比（CDK 是"统一来源"vs OP Stack 是"降级错误"）
- [ ] C 节 ethtx-manager 说明了"临时错误/确定失败"的区分是修复的本质
- [ ] go.mod replace 指令的版本号已核实并填写，不留占位符

- [ ] **Step 5: Commit**

```bash
git add doc-report/4.2-rollup-sidechain-integration.md
git commit -m "docs: draft 4.2.5 CDK adaptation"
```

---

### Task 10: 全节最终审校与收尾

**Files:**
- Read: `doc-report/4.2-rollup-sidechain-integration.md`
- Read: `docs/superpowers/specs/2026-05-06-rollup-sidechain-integration-spec.md`（自查清单）
- Modify: `doc-report/4.2-rollup-sidechain-integration.md`

- [ ] **Step 1: 对照 spec 全部 15 条自查清单逐项核查**

| # | 检查项 | 状态 |
|---|-------|------|
| 1 | 4.2.1 五类问题有"相互独立"的说明 | |
| 2 | 4.2.1 C1 影响面包含具体代码位置和失败后果 | |
| 3 | 4.2.1 C3 说明 maxSequencerDrift 1800s、Fjord 后不可配置 | |
| 4 | 4.2.2 总览表"实施位置"列全部填写 | |
| 5 | 4.2.2 C1 对比表"不能覆盖的场景"列全部填写 | |
| 6 | 4.2.4-B L1 origin 追赶说明两部分缺一不可 | |
| 7 | 4.2.4-B 说明追赶时 deposit 事件的处理情况 | |
| 8 | 4.2.4-C checkMinGas 说明对用户操作的影响 | |
| 9 | 4.2.4-C 提现参数说明约束关系（max(...)≤maxClockDuration）| |
| 10 | 4.2.5-A 明确放弃聚合能力及可恢复条件 | |
| 11 | 4.2.5-C ethtx-manager 说明临时/确定失败区分 | |
| 12 | 全节每个解决方案对应 4.2.1 的问题编号（C1–C5）| |
| 13 | 全节无"这种设计不仅……还……"尾巴句 | |
| 14 | 全节无"综合考虑后选择"空洞论证 | |
| 15 | 原创工作篇幅占全节 80% 以上 | |

- [ ] **Step 2: 核查各节字数**

统计字数，对照目标范围：
- 4.2.1：目标 1000–1200 字
- 4.2.2：目标 700–900 字
- 4.2.3：目标 700–900 字
- 4.2.4：目标 1350–1850 字
- 4.2.5：目标 850–950 字
- 全节：目标 5800–6900 字

如有节未达下限，补充内容；如超出上限，精简冗余表述（优先删除重复的背景回顾）。

- [ ] **Step 3: 删除草稿区内容**

将 Task 2–4 在文件末尾记录的"写作草稿区"内容删除，确保正文文件只包含可提交的正文。

- [ ] **Step 4: 最终 Commit**

```bash
git add doc-report/4.2-rollup-sidechain-integration.md
git commit -m "docs: complete 4.2 section final review"
```

---

## 自查结果（写作完成后填写）

计划完成时此处填写：
- 实际字数：___
- 未覆盖的 spec 要求：___
- 需要补充的技术数据：___
