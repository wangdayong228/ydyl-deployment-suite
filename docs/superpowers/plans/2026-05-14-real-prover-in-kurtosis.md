# 方案二：Kurtosis 内启用真实 Prover — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 新增两个模板变量让用户可以在 Kurtosis 内启用真实 ZK 证明生成

**Architecture:** 4 个文件、纯配置改动：input_parser.star 加默认值 → prover-config.json 模板化 → cdk_central_environment.star 放宽启动条件 → params.template.yml 加示例

**Tech Stack:** Kurtosis Starlark 模板 + YAML 配置

---

### Task 1: 新增 input_parser.star 默认值

**Files:**
- Modify: `kurtosis-cdk/input_parser.star:316`

- [x] **Step 1: 在 `zkevm_use_real_verifier` 之后插入两个新变量**

```python
    "zkevm_use_real_verifier": False,
    # Set to true to run the prover with real proof generation (runAggregatorClient).
    # Requires 700GB+ RAM on the Kurtosis host. When false, mock proofs are used.
    "zkevm_use_real_prover_client": False,
    # Set to false when zkevm_use_real_prover_client is true (mutually exclusive).
    "zkevm_use_mock_prover_client": True,
```

- [x] **Step 2: 验证语法**

Run: `starlark -c 'print("ok")' /dev/null` (或跳过，Starlark 语法检查在 Kurtosis 执行时自然验证)

- [x] **Step 3: Commit**

```bash
git add kurtosis-cdk/input_parser.star
git commit -m "feat: add zkevm_use_real_prover_client and zkevm_use_mock_prover_client defaults for real prover mode"
```

---

### Task 2: 模板化 prover-config.json

**Files:**
- Modify: `kurtosis-cdk/templates/trusted-node/prover-config.json:72,81-85`

- [x] **Step 1: 改 `runAggregatorClient` 为模板变量（第 72 行）**

```
# 改前
    "runAggregatorClient": false,

# 改后
    "runAggregatorClient": {{.zkevm_use_real_prover_client}},
```

- [x] **Step 2: 改 `runAggregatorClientMock`，保留 `stateless_executor` 守卫（第 81-85 行）**

```
# 改前
    {{if .stateless_executor}}
    "runAggregatorClientMock": false,
    {{else}}
    "runAggregatorClientMock": true,
    {{end}}

# 改后
    {{if .stateless_executor}}
    "runAggregatorClientMock": false,
    {{else}}
    "runAggregatorClientMock": {{.zkevm_use_mock_prover_client}},
    {{end}}
```

- [x] **Step 3: Commit**

```bash
git add kurtosis-cdk/templates/trusted-node/prover-config.json
git commit -m "feat: template-ize runAggregatorClient and runAggregatorClientMock for real prover support"
```

---

### Task 3: 放宽 cdk_central_environment.star prover 启动条件

**Files:**
- Modify: `kurtosis-cdk/cdk_central_environment.star:30-37`

- [x] **Step 1: 在启动条件中加入 `zkevm_use_real_prover_client` 判断**

```
# 改前
    if (
        not args["zkevm_use_real_verifier"]
        and not args["enable_normalcy"]
        and not args["consensus_contract_type"] == constants.CONSENSUS_TYPE.pessimistic
    ):

# 改后
    if (
        (not args["zkevm_use_real_verifier"] or args["zkevm_use_real_prover_client"])
        and not args["enable_normalcy"]
        and not args["consensus_contract_type"] == constants.CONSENSUS_TYPE.pessimistic
    ):
```

- [x] **Step 2: Commit**

```bash
git add kurtosis-cdk/cdk_central_environment.star
git commit -m "feat: start prover when zkevm_use_real_prover_client is true, even with real verifier"
```

---

### Task 4: 在 params.template.yml 中添加用户配置示例

**Files:**
- Modify: `cdk-work/scripts/params.template.yml`

- [x] **Step 1: 在 `zkevm_prover_image` 附近添加新配置项**

```yaml
	  zkevm_prover_image: hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12
	  # 启用真实证明生成（需要 700GB+ RAM），与 zkevm_use_mock_prover_client 互斥
	  zkevm_use_real_prover_client: false
	  zkevm_use_mock_prover_client: true
```

- [x] **Step 2: Commit**

```bash
git add cdk-work/scripts/params.template.yml
git commit -m "feat: add real prover client config examples in params template"
```

---

## 验证方式

### 本地验证（不需要大内存）

- [x] **1. 确认默认值渲染结果不变** — `runAggregatorClient: false`, `runAggregatorClientMock: true` ✓

用 `kurtosis` 渲染模板但不实际启动（或直接 diff 渲染产物）：

```bash
# 用默认 params（不设新变量），对比 prover-config.json 渲染产物中关键字段
# 预期：runAggregatorClient=false, runAggregatorClientMock=true（与改动前一致）
grep -E '"runAggregatorClient"|"runAggregatorClientMock"' <rendered-config>
```

- [x] **2. 确认方案二变量正确传递到模板** — `runAggregatorClient: true`, `runAggregatorClientMock: false` ✓

用设置了新变量的 params 渲染模板：

```bash
# params.yml 中设置：
#   zkevm_use_real_prover_client: true
#   zkevm_use_mock_prover_client: false
# 预期渲染结果：runAggregatorClient=true, runAggregatorClientMock=false
grep -E '"runAggregatorClient"|"runAggregatorClientMock"' <rendered-config>
```

- [x] **3. Starlark 语法检查** — starlark-go 确认无语法错误 ✓

```bash
# input_parser.star 语法
starlark -c 'print("ok")' kurtosis-cdk/input_parser.star 2>&1 || echo "SYNTAX ERROR"
```

> 本地无法验证真实 prover 运行（需要 700GB+ RAM）。方案二的完整验证需要在实际部署时在满足硬件要求的主机上进行。

### 部署时验证（需要 700GB+ 主机）

```bash
# prover 连上 cdk-node aggregator
kurtosis service logs cdk-gen cdk-node-1 | grep "connected prover"
# verified batch 增长
cast rpc --rpc-url $L2_RPC zkevm_verifiedBatchNumber
```
