# 科技报告 4.4 节写作规格说明
# 多类型侧链规模化部署

**日期**：2026-05-07
**对应报告章节**：第四章 4.4
**写作负责人**：大勇
**写作规范参考**：doc-report/科技报告写作质量指南.markdown

---

## 一、文档定位

本节在整个报告中的位置：

```
第四章 多类型侧链扩展与跨链互操作关键技术研究
  4.1 问题分析与研究目标（李辰星）
  4.2 Rollup 侧链接入方案（大勇）
  4.3 树图联盟链侧链方案（向荣）
  4.4 多类型侧链规模化部署（大勇）          ← 本节
  4.5 通用跨侧链消息传递机制（梓含）
  4.6 测试与验证
```

**本节职责**：论证将 96 条 XJST 联盟链侧链、2 条 CDK zk-rollup 侧链、2 条 OP Stack op-rollup 侧链共 100 条异构侧链批量部署到统一互操作网络的技术方案。重点在三类侧链流水线的服务组成与流程编排，以及支撑规模化的部署架构设计。不承担 4.2 节已论证的兼容性适配内容，不承担 4.5 节的跨链消息协议内容。

**读者预设**：同领域评审专家，已读过 4.2 与 4.3，了解 Rollup 与联盟链的基础架构，但不了解本项目的部署组织方式与三类流水线的具体编排。

---

## 二、总体结构

```
4.4 多类型侧链规模化部署
│
├── 4.4.1  问题分析与研究目标
│           C1. 异构栈差异
│           C2. 多步状态化部署
│           C3. 拓扑约束（L2 head 对 L1 head 的滞后累积）
│           C4. 元数据契约（部署产物到压测的衔接）
│
├── 4.4.2  总体部署架构（重点章节）
│           4.4.2.1  控制平面与数据平面分离
│           4.4.2.2  网络拓扑设计
│           4.4.2.3  公共依赖与组件清单（含三栈对照表）
│
├── 4.4.3  三类侧链流水线的服务与流程（主体章节）
│           4.4.3.1  公共骨架：12 步流水线五阶段抽象
│           4.4.3.2  OP Rollup 流水线（更详细）
│           4.4.3.3  CDK Rollup 流水线（精简）
│           4.4.3.4  XJST 联盟链侧链流水线
│           4.4.3.5  Counter 部署与桥注册（三栈共用环节）
│           4.4.3.6  三栈对照表
│
├── 4.4.4  ydyl-deploy-client 编排链路
│           （deploy / deploy-restore / gen-cross-tx-config / bench / tps）
│
├── 4.4.5  规模化部署验证
│
└── 4.4.6  局限与展望
```

**篇幅分配**：

| 节 | 估计页数 | 占比 |
|----|---------|------|
| 4.4.1 问题分析 | ~1 | 9% |
| 4.4.2 部署架构（重点） | ~3 | 27% |
| 4.4.3 三类流水线（主体） | ~6 | 55% |
| 4.4.4 deploy-client 编排 | ~1.5 | — |
| 4.4.5 验证 | ~1.5 | — |
| 4.4.6 局限 | ~0.5 | — |

总计约 11 页。原创工作占比 ≥85%。

---

## 三、各小节内容规格

### 4.4.1 问题分析与研究目标（~1 页）

**核心问题陈述**（必须精确到可判断"解决了没有"）：

> 在异构 L2 栈共存的环境下，如何以可恢复、可观测、对后续跨链压测友好的方式，将 96 条 XJST、2 条 CDK（zk-rollup）、2 条 OP Stack（op-rollup）共 100 条侧链一次性部署到 AWS EC2 上，并保证产出的元数据足以驱动后续的跨链消息验证与 TPS 测试？

**四个子挑战**（每个一段，给出"为什么难"的具体根因）：

- **C1 异构栈差异**：三类侧链各自有独立流水线（`cdk_pipe.sh` / `op_pipe.sh` / `xjst_pipe.sh`）、独立环境变量契约、独立产物落点。CDK 走 Kurtosis + ZK proof 中继；OP 走 Kurtosis + Merkle proof 中继；XJST 走自有 L1 合约部署 + 链内多节点协同 + 直 bridge。三套形态不可能用单一脚本统一。
- **C2 多步状态化部署**：每条链 12 步流水线，单条 CDK 含 Kurtosis 启动、L1/L2 合约部署、claim-service 拉起等长尾步骤，半途失败不能从零重启。
- **C3 拓扑约束**：OP Stack 的 `L1Traversal` 每次推进时将 L1 origin 向前递增一格；当 L1 RPC 查询延迟高时 origin 推进失败，后续 L2 区块复用上一个 L1 origin，L2 所引用的 L1 origin 与真实 L1 head 的差距随时间持续扩大。CDK 的 sequencer 不使用 L1 origin 追踪逻辑，不受此问题影响。这一滞后是累积型而非瞬时型，跨 region/AZ 拓扑下尤为明显——把"批量部署"从纯软件问题升级为部署拓扑约束。
- **C4 元数据契约**：100 条链各自产出 RPC、bridge、Counter 合约地址，若无统一契约，下游 `gen-cross-tx-config` → `ydyl-bench-docker` 链路不可复用。

**研究目标**（量化验收）：

1. 单条命令一次性发起 ≥100 条侧链批量部署；失败可定向重试不重建已成功节点
2. 部署完成后无人工整理即可生成 8 路并行跨链压测 jobs
3. **100 条链上累计创建 ≥10 亿用户账户**——这一规模是侧链可承载真实业务负载的硬指标，由 `ydyl-gen-accounts` 在每条链的 step9 批量生成与充值
4. 96 XJST + 2 CDK + 2 OP，跨链 Counter 调用全链路可达

---

### 4.4.2 总体部署架构（~3 页，重点章节）

#### 4.4.2.1 控制平面与数据平面分离

**核心三论点**：

1. **控制平面无状态**：`ydyl-deploy-client` 不持有任何链产物，所有链状态都落在数据平面节点本地（`*-work/output/`、`*_pipe.state`）。控制平面失联不影响已部署节点继续运行。

2. **数据平面节点的标准形态**：每台 EC2 承担三类角色——
   - L2 节点本体（CDK 是 Kurtosis 编排的多容器、OP 是 op-node/op-geth/op-batcher/op-proposer、XJST 是 conflux-rust 的 xjst 模式）
   - 跨链中继服务（zk-claim-service / op-claim-service，XJST 无独立中继）
   - 元数据服务 `ydyl-console-service`

   **`jsonrpc-proxy` 不在节点标准形态中**，按拓扑差异分别部署（见 4.4.2.3）：
   - **OP 共享一个 `jsonrpc-proxy` 实例**：所有 OP 链复用同一个代理，因为 OP 的 block hash 适配要求所有 OP 节点从同一起始 block 进入 derivation 才能保证 hash 修正后的一致性
   - **CDK 每条链独立一个 `jsonrpc-proxy`**：CDK 不在代理层做 block hash 适配（CDK 的 hash 校验冲突由内核侧解决，详见 4.2 节），代理仅承担 RPC 转发与 gas 补偿等无状态职责，可一链一实例
   - **XJST 不需要 `jsonrpc-proxy`**

3. **节点间关系**：96 条 XJST **链内部**存在多节点协同（同一条 XJST 链的 node-2..node-N 需从 node-1 拉取该链专属的 L1 合约地址组——`simple_calculator` / `state_sender` / `unified_bridge`），跨链之间各 XJST 完全独立；CDK/OP 链同样彼此独立。**所有 100 条链共享单一 `L1_BRIDGE_HUB_CONTRACT`**，这是把异构侧链编织成统一互操作网络的唯一全局单点。

#### 4.4.2.2 网络拓扑设计

**核心论点**：同 region 同 AZ 部署，目的是压低节点到 L1 RPC 的网络延迟。OP Stack 的 `L1Traversal` 每次推进时通过 RPC 查询下一个 L1 区块；RPC 延迟一旦升高 origin 推进失败，后续 L2 区块复用上一个 L1 origin，L2 所引用的 L1 origin 与真实 L1 head 的差距随时间单调扩大——这种滞后是累积型而非瞬时型，跨 region/AZ 拓扑下尤为明显。CDK 的 sequencer 不使用 L1 origin 追踪逻辑，不受此影响。

**与 4.2 节 C3 的关系**：4.2 C3 描述的是触达 `maxSequencerDrift` 硬阈值后 sequencer 设 NoTxPool、仅出含 L1 属性存款交易的空区块、继而可能彻底停块的瞬时事故；本节描述的是更早期、更普遍的 L2 head 持续滞后现象（累积劣化）。两者是相邻而非同一问题。

**L1 共享面边界**：与 `L1_BRIDGE_HUB_CONTRACT` 全局单点并列的另一组 L1 合约——XJST 的 `unified_bridge` / `state_sender` / `simple_calculator`、CDK 的 rollup 合约组、OP 的 OptimismPortal2 等——是**每条链独立**部署的，不存在跨链共享。"L1 共享"与"L1 独立"的边界精确落在 `BRIDGE_HUB` 与各栈具体桥实现之间。

#### 4.4.2.3 公共依赖与组件清单

按是否栈相关分组：

| 组件 | 角色 | CDK | OP | XJST |
|------|------|-----|-----|------|
| `*_pipe.sh` | 编排入口 | cdk_pipe.sh | op_pipe.sh | xjst_pipe.sh |
| L2 节点 | 链本体 | Kurtosis(cdk-erigon, cdk-node, zkevm-prover) | Kurtosis(op-node, op-geth, op-batcher, op-proposer) | conflux-rust(xjst 模式) |
| `jsonrpc-proxy` | L1 RPC 适配层 | 每链独立一实例 | 所有 OP 链共享一实例 | ✗ |
| claim-service | 跨链消息中继 | `zk-claim-service` | `op-claim-service` | ✗（直 bridge） |
| `ydyl-console-service` | 元数据 HTTP API | ✓ | ✓ | ✓ |
| `ydyl-gen-accounts` | 大规模用户账户生成与充值（10 亿级验收指标的承载者） | ✓ | ✓ | ✓ |
| PM2 | Node 服务进程管理 | ✓ | ✓ | ✓ |

> **`ydyl-gen-accounts` 的角色**：基于 Hardhat/TS 的批量账户生成器，按 deterministic 规则（EVM 链用 chainID + index、XJST 用 groupID + index）派生私钥并发起 L2 充值。每条链在 step9 调用一次，承担"为该链产出 N 个可用测试账户"的职责。100 条链汇总后承担"全网 ≥10 亿账户"的规模化验收目标——这一指标使 `ydyl-gen-accounts` 不能视为可选辅助，而是与 L2 节点本体并列的核心组件。

> 这张表是 4.4.3 详解每条流水线的总览索引。

#### 4.4.2.4 总体架构图（待画）

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

L1（Conflux eSpace）作为外部依赖，由所有节点共享接入。`L1_BRIDGE_HUB_CONTRACT` 是 100 条链唯一全局单点。

---

### 4.4.3 三类侧链流水线的服务与流程（~6 页，主体章节）

#### 4.4.3.1 公共骨架：12 步流水线五阶段抽象

CDK/OP/XJST 三条流水线共享同一组 step 编号（XJST 因 L1 合约部署引入语义重排），核心骨架抽象为五个阶段：

| 阶段 | 步骤 | 共性目的 |
|------|------|----------|
| ① 身份与资金准备 | step1 初始化密钥、step2 L1 充值 | 部署者 / claim-service / L2 部署者三类账户从 L1 vault 充值 |
| ② L1 接入层 | step3 启 jsonrpc-proxy（XJST：部 L1 合约） | 解决 4.2 节 L1 兼容性 / 部署本链 L1 合约 |
| ③ L2 部署 | step4 拉起 L2 节点、step5 L2 充值 | 链本体与 L2 测试钱包就绪 |
| ④ 跨链中继与桥注册 | step6 生成 .env、step7 部 Counter + 注册 bridge、step8 启 claim-service | 把单链转化为可互操作侧链 |
| ⑤ 元数据与可观测 | step9 批量账户、step10 元数据归档、step11 console-service、step12 PM2 巡检 | 为下游压测与控制平面查询提供契约 |

> 三条流水线的差异主要落在阶段 ②③④。

#### 4.4.3.2 OP Rollup 流水线（本节较 4.4.3.3 更详细）

**部署的服务清单**：

1. **全栈共享 `jsonrpc-proxy`**：所有 OP 链共享同一个代理实例，由控制平面在独立位置部署一次，所有 OP 链的 `L1_RPC_URL` 均指向该实例
2. Kurtosis 启动的 OP Stack（每链一套）：`op-node`（derivation + sequencer 协调）、`op-geth`（执行客户端）、`op-batcher`（calldata 提交）、`op-proposer`（output root 提交）
3. `op-claim-service`（PM2，每链一套）：监听 L2 出口消息，构造 output root + Merkle proof 并在 L1 中继
4. `ydyl-gen-accounts`（每链一次性运行）：在 step9 批量生成与充值测试账户

**关键步骤深入**：

- **step3 共享 proxy 接入**：step3 不是"每条 OP 链各起一个 proxy"，而是"确保共享 proxy 已就绪并把其地址注入后续步骤"。共享的根因来自 4.2 节 C1：proxy 对 OP 节点做 block hash 修正时，必须从同一起始 block 进入 derivation 才能保证修正后的 hash 在所有 OP 节点之间一致；若每条 OP 链各起独立 proxy，不同 proxy 的起始 block 不一致会导致同一 L1 区块在不同 OP 链上呈现不同 hash，跨 OP 链的 L1 引用一致性基础失效。
- **step4 `step4_deploy_kurtosis_op`**：通过 `optimism-package` 调用 OP Stack 部署；出块时间设为 1s 以缓和 4.2 C3 的 L1 origin drift；batcher 强制 calldata 模式以规避 EIP-4844 缺失。
- **step6 → step7 → step8 跨链链路**：step6 从 `op-work/output/` 读取 L2 部署 key、claim-service EOA、bridge 注册参数，渲染出 `op-claim-service/.env` 与 `.env.counter-bridge-register`；step7 调用 Counter 部署与 bridge 注册（详见 4.4.3.5）；step8 通过 PM2 启动 `op-claim-service`，进入"事件监听 → proof 构造 → L1 中继"循环。

**论证：OP 共享 proxy 与 CDK 独立 proxy 的根本差异**：

> OP 的 block hash 修正是**有状态**的——proxy 需要从某个起始 block 开始维护原始 hash 与修正后 hash 的映射关系，所有 OP 节点都查询同一个映射表才能保证 derivation 引用一致。两个独立 proxy 即便实现完全相同，只要起始 block 不同，对历史区块的修正结果就可能分叉，OP 跨链消息验证会失败。
>
> CDK 不在代理层做 hash 修正——4.2 节论证 CDK 的 hash 冲突由 `sync/evmdownloader.go` 的内核侧改造解决，代理只承担无状态的 RPC 转发与高 gasLimit 下的 gas price 补偿。无状态意味着代理实例之间无须协调，每链独立部署反而避免了单点瓶颈。
>
> 这两种代理拓扑对部署架构的影响是直接的：OP 的共享 proxy 是 100 链拓扑中除 `L1_BRIDGE_HUB_CONTRACT` 之外的第二个全局点；CDK 则没有此类全局点，代理与节点 1:1 同生命周期。

**OP 链 step9 的账户生成**：每条 OP 链通过 `ydyl-gen-accounts` 的 `l2type=0`（EVM 类）+ chainID 派生路径生成测试账户并完成 L2 充值，单链账户量是 10 亿级总验收指标按 100 链摊分后的份额。

#### 4.4.3.3 CDK Rollup 流水线（精简）

**部署的服务清单**（本链节点本机）：

1. `jsonrpc-proxy`（**本链独立**一实例，PM2 进程，承担 RPC 转发与高 gasLimit 下的 gas price 补偿；CDK 的 block hash 校验冲突由内核侧解决，代理无需做 hash 适配，故无跨链协同需求）
2. Kurtosis 启动的 CDK 容器栈：`cdk-erigon`（执行节点）、`cdk-node`（sequencer + aggregator）、`zkevm-prover`（ZK proof 生成）、本链 L1 合约部署
3. `zk-claim-service`（PM2，监听 L2 跨链事件，拉 ZK proof 后到 L1 提 claim）
4. `ydyl-gen-accounts`（每链一次性运行）

**关键步骤要点**：

- **step3** 在本机拉起本链专属代理，将 `L1_RPC_URL` 改写为代理地址注入后续步骤
- **step4 `step4_deploy_kurtosis_cdk`** 通过 `kurtosis run` 调起 `cdk-work/scripts/deploy.sh`；与 OP 共享 Kurtosis 但 package 不同
- **step6 → step7 → step8** 与 OP 同型异构：渲染 `zk-claim-service/.env` → 部署 Counter + 注册 bridge → 启动 `zk-claim-service`

**与 OP 的关键差异**：

- **代理拓扑**：CDK 每链独立一个 proxy（已在 4.4.3.2 论证）
- **跨链证明形态**：CDK 走 ZK proof，`zk-claim-service` 用 hardhat + ZK prover RPC；OP 走 Merkle proof，`op-claim-service` 用纯 JS 计算
- **资源消耗**：CDK 单节点最重（多容器 + ZK prover），机型选择不同——驱动 4.4.4 的 `services[]` 差异化配置

#### 4.4.3.4 XJST 联盟链侧链流水线

XJST 是与 CDK/OP 形态最不同的一栈，本节是 4.4.3 中最有深度的子节。

**部署的服务清单**：

1. **L1 合约**（仅本链 node-1 执行）：`step3_deploy_l1_contracts` 部署该链专属的 `simple_calculator` / `state_sender` / `unified_bridge`
2. XJST 节点本体（`conflux-rust` 的 xjst 模式，每节点一进程）
3. **不需要** jsonrpc-proxy 与独立 claim-service——XJST 直接用 bridge 合约对账

**节点角色分化**：

> 一条 XJST 链由若干节点构成（node-1、node-2、…）。
>
> - **node-1（本链）** 在该链内部承担三项独占职责：
>   1. **step3 部署该链专属的 L1 合约**（`simple_calculator`、`state_sender`、`unified_bridge`），通过 `xjst-work/docker_builder/deploy_l1_contracts.py` 执行
>   2. **step9 在该链 L2 上部署 Counter，并把该链的 `unified_bridge` 与 `state_sender` 注册到全局共享的 `L1_BRIDGE_HUB_CONTRACT`**（注意 `BRIDGES` 是数组，注册的是该链自己的两个桥合约）
>   3. 通过 `ydyl-console-service` 的 `/v1/result/node-deployment-contracts/xjst/l1` 接口对外暴露 L1 合约地址，供同链其它节点拉取
> - **node-2..node-N（同链非 node-1 节点）**：仅启动 XJST 节点。在 step5（`step5_deploy_xjst_node`）调用 `get_l1_deploy_contracts` 从同链 node-1 拉到 `L1_STATE_SENDER_ADDR`、`L1_UNIFIED_BRIDGE_ADDR`、`L1_START_EPOCH` 后，以 `AUTO_DEPLOY_L1_CONTRACTS=false` 启动节点。

**节点协同图**：

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

**论证式讨论**：

> **`step_wait_for_other_nodes_to_start` 的实现与必要性**：
> node-1 通过 `xjst-work/js-scripts/checkNodePeers.js` 轮询同链其它节点的 P2P 连通性，确认 L2 网络稳定后再进入桥注册步骤。若不等待，桥注册成功后 L2 网络可能仍处于不稳定状态，下游跨链消息流转会失败。

#### 4.4.3.5 Counter 部署与桥注册（三栈共用环节）

step7（XJST 中编号为 step9）是三栈唯一在流程位置与语义上完全一致的步骤，承担把单链转化为可互操作侧链的关键动作。本节单列因为它是异构侧链可互通的根本机制——所有跨栈差异在桥实现层面消化完毕，到了注册层面则统一接入同一全局合约。

**两个动作合一**：

1. **L2 端部署 Counter 合约**：调用 `zk-claim-service/scripts/i_deployCounterAndRegisterBridge.js`（被三栈共用，名字带 zk 仅是历史命名），在本链 L2 上部署 Counter 测试合约，作为后续跨链调用的目标
2. **L1 端注册桥到 BridgeHub**：在同一脚本内调用 `L1_BRIDGE_HUB_CONTRACT` 的 `addBridgeService` 方法，把本链的桥合约地址注册到全局 hub 中

**输入参数（来自 step6 渲染的 `.env.counter-bridge-register`）**：

| 字段 | OP | CDK | XJST |
|------|----|----|------|
| `BRIDGES`（可数组） | OP 标准桥合约 | CDK 标准桥合约 | `unified_bridge`, `state_sender` |
| `L1_BRIDGE_HUB_CONTRACT` | 全局共享地址 | 全局共享地址 | 全局共享地址 |
| `L1_REGISTER_BRIDGE_PRIVATE_KEY` | 全局注册者 EOA | 全局注册者 EOA | 全局注册者 EOA |
| `L2_PRIVATE_KEY` | 本链 L2 部署 key | 本链 L2 部署 key | 本链 L2 部署 key |
| `L2_TYPE` | 0 | 1 | 2 |

`BRIDGES` 是逗号分隔数组（也可通过 CLI `--bridges 0x... --bridges 0x...` 重复传参），这一设计正是为了支持 XJST 同时注册两个桥合约的形态。

**为什么所有桥都注册到同一 BridgeHub**：

> 每条链的桥实现合约只感知该链的 L2 状态根、出口消息与流动性，按链独立避免跨链状态污染；而 `BridgeHub` 不持有任何链状态，仅作为"哪条链的哪个桥地址在哪 / `L2_TYPE` 是什么"的注册表与跨链路由入口，因此可以也必须全局唯一——否则不同链注册到不同 hub 时跨链消息无法路由。`addBridgeService` 调用本质是把"链类型 + 链 ID + 该链桥地址"三元组写入全局注册表，下游 4.5 节的跨链消息协议正是基于此表完成路由解析。

**节点角色约束**（仅 XJST 有此约束）：

CDK/OP 由本链节点（部署 Counter 后立即注册）执行 step7；XJST 由本链 node-1 在 step9 单独执行 `step7_deploy_counter_and_register_bridge_if_node1`，非 node-1 节点跳过——根因是 96 节点（注：以单条 XJST 链内多节点为例）共享同一组 L1 桥合约，重复注册会造成 hub 表中同一桥地址多次出现。

#### 4.4.3.6 三栈对照表

最后用一张对照表收束本章：

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

> 这张表是 4.4 章承上启下的关键——下一节 4.4.4 介绍 deploy-client 时，正是基于这张表把"差异"压缩进 `services[].remoteCmd`。

---

### 4.4.4 ydyl-deploy-client 编排链路（~1.5 页）

不展开实现细节，仅交代"五类命令如何串成压测前的完整链路"：

1. **`deploy`**：按 `config.deploy.yaml` 中 `services[]` 批量起 EC2 + 等 SSH + 派发对应的 `*_pipe.sh`（每类侧链对应一段 `remoteCmd`）。失败按节点级落入 `script_status.json`。
2. **`deploy-restore`**：仅对 `failed` 状态的节点重派 `*_pipe.sh`；流水线本身的 `START_STEP` 续跑机制保证不重做已完成的步骤——这是控制平面 × 数据平面双层续跑的复合。
3. **`gen-cross-tx-config`**：扫 `servers.json`，向每节点的 `ydyl-console-service` 拉取链元数据（chainID、L2 RPC、Counter、bridge），笛卡尔积成 100×99 的跨链 jobs，按 8 路均分。
4. **`bench-cross-tx`**：把 jobs 喂给 `ydyl-bench-docker` 的 8 个 multijob 容器，每容器跑 `7s_multijob.js` 发交易。
5. **`tps`**：单独起 `h_TPSjob.js` 容器，按 `--block-range` 监控全链路 TPS。
6. **`collect-logs`** / **`stats-logs`**：部署后收集远端 pipe / Kurtosis 部署 / 运行期日志并统计行数与大小（详见 [`2026-06-10-deploy-client-log-collection-spec.md`](2026-06-10-deploy-client-log-collection-spec.md)）。

> 篇幅控制要点：每个命令一段，给输入/输出/职责，不展开实现细节。

---

### 4.4.5 规模化部署验证（~1.5 页）

按写作指南 4.3 节"用数据说话"，给出完整测试环境与可对比数据：

- **环境**：EC2 机型矩阵（XJST/CDK/OP 各自规格）、region/AZ、AMI 版本、L1 接入点
- **耗时分布**：每类侧链单条部署耗时 P50/P95；100 条并发的总墙钟耗时
- **首跑成功率与 deploy-restore 后最终成功率**：分栈给出，按失败 root cause 归类（Kurtosis 启动超时 / SSH / L1 充值失败 / bridge 注册超时等）
- **元数据完整性**：100 条链中 `ydyl-console-service` 健康的比例、`gen-cross-tx-config` 成功生成 jobs 的比例
- **跨链可达性**：随机抽 N 对侧链发起 Counter 跨链调用，观察成功率与端到端延迟（呼应 4.6 节）

---

### 4.4.6 局限与展望（~0.5 页）

- 一机一链的资源开销随规模线性增长，未做多租户压缩
- 控制平面单点（运行 deploy 的开发机）；中断后通过 `script_status.json` + `servers.json` 可重建，但缺自动 leader 切换
- **OP 共享 `jsonrpc-proxy` 是除 `L1_BRIDGE_HUB_CONTRACT` 之外的第二个全局点**：proxy 实例失效会同时影响所有 2 条 OP 链的 derivation；当前未做 proxy 高可用，恢复依赖手工重启与 derivation 自愈
- 每条 XJST 链的 node-1 在 step3 是该链内部的单点：node-1 失败会卡住该链其余节点的 step5（无法获取 L1 合约地址）。但故障爆炸半径限于单链，不会传播到其它 XJST 链或 CDK/OP 链
- 跨 region/AZ 部署下 L2 head 对 L1 head 的滞后量会随时间累积，需要从机型/链路两侧共同优化

---

## 四、写作纪律检查清单

写作前 / 写作中按以下要点自查：

1. **原创工作占比 ≥85%**：背景介绍只在 4.4.1 出现，不教学 EC2 / Kurtosis / PM2 等公共知识。
2. **论证式而非导游式**：每个关键设计（双平面分离、Kurtosis 选型、XJST 节点协同、L1 合约共享边界）都必须有"设计空间 → 选择论证 → 代价"的完整链条。
3. **数据替代评价**：4.4.5 必须给出实测数据；避免"高吞吐"、"显著提升"等评价性虚词。
4. **段落承载论述**：4.4.2 / 4.4.3.4 的论证段必须用段落，不退化为 bullet 罗列。
5. **章节衔接**：4.4.2 → 4.4.3 必须由"组件清单"自然导入"流水线展开"；4.4.3 → 4.4.4 必须由"三栈对照表"自然导入"deploy-client 如何抽象差异"。
6. **不重复 4.2 内容**：jsonrpc-proxy / 哈希修正 / FloorDataGas 等只点到为止并引用 4.2，不重述。
7. **不混入项目管理信息**：不写"待 XX 部署"、"需与 XX 确认"等。

---

## 五、待确认事项

写作启动前需对齐：

1. **4.4.3.2 / 4.4.3.3 Kurtosis 内部容器列表的精确版本号**：需 grep `cdk-work/` 与 `optimism-package/` 实际配置后确定。
2. **4.4.5 实测数据来源**：是从已有 100 链部署日志中提取，还是写作前先跑一轮采样。
3. **OP 共享 `jsonrpc-proxy` 的部署位置**：是放在某台 OP 节点机器上、独立 EC2 上、还是控制平面机上。这决定 4.4.5 中"全局点"的物理形态与故障域。
4. **4.4.5 跨链可达性测试**：与 4.6 节如何分工——4.4 给出的是"部署完成的链是否可互通"，4.6 给出的是"互通的性能与正确性"。

---

## 六、产物对应关系

- 本 spec：`docs/superpowers/specs/2026-05-07-multi-sidechain-bulk-deployment-spec.md`
- 写作产物：`doc-report/4.4-multi-sidechain-bulk-deployment.md`（待写）
- 上游依赖 spec：`docs/superpowers/specs/2026-05-06-rollup-sidechain-integration-spec.md`（4.2 节）

写作产物与本 spec 的一致性按项目"spec 是真理之源"约定维护：需求/设计变更先改本 spec，再改产物；纯实施细节可改产物但完成后扫一遍 spec 确认仍一致。
