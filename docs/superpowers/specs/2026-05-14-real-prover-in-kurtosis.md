# 方案二：Kurtosis 内启用真实 Prover

## 背景

当前 kurtosis-cdk 的 prover 模板（`templates/trusted-node/prover-config.json`）写死了 `runAggregatorClient: false` + `runAggregatorClientMock: true`，即只能生成假证明。本文档描述如何为 kurtosis-cdk 增加真实 prover 支持，使其成为用户可切换的模式。

## 目标

- 新增两个模板变量，控制 prover 运行模式
- 用户只需在自己的 `params.yml` 中设置标志位即可切换真实/mock 证明
- 兼容现有默认行为（不改用户配置则仍然 mock）

## 涉及文件

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `kurtosis-cdk/input_parser.star` | 新增默认值 | 两个新变量的默认值 |
| `kurtosis-cdk/templates/trusted-node/prover-config.json` | 修改模板 | 硬编码 → 模板变量 |
| `kurtosis-cdk/cdk_central_environment.star` | 修改启动条件 | 真实 prover 模式也启动 prover 服务 |
| `cdk-work/scripts/params.template.yml` | 新增示例配置 | 用户参考 |

## 详细设计

### 1. `input_parser.star` — 新增默认值

在 `zkevm_use_real_verifier`（第 316 行）之后增加两个变量：

```python
# Set to true to run the prover with real proof generation (runAggregatorClient).
# Requires 700GB+ RAM on the Kurtosis host. When false, mock proofs are used.
"zkevm_use_real_prover_client": False,
# Set to false when zkevm_use_real_prover_client is true (mutually exclusive).
"zkevm_use_mock_prover_client": True,
```

默认值保持 mock 模式（`real_prover_client: false, mock: true`），完全兼容现有行为。

### 2. `prover-config.json` — 模板化

**第 72 行**：`runAggregatorClient` 从硬编码改为模板变量：

```
# 改前
"runAggregatorClient": false,

# 改后
"runAggregatorClient": {{.zkevm_use_real_prover_client}},
```

**第 81-85 行**：`runAggregatorClientMock` 保留 `stateless_executor` 守卫，非 stateless 路径改用模板变量：

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

`stateless_executor` 路径保持不变（始终 `false`，因为 stateless executor 不生成证明）。非 stateless 路径由用户通过 `zkevm_use_mock_prover_client` 控制。

### 3. `cdk_central_environment.star` — 启动条件

当前逻辑（第 30-37 行）：只有 `zkevm_use_real_verifier == false` 时才启动 prover 容器。真实 verifier 场景下 prover 完全不被启动（预留给方案一的独立部署）。

改为：`zkevm_use_real_prover_client == true` 时也启动 prover：

```python
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

启动逻辑：prover 容器始终启动（与之前一样走 `zkevm_prover_package.start_prover`），行为由 `prover-config.json` 中的 `runAggregatorClient` / `runAggregatorClientMock` 控制。

### 4. `params.template.yml` — 用户配置示例

```yaml
args:
  # 启用真实证明生成（需要 700GB+ RAM 主机）
  zkevm_use_real_prover_client: false   # 改为 true 启用
  zkevm_use_mock_prover_client: true    # 改为 false 关闭 mock
```

## 用户使用方式

```yaml
# 在用户自己的 params.yml 中：
args:
  zkevm_use_real_prover_client: true
  zkevm_use_mock_prover_client: false
```

然后照常执行 `bash cdk_pipe.sh`，prover 在 Kurtosis 内启动并连接 cdk-node aggregator 生成真实证明。

## 兼容性

- 不传这两个变量 → 默认 `real_prover_client: false` + `mock: true`，与现有行为完全一致
- 仅当用户显式设置 `zkevm_use_real_prover_client: true` + `zkevm_use_mock_prover_client: false` 时才启用真实证明

## 不在范围内

- 不修改 `zkevm_prover_package.start_prover` 函数本身——prover 容器的启动方式不变，变的是传入的配置内容
- 不修改 prover 镜像——仍然使用 `zkevm_prover_image` 指定的镜像
- 不处理 700GB 内存主机的 provision——这是部署层面的问题
