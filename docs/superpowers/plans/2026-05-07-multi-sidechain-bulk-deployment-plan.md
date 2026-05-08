# 4.4 多类型侧链规模化部署 写作实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按照 `docs/superpowers/specs/2026-05-07-multi-sidechain-bulk-deployment-spec.md` 写出科技报告 4.4 节的完整产物 `doc-report/4.4-multi-sidechain-bulk-deployment.md`，约 11 页，论证式写作，原创工作占比 ≥85%。

**Architecture:** 单文件产物，按 spec 6 个二级节 + 子节顺序逐节写作。每个任务覆盖一个最小语义单元（一个子节或一个独立要素），任务间通过 commit 隔离，便于回滚单节重写。每节完成后按 spec 第四节"写作纪律检查清单"自检。

**Tech Stack:** Markdown（CommonMark），中文写作，引用 `cdk_pipe.sh` / `op_pipe.sh` / `xjst_pipe.sh` 实际代码与 `ydyl-deploy-client` README。

**写作风格基线（每个任务都适用）：**
- 段落承载论述、列表承载枚举（指南 4.1）
- 论证式而非导游式：问题→设计空间→选择论证→实现→代价（指南 2.3）
- 用具体数据替代评价性虚词（指南 4.2/4.3）
- 不重复 4.2 节内容，仅引用
- 不混入项目管理信息

---

## Task 1: 创建产物文件骨架

**Files:**
- Create: `doc-report/4.4-multi-sidechain-bulk-deployment.md`

**Goal:** 把 spec 第二节"总体结构"中的所有标题落到产物文件中，建立可分节填充的骨架。

- [ ] **Step 1: 读 spec 第二节，确认所有节号与标题**

Read: `docs/superpowers/specs/2026-05-07-multi-sidechain-bulk-deployment-spec.md` 的"二、总体结构"

- [ ] **Step 2: 写入骨架文件**

写入下列内容到 `doc-report/4.4-multi-sidechain-bulk-deployment.md`：

```markdown
## 4.4 多类型侧链规模化部署

### 4.4.1 问题分析与研究目标

### 4.4.2 总体部署架构

#### 4.4.2.1 控制平面与数据平面分离

#### 4.4.2.2 网络拓扑设计

#### 4.4.2.3 公共依赖与组件清单

#### 4.4.2.4 总体架构图

### 4.4.3 三类侧链流水线的服务与流程

#### 4.4.3.1 公共骨架：12 步流水线五阶段抽象

#### 4.4.3.2 OP Rollup 流水线

#### 4.4.3.3 CDK Rollup 流水线

#### 4.4.3.4 XJST 联盟链侧链流水线

#### 4.4.3.5 Counter 部署与桥注册

#### 4.4.3.6 三栈对照表

### 4.4.4 ydyl-deploy-client 编排链路

### 4.4.5 规模化部署验证

### 4.4.6 局限与展望
```

- [ ] **Step 3: 提交**

```bash
git add doc-report/4.4-multi-sidechain-bulk-deployment.md
git commit -m "docs: 4.4 节产物骨架"
```

---

## Task 2: 写 4.4.1 问题分析与研究目标

**Files:**
- Modify: `doc-report/4.4-multi-sidechain-bulk-deployment.md`（4.4.1 节）

**Spec 对应：** 第三节 4.4.1 段落

**篇幅目标：** ~1 页

**必须覆盖的要素：**
1. 核心问题陈述（精确到可判断"解决了没有"）
2. 四个子挑战 C1–C4，每个独立一段：
   - C1 异构栈差异（CDK/OP/XJST 三套不同形态）
   - C2 多步状态化部署（12 步、长尾、半途失败）
   - C3 拓扑约束（L2 head 滞后累积，**不是** maxSequencerDrift）
   - C4 元数据契约（部署产物到压测的衔接）
3. 量化研究目标 4 条，必须包含 ≥10 亿用户账户验收

**写作禁忌：**
- 不要写成"项目背景"——必须以问题陈述开篇
- C3 不得描述为 maxSequencerDrift（那是 4.2 C3 的瞬时事故，本节是累积型滞后）

- [ ] **Step 1: 重读 spec 4.4.1 段落与四个 C 的根因描述**

- [ ] **Step 2: 起草核心问题陈述（一段，不超过 80 字）**

模板：
> 在异构 L2 栈共存的环境下，如何以可恢复、可观测、对后续跨链压测友好的方式，将 96 条 XJST、2 条 CDK（zk-rollup）、2 条 OP Stack（op-rollup）共 100 条侧链一次性部署到 AWS EC2 上，并保证产出的元数据足以驱动后续的跨链消息验证与 TPS 测试？

- [ ] **Step 3: 起草 C1–C4 四段（每段 100–200 字）**

每段必须：①点出根因，②给出"为什么难"的具体技术理由，③不与其它 C 重叠。

- [ ] **Step 4: 起草研究目标 4 条**

按编号列表：①单条命令批量发起、②无人工 jobs 生成、③10 亿账户验收、④跨链 Counter 全链路可达。

- [ ] **Step 5: 自检**

对照 spec 4.4.1 的"研究目标（量化验收）"四条，逐条核对是否在文中出现。检查 C3 描述是否为"累积滞后"而非"sequencer drift 瞬时停摆"。

- [ ] **Step 6: 提交**

```bash
git add doc-report/4.4-multi-sidechain-bulk-deployment.md
git commit -m "docs: 4.4.1 问题分析与研究目标"
```

---

## Task 3: 写 4.4.2.1 控制平面与数据平面分离

**Spec 对应：** 第三节 4.4.2.1

**篇幅目标：** ~1 页

**必须覆盖的三论点：**
1. 控制平面无状态：`ydyl-deploy-client` 不持有任何链产物，链状态都在数据平面（`*-work/output/`、`*_pipe.state`）
2. 数据平面节点的标准形态（三类角色）：
   - L2 节点本体（CDK 多容器 / OP 四进程 / XJST 单进程）
   - 跨链中继服务（zk-claim-service / op-claim-service，XJST 无）
   - 元数据服务 ydyl-console-service
3. `jsonrpc-proxy` **不在节点标准形态中**，按拓扑差异分别部署：
   - OP 共享一实例（block hash 适配的有状态特性）
   - CDK 每链独立一实例（无 hash 适配需求）
   - XJST 不需要

外加节点间关系一段：96 XJST 链**链内部**多节点协同；跨链均独立；100 链共享单一 `L1_BRIDGE_HUB_CONTRACT`。

- [ ] **Step 1: 重读 spec 4.4.2.1 三论点**

- [ ] **Step 2: 用段落形式起草三论点**

每个论点独立一段，段间有"先 X，再 Y，最后 Z"的逻辑递进，避免退化为 bullet 罗列。

- [ ] **Step 3: 起草 jsonrpc-proxy 拓扑差异段**

OP 共享 / CDK 独立 / XJST 无的根因必须在本段交代，但**论证细节延后到 4.4.3.2 完整展开**——本节仅给结论。

- [ ] **Step 4: 起草节点间关系段**

明确"链内 vs 跨链"的边界，并指明 `L1_BRIDGE_HUB_CONTRACT` 是唯一全局单点。

- [ ] **Step 5: 自检**

确认未提前展开"OP 为什么必须共享 proxy"的有状态论证（那是 4.4.3.2 的内容）。

- [ ] **Step 6: 提交**

```bash
git commit -am "docs: 4.4.2.1 控制平面与数据平面分离"
```

---

## Task 4: 写 4.4.2.2 网络拓扑设计

**Spec 对应：** 第三节 4.4.2.2

**篇幅目标：** ~0.5 页

**必须覆盖：**
1. 同 region 同 AZ 部署的目的（压低节点到 L1 RPC 的延迟）
2. 累积滞后机制：RPC 延迟升高 → OP Stack L1 origin 推进失败 → 后续 L2 区块复用上一个 origin → L2 head 与 L1 head 滞后量随时间单调增长（CDK 不受此影响）
3. 与 4.2 C3 的关系：4.2 C3 是触达 maxSequencerDrift 后的瞬时事故，本节是更早期、更普遍的累积劣化（**两者相邻而非同一问题**）
4. L1 共享面边界：`BRIDGE_HUB`（全局共享）vs 各栈本链桥实现（按链独立）

- [ ] **Step 1: 重读 spec 4.4.2.2 与 4.2 C3 章节**

Read: `doc-report/4.2-rollup-sidechain-integration.md` 的 C3 段，确认本节描述与之相邻而非重复。

- [ ] **Step 2: 起草拓扑论点段**

第一句给结论（同 region 同 AZ），第二句给目的（压低延迟），后续段交代累积滞后机制。

- [ ] **Step 3: 起草 L1 共享面边界段**

明确写出"`BRIDGE_HUB` 是 100 链唯一全局单点；`unified_bridge` / `state_sender` / OP/CDK 桥合约均按链独立"。

- [ ] **Step 4: 自检**

搜本节是否出现 `maxSequencerDrift` —— 若出现，必须明确标注为"4.2 C3 的瞬时事故"而非本节话题。

- [ ] **Step 5: 提交**

```bash
git commit -am "docs: 4.4.2.2 网络拓扑设计"
```

---

## Task 5: 写 4.4.2.3 公共依赖与组件清单

**Spec 对应：** 第三节 4.4.2.3

**篇幅目标：** ~1 页

**必须覆盖：**
1. 完整组件表（含 ydyl-gen-accounts 行）
2. ydyl-gen-accounts 角色专段（不可省略）：deterministic 派生、step9 调用、10 亿账户验收承载

**组件表精确内容：**

| 组件 | 角色 | CDK | OP | XJST |
|------|------|-----|-----|------|
| `*_pipe.sh` | 编排入口 | cdk_pipe.sh | op_pipe.sh | xjst_pipe.sh |
| L2 节点 | 链本体 | Kurtosis(cdk-erigon, cdk-node, zkevm-prover) | Kurtosis(op-node, op-geth, op-batcher, op-proposer) | conflux-rust(xjst 模式) |
| `jsonrpc-proxy` | L1 RPC 适配层 | 每链独立一实例 | 所有 OP 链共享一实例 | ✗ |
| claim-service | 跨链消息中继 | `zk-claim-service` | `op-claim-service` | ✗（直 bridge） |
| `ydyl-console-service` | 元数据 HTTP API | ✓ | ✓ | ✓ |
| `ydyl-gen-accounts` | 大规模用户账户生成与充值（10 亿级验收指标的承载者） | ✓ | ✓ | ✓ |
| PM2 | Node 服务进程管理 | ✓ | ✓ | ✓ |

- [ ] **Step 1: 把组件表原样写入产物**

- [ ] **Step 2: 起草 ydyl-gen-accounts 专段（约 150–200 字）**

要点：①Hardhat/TS 实现，②deterministic 派生规则（EVM 用 chainID + index、XJST 用 groupID + index），③每条链 step9 调用一次，④100 链汇总承担 ≥10 亿账户验收，⑤因此不是可选辅助而是核心组件。

- [ ] **Step 3: 自检**

确认 jsonrpc-proxy 行的拓扑差异在表中已正确反映；ydyl-gen-accounts 段必须呼应 4.4.1 的 10 亿验收指标。

- [ ] **Step 4: 提交**

```bash
git commit -am "docs: 4.4.2.3 公共依赖与组件清单"
```

---

## Task 6: 写 4.4.2.4 总体架构图

**Spec 对应：** 第三节 4.4.2.4

**篇幅目标：** ~0.5 页

**必须覆盖：** 一张文本架构图 + 一段说明（L1 外部依赖、`L1_BRIDGE_HUB_CONTRACT` 唯一全局单点）。

- [ ] **Step 1: 把 spec 4.4.2.4 中的架构图原样写入**

```
┌──────────────────── 控制平面 ──────────────────────┐
│  ydyl-deploy-client (Go/Cobra)                    │
│  ├─ deploy / deploy-restore                       │
│  ├─ gen-cross-tx-config                           │
│  └─ bench-cross-tx / tps                          │
└────────────┬──────────────────────────────────────┘
             │ AWS API + SSH
             ▼
┌──────────────────── 数据平面（×100 EC2） ──────────┐
│   XJST ×96       │   CDK ×2        │   OP ×2      │
│  xjst_pipe.sh    │  cdk_pipe.sh    │  op_pipe.sh  │
└──────────────────────┬────────────────────────────┘
                       │ HTTP（元数据）
                       ▼
                  servers.json
                       │
                       ▼
              gen-cross-tx-config
                       │
                       ▼
              jobs/*.json → ydyl-bench-docker
```

- [ ] **Step 2: 起草说明段**

一段两句：L1 是外部依赖；`L1_BRIDGE_HUB_CONTRACT` 是 100 链唯一全局单点（已与 4.4.2.1 论点呼应）。

- [ ] **Step 3: 提交**

```bash
git commit -am "docs: 4.4.2.4 总体架构图"
```

---

## Task 7: 写 4.4.3.1 公共骨架五阶段抽象

**Spec 对应：** 第三节 4.4.3.1

**篇幅目标：** ~0.5 页

**必须覆盖：** 五阶段总览表（按 spec 给定），并以一句过渡引出后续 4.4.3.2–4 三栈具体展开。

**五阶段表精确内容：**

| 阶段 | 步骤 | 共性目的 |
|------|------|----------|
| ① 身份与资金准备 | step1 初始化密钥、step2 L1 充值 | 部署者 / claim-service / L2 部署者三类账户从 L1 vault 充值 |
| ② L1 接入层 | step3 启 jsonrpc-proxy（XJST：部 L1 合约） | 解决 4.2 节 L1 兼容性 / 部署本链 L1 合约 |
| ③ L2 部署 | step4 拉起 L2 节点、step5 L2 充值 | 链本体与 L2 测试钱包就绪 |
| ④ 跨链中继与桥注册 | step6 生成 .env、step7 部 Counter + 注册 bridge、step8 启 claim-service | 把单链转化为可互操作侧链 |
| ⑤ 元数据与可观测 | step9 批量账户、step10 元数据归档、step11 console-service、step12 PM2 巡检 | 为下游压测与控制平面查询提供契约 |

- [ ] **Step 1: 写入五阶段表**

- [ ] **Step 2: 起草过渡段**

末尾一句明确"三条流水线的差异主要落在阶段 ②③④。下面分别展开。"作为承上启下。

- [ ] **Step 3: 提交**

```bash
git commit -am "docs: 4.4.3.1 公共骨架五阶段抽象"
```

---

## Task 8: 写 4.4.3.2 OP Rollup 流水线（**重点章节**）

**Spec 对应：** 第三节 4.4.3.2

**篇幅目标：** ~2 页（最详细的子节）

**必须覆盖：**
1. 部署的服务清单 4 项：
   - 全栈共享 jsonrpc-proxy
   - Kurtosis OP Stack（op-node / op-geth / op-batcher / op-proposer）
   - op-claim-service
   - ydyl-gen-accounts
2. 关键步骤深入：step3 共享 proxy 接入语义、step4 部署细节（出块 1s + calldata 模式）、step6→7→8 跨链链路
3. **完整的"OP 共享 proxy vs CDK 独立 proxy"论证**（三段，按 spec 给定）：
   - OP 的 hash 修正是有状态的（必须共享）
   - CDK 不在代理层做 hash 修正（无状态、可独立）
   - 拓扑后果：OP 共享 proxy 是除 BRIDGE_HUB 之外第二个全局点
4. OP 链 step9 的账户生成（呼应 10 亿验收）

**禁忌：**
- 不要提及 `YDYL_NO_TRAP=1` 这类代码细节
- 不要在此节展开 maxSequencerDrift（4.2 内容）

- [ ] **Step 1: 起草服务清单（编号列表）**

- [ ] **Step 2: 起草关键步骤深入（按 step3/step4/step6→8 三个子标题）**

每子标题下用段落写作，不退化为 bullet。step3 段必须给出"共享 proxy 接入"而非"每链独立起一个"的语义，并交代根因（与 4.2 C1 的 hash 修正有状态特性的关系）。

- [ ] **Step 3: 起草共享 vs 独立 proxy 论证（三段）**

第一段：OP 必须共享的根因（hash 映射表的状态一致性）
第二段：CDK 必须独立的根因（无状态、避免单点瓶颈）
第三段：对部署架构的影响（OP 共享 proxy 是第二个全局点）

- [ ] **Step 4: 起草 OP step9 账户生成段**

明确 `l2type=0` + chainID 派生路径，单链账户量是 10 亿验收按 100 链摊分的份额。

- [ ] **Step 5: 自检**

按 spec 第四节检查清单逐项核对：
- 论证式而非导游式 ✓
- 段落承载论述 ✓
- 不重复 4.2 ✓
- 无 YDYL_NO_TRAP 细节 ✓

- [ ] **Step 6: 提交**

```bash
git commit -am "docs: 4.4.3.2 OP Rollup 流水线"
```

---

## Task 9: 写 4.4.3.3 CDK Rollup 流水线（精简）

**Spec 对应：** 第三节 4.4.3.3

**篇幅目标：** ~1 页（精简，不重复 4.4.3.2 已论证内容）

**必须覆盖：**
1. 服务清单 4 项（CDK 版本，本链独立 jsonrpc-proxy）
2. 关键步骤要点（step3/step4/step6→8）——简短即可，详细机制延后引用 4.4.3.2
3. 与 OP 的关键差异 3 条：代理拓扑、跨链证明形态（ZK vs Merkle）、资源消耗

**禁忌：**
- 不重复 4.4.3.2 已展开的 OP 共享 proxy 根因（仅引用）
- 不要提及 `YDYL_NO_TRAP=1`
- 不要列入"sequencer 时序差异"这类与部署形态无关的差异

- [ ] **Step 1: 起草服务清单**

明确 jsonrpc-proxy 是"本链独立"，区别于 4.4.3.2 OP 共享。

- [ ] **Step 2: 起草关键步骤要点（每个 step 1–2 句）**

避免重复 4.4.3.2 中已交代的内容；与 OP 同型异构的部分用"与 4.4.3.2 同型异构"一句带过。

- [ ] **Step 3: 起草"与 OP 的关键差异" 3 条**

只列 3 条：①代理拓扑（已在 4.4.3.2 论证），②ZK proof vs Merkle proof + claim-service 实现差异，③资源消耗（机型差异，驱动 4.4.4 的 services[] 配置）。

- [ ] **Step 4: 自检**

搜本节是否含 `maxSequencerDrift` 或 sequencer 时序差异——若有，删除（spec 已确认无关）。

- [ ] **Step 5: 提交**

```bash
git commit -am "docs: 4.4.3.3 CDK Rollup 流水线"
```

---

## Task 10: 写 4.4.3.4 XJST 联盟链侧链流水线

**Spec 对应：** 第三节 4.4.3.4

**篇幅目标：** ~1.5 页

**必须覆盖：**
1. 服务清单 3 项（无 jsonrpc-proxy、无独立 claim-service）：
   - 仅 node-1 执行的 L1 合约部署
   - XJST 节点本体
   - ydyl-gen-accounts
2. **节点角色分化**（node-1 三独占职责 vs node-2..node-N 仅启动 XJST 节点）
3. 节点协同图（按 spec 给定）
4. 论证段**仅一段**：`step_wait_for_other_nodes_to_start` 的实现与必要性（**不写其它论证段**）

**节点协同图原样：**

```
    一条 XJST 链内部                         全局共享层
   ┌──────────────────┐                ┌────────────────────────┐
   │   node-1（本链）   │                │ L1_BRIDGE_HUB_CONTRACT │
   │ step3 部本链 L1 合约│──暴露合约地址──►│  （100 条链共享单点）   │
   │  · simple_calc    │                └─────────▲──────────────┘
   │  · state_sender   │                          │
   │  · unified_bridge │                  step9 注册本链桥
   ├──────────────────┤                          │
   │ step5 启 XJST     │                          │
   │ step9 部 Counter   │──注册 bridges───────────┘
   └────┬─────────────┘
        │ HTTP（/v1/result/node-deployment-contracts/xjst/l1）
        ▼
   ┌──────────────────┐
   │ node-2..node-N    │
   │ 仅启动 XJST 节点   │
   └──────────────────┘
```

- [ ] **Step 1: 起草服务清单**

明确 XJST 不依赖 jsonrpc-proxy 与独立 claim-service；node-1 独占承担 L1 合约部署。

- [ ] **Step 2: 起草节点角色分化段（段落写作）**

node-1 三职责（step3 部 L1 合约 / step9 部 Counter + 注册 bridge / 通过 console-service 暴露 L1 合约地址）；node-2..node-N 仅启动 XJST 节点，通过 `get_l1_deploy_contracts` 拉地址，`AUTO_DEPLOY_L1_CONTRACTS=false` 启动。

- [ ] **Step 3: 写入节点协同图**

- [ ] **Step 4: 起草唯一论证段——`step_wait_for_other_nodes_to_start`**

引用 `xjst-work/js-scripts/checkNodePeers.js`，说明 P2P 连通性轮询的目的与不等待的后果。

- [ ] **Step 5: 自检**

确认未写入 spec 此前删除的两段论证（"L1 桥独立 vs hub 共享"已挪到 4.4.3.5；"为什么不需要 jsonrpc-proxy"已并入 4.4.2.1）。

- [ ] **Step 6: 提交**

```bash
git commit -am "docs: 4.4.3.4 XJST 联盟链侧链流水线"
```

---

## Task 11: 写 4.4.3.5 Counter 部署与桥注册（三栈共用）

**Spec 对应：** 第三节 4.4.3.5

**篇幅目标：** ~1 页

**必须覆盖：**
1. 开篇说明：为什么单列本节——三栈唯一在流程位置与语义上完全一致的步骤，是异构侧链可互通的根本机制
2. 两个动作合一：①L2 端部署 Counter；②L1 端 `addBridgeService` 注册桥到 BridgeHub
3. 输入参数对照表（按 spec 给定）：

| 字段 | OP | CDK | XJST |
|------|----|----|------|
| `BRIDGES`（可数组） | OP 标准桥合约 | CDK 标准桥合约 | `unified_bridge`, `state_sender` |
| `L1_BRIDGE_HUB_CONTRACT` | 全局共享地址 | 全局共享地址 | 全局共享地址 |
| `L1_REGISTER_BRIDGE_PRIVATE_KEY` | 全局注册者 EOA | 全局注册者 EOA | 全局注册者 EOA |
| `L2_PRIVATE_KEY` | 本链 L2 部署 key | 本链 L2 部署 key | 本链 L2 部署 key |
| `L2_TYPE` | 0 | 1 | 2 |

4. **论证段**："为什么所有桥都注册到同一 BridgeHub"——桥实现按链独立 vs hub 全局唯一的边界划分
5. 节点角色约束：CDK/OP 由本链节点执行；XJST 仅 node-1 执行（防止重复注册）

**关键术语：**
- 共用脚本是 `zk-claim-service/scripts/i_deployCounterAndRegisterBridge.js`（命名带 zk 是历史原因，三栈共用）

- [ ] **Step 1: 起草开篇说明段**

明确单列原因：流程位置一致 + 语义一致 + 异构侧链可互通的根本机制。

- [ ] **Step 2: 起草"两个动作合一"段**

调用脚本名、L2 端动作、L1 端动作。

- [ ] **Step 3: 写入输入参数对照表**

- [ ] **Step 4: 起草论证段（段落形式）**

桥实现按链独立的理由（避免跨链状态污染）+ BridgeHub 全局唯一的理由（路由表必须唯一）+ `addBridgeService` 把"链类型 + 链 ID + 桥地址"三元组写入注册表的事实。

- [ ] **Step 5: 起草节点角色约束段**

CDK/OP vs XJST node-1 的差异；明确"重复注册会造成 hub 表中同一桥地址多次出现"是 XJST 仅 node-1 执行的根因。

- [ ] **Step 6: 提交**

```bash
git commit -am "docs: 4.4.3.5 Counter 部署与桥注册"
```

---

## Task 12: 写 4.4.3.6 三栈对照表

**Spec 对应：** 第三节 4.4.3.6

**篇幅目标：** ~0.5 页

**必须覆盖：** 对照表 + 一句承上启下（导出 4.4.4）。

**对照表精确内容：**

| 维度 | CDK | OP | XJST |
|------|-----|-----|------|
| 部署器 | Kurtosis | Kurtosis | 自研脚本 |
| L1 适配层 | 每链独立 jsonrpc-proxy | 全栈共享 jsonrpc-proxy（hash 一致性） | 无 |
| 本链 L1 合约 | rollup 合约组 | OptimismPortal2 等 | simple_calc / state_sender / unified_bridge |
| 跨链证明 | ZK proof | Merkle / Output Root | 直 bridge |
| 节点间协同 | 独立 | 独立 | 链内 node-1 ↔ node-N |
| 中继服务 | zk-claim-service | op-claim-service | 无 |
| step3 含义 | 启 proxy | 启 proxy | 部本链 L1 合约 |
| step5 含义 | L2 充值 | L2 充值 | 启 XJST 节点 |
| 资源消耗（相对） | 高 | 中 | 低 |

**禁忌：** 不再列入 sequencer 时序差异等无关行。

- [ ] **Step 1: 写入对照表**

- [ ] **Step 2: 起草承上启下段**

一句：这张表是承上启下的关键——下一节 4.4.4 介绍 deploy-client 时，正是基于这张表把"差异"压缩进 `services[].remoteCmd`。

- [ ] **Step 3: 提交**

```bash
git commit -am "docs: 4.4.3.6 三栈对照表"
```

---

## Task 13: 写 4.4.4 ydyl-deploy-client 编排链路

**Spec 对应：** 第三节 4.4.4

**篇幅目标：** ~1.5 页（精简，不展开实现细节）

**必须覆盖：** 5 个命令，每个一段：
1. `deploy`：批量起 EC2 + 等 SSH + 派发 `*_pipe.sh`，失败按节点级落入 `script_status.json`
2. `deploy-restore`：仅对 `failed` 状态节点重派；流水线本身的 `START_STEP` 续跑保证不重做已完成步骤——控制平面 × 数据平面双层续跑的复合
3. `gen-cross-tx-config`：扫 `servers.json` → 拉 `ydyl-console-service` → 笛卡尔积 → 8 路均分
4. `bench-cross-tx`：jobs 喂给 ydyl-bench-docker 8 个 multijob 容器（`7s_multijob.js`）
5. `tps`：单独起 `h_TPSjob.js` 容器监控 TPS

**禁忌：** 不展开 `script_status.json` 五态语义、不展开 SSH 探测细节——本节聚焦命令链路。

- [ ] **Step 1: 起草开篇过渡句**

一句：deploy-client 把 4.4.3 的三栈差异压缩到 `services[].remoteCmd`，五命令串成压测前的完整链路。

- [ ] **Step 2: 起草 5 个命令段**

每个命令一段，含输入/输出/职责，不展开实现。

- [ ] **Step 3: 自检**

逐条核对篇幅：每个命令不超过 4–5 句；总篇幅不超过 1.5 页。

- [ ] **Step 4: 提交**

```bash
git commit -am "docs: 4.4.4 ydyl-deploy-client 编排链路"
```

---

## Task 14: 写 4.4.5 规模化部署验证

**Spec 对应：** 第三节 4.4.5

**篇幅目标：** ~1.5 页

**必须覆盖：** 5 类数据，按 spec 列举：
1. 环境（机型矩阵、region/AZ、AMI、L1 接入点）
2. 耗时分布（单条 P50/P95、100 条并发墙钟）
3. 首跑 vs deploy-restore 后成功率（分栈、按 root cause 归类）
4. 元数据完整性（console-service 健康率、jobs 生成率）
5. 跨链可达性（随机抽 N 对侧链发起 Counter 调用）

**数据来源依赖：** 实测数据未取齐前，先以表格留位（每行给数据采集口径，单元格留 `TBD（待测）`）。完整数据采集后再回填本节并提交。

> ⚠️ **依赖项**：spec 第五节"待确认事项"第 2 条——4.4.5 实测数据来源需先对齐。本任务在数据未到位时仅完成表格框架与采集口径定义，不阻塞其他任务。

- [ ] **Step 1: 起草环境段**

明确机型矩阵（XJST/CDK/OP 三类、磁盘、L1 接入点），可先按当前已知配置写入。

- [ ] **Step 2: 写入 4 张数据采集表（耗时 / 成功率 / 元数据完整性 / 跨链可达性）**

每张表只列字段与口径，数据单元格写 `TBD（待测）` 或具体值（如已有）。

- [ ] **Step 3: 起草 baseline 对比说明（如适用）**

按指南 4.3 节"用数据说话"，至少为成功率给出 baseline——例如"若不使用 deploy-restore 而整批重跑，预计需 X 小时"。

- [ ] **Step 4: 提交（表格 + TBD 形式）**

```bash
git commit -am "docs: 4.4.5 规模化部署验证（表格框架，待回填）"
```

- [ ] **Step 5: 数据采集完成后回填**（独立提交）

```bash
git commit -am "docs: 4.4.5 实测数据回填"
```

---

## Task 15: 写 4.4.6 局限与展望

**Spec 对应：** 第三节 4.4.6

**篇幅目标：** ~0.5 页

**必须覆盖 4 条局限**（按 spec 给定）：
1. 一机一链的资源开销线性增长，未做多租户压缩
2. 控制平面单点（运行 deploy 的开发机），缺自动 leader 切换
3. **OP 共享 jsonrpc-proxy 是除 BRIDGE_HUB 之外第二个全局点**：故障域覆盖全部 OP 链；当前未做高可用
4. 每条 XJST 链 node-1 在 step3 是该链内部单点（爆炸半径限于单链）
5. 跨 region/AZ 部署下 L2 head 对 L1 head 的滞后量随时间累积

- [ ] **Step 1: 起草 5 段**

每条局限一段，主动暴露代价（指南 2.3 节第 4 要素），不回避。

- [ ] **Step 2: 提交**

```bash
git commit -am "docs: 4.4.6 局限与展望"
```

---

## Task 16: 全文自查（spec 第四节写作纪律检查清单）

**Spec 对应：** 第四节"写作纪律检查清单"7 条

**Goal:** 全文按 7 条纪律逐项扫描，发现问题立即修复并单独提交。

- [ ] **Step 1: 检查"原创工作占比 ≥85%"**

数一遍背景介绍（4.4.1）字数与原创工作（4.4.2–4.4.5）字数，确认背景 ≤15%。若背景过多，删除多余教学内容。

- [ ] **Step 2: 检查"论证式而非导游式"**

逐节检查关键设计是否包含"设计空间 → 选择论证 → 代价"完整链条。重点检查：
- 4.4.2.1 控制平面无状态化（论点 1）
- 4.4.3.2 OP 共享 proxy
- 4.4.3.3 CDK 独立 proxy
- 4.4.3.4 XJST 节点协同
- 4.4.3.5 桥独立 vs hub 全局

- [ ] **Step 3: 检查"数据替代评价"**

grep "高吞吐"、"显著"、"质的飞跃"、"极大"、"从根本上"等评价性虚词；若发现，替换为具体数据或可验证条件。

- [ ] **Step 4: 检查"段落承载论述"**

逐节扫描，是否有连续 bullet 实际表达因果/时序的——若有，改为段落。

- [ ] **Step 5: 检查"章节衔接"**

读 4.4.2 末尾 → 4.4.3 开头是否自然过渡；读 4.4.3.6 末尾 → 4.4.4 开头是否由对照表自然导入。若衔接突兀，补一两句过渡。

- [ ] **Step 6: 检查"不重复 4.2"**

grep "FloorDataGas"、"哈希修正"、"checkMinGas"、"EIP-7623"等 4.2 节专有术语，若出现且超过点到为止的引用，改为引用句"详见 4.2 节"。

- [ ] **Step 7: 检查"不混入项目管理信息"**

grep "待 XX"、"需与 XX 确认"、"对方"、"协助"等项目管理用语，若发现，删除。

- [ ] **Step 8: 提交修复**

```bash
git commit -am "docs: 4.4 全文自查修复"
```

---

## Self-Review

### Spec 覆盖核对

| Spec 章节 | 实施任务 |
|----------|---------|
| 4.4.1 | Task 2 |
| 4.4.2.1 | Task 3 |
| 4.4.2.2 | Task 4 |
| 4.4.2.3 | Task 5 |
| 4.4.2.4 | Task 6 |
| 4.4.3.1 | Task 7 |
| 4.4.3.2 | Task 8 |
| 4.4.3.3 | Task 9 |
| 4.4.3.4 | Task 10 |
| 4.4.3.5 | Task 11 |
| 4.4.3.6 | Task 12 |
| 4.4.4 | Task 13 |
| 4.4.5 | Task 14 |
| 4.4.6 | Task 15 |
| 写作纪律检查清单 | Task 16 |

所有 spec 章节均被任务覆盖。

### 任务粒度

每个任务对应一个独立 git commit，可单独回滚或重写。Task 8（OP 流水线）与 Task 14（验证）是两个最大的任务，分别约 2 页和 1.5 页；其余子节任务均 ≤1 页。

### 依赖项

- Task 14（4.4.5 验证）依赖实测数据采集——已在任务内拆为"表格框架先行 + 数据回填"两个独立提交，不阻塞其他任务串行执行。
- Task 8（OP 流水线）必须先于 Task 9（CDK 流水线）完成，因为 Task 9 引用 Task 8 的 OP 共享 proxy 论证。
- Task 11（Counter + bridge 注册）应在 Task 8/9/10 之后写，便于回顾三栈共用的统一性。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-07-multi-sidechain-bulk-deployment-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** - 每个任务 dispatch 一个新 subagent，任务间复审，迭代快

**2. Inline Execution** - 在当前 session 内顺序执行，使用 executing-plans 批量执行 + checkpoint 复审

哪种方式？
