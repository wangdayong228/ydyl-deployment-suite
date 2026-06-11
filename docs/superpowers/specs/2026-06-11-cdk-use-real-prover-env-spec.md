# CDK 流水线：`USE_REAL_PROVER` 环境变量

## 背景

[`2026-05-14-real-prover-in-kurtosis`](2026-05-14-real-prover-in-kurtosis.md) 已在 kurtosis-cdk 侧支持通过 `params.yml` 切换真实 / mock 证明。当前 `cdk-work/scripts/params.template.yml` 中三个相关字段仍为硬编码：

```yaml
zkevm_use_real_verifier: true
zkevm_use_real_prover_client: false
zkevm_use_mock_prover_client: true
```

运维在批量部署或流水线续跑时，需要改模板或手工编辑渲染后的 `params-*.yml`，不便与 `cdk_pipe.sh` / `ydyl-deploy-client` 的环境变量风格统一。

## 目标

- 用单一环境变量 `USE_REAL_PROVER`（`true` / `false`）控制 Kurtosis 部署参数中的 verifier / mock prover 模式
- 通过现有 `envsubst` 机制注入，不引入新工具链
- 默认值保持与当前模板一致（`USE_REAL_PROVER=true`：真实 verifier、不启动 mock prover 容器）
- `USE_REAL_PROVER` 仅接受小写 `true` / `false`；非法值直接失败，避免渲染出非布尔 YAML

## 非目标

- 不修改 kurtosis-cdk 包内逻辑（已由 2026-05-14 spec 覆盖）
- 本阶段不启用 `zkevm_use_real_prover_client`（700GB+ RAM 真实证明生成），该字段固定为 `false`
- 本阶段不强制改 `ydyl-deploy-client` 远程命令拼接（可后续按需加配置项）

## 变量映射

| 环境变量 | 来源 | 写入 `params.template.yml` |
|---------|------|---------------------------|
| `USE_REAL_PROVER` | 用户 / 流水线，默认 `true` | `zkevm_use_real_verifier` |
| `USE_MOCK_PROVER` | 脚本内由 `USE_REAL_PROVER` 取反，不对外暴露 | `zkevm_use_mock_prover_client` |

`zkevm_use_real_prover_client` 固定为 `false`（本阶段不启用 Kurtosis 内真实证明生成）。

映射关系（结合 kurtosis-cdk 启动条件：`not zkevm_use_real_verifier or zkevm_use_real_prover_client` 时才启动 prover 容器）：

| `USE_REAL_PROVER` | `zkevm_use_real_verifier` | `zkevm_use_real_prover_client` | `zkevm_use_mock_prover_client` | prover 容器 |
|-------------------|---------------------------|--------------------------------|--------------------------------|-------------|
| `true`（默认）    | `true`                    | `false`                        | `false`                        | 不启动      |
| `false`           | `false`                   | `false`                        | `true`                         | 启动（mock）|

语义：

- `USE_REAL_PROVER=true`：合约侧使用真实 verifier，不部署 mock prover 服务
- `USE_REAL_PROVER=false`：部署 mock zkevm-prover 服务，并启用 mock 证明客户端

## 涉及文件

| 文件 | 改动 |
|------|------|
| `cdk-work/scripts/params.template.yml` | 三处硬编码改为 `$USE_REAL_PROVER` / `false` / `$USE_MOCK_PROVER` |
| `cdk-work/scripts/prover_env.sh` | 集中解析、校验并导出 `USE_REAL_PROVER` 与 `USE_MOCK_PROVER` |
| `cdk-work/scripts/deploy.sh` | 在 `prepare_cdk_env` 中调用公共解析函数 |
| `cdk_pipe.sh` | 头部注释补充可选变量；`PERSIST_VARS` 与一致性校验加入 `USE_REAL_PROVER` 以支持续跑 |
| `cdk-work/scripts/prover_env.test.sh` | 覆盖默认值、显式值、非法值、模板渲染和父流程一致性挂钩 |

## 详细设计

### 1. `params.template.yml`

```yaml
  zkevm_use_real_verifier: $USE_REAL_PROVER
  zkevm_use_real_prover_client: false
  zkevm_use_mock_prover_client: $USE_MOCK_PROVER   # USE_REAL_PROVER 取反
```

保留原有中文注释，说明 true 时跳过 mock prover；`zkevm_use_real_prover_client` 本阶段固定 false。

### 2. `prover_env.sh` — 公共解析函数

集中处理默认值、严格布尔校验和 mock 取反：

```bash
USE_REAL_PROVER="${USE_REAL_PROVER:-true}"
case "$USE_REAL_PROVER" in
  true) USE_MOCK_PROVER="false" ;;
  false) USE_MOCK_PROVER="true" ;;
  *) echo "错误: USE_REAL_PROVER 只能设置为 true 或 false" >&2; return 1 ;;
esac
export USE_REAL_PROVER USE_MOCK_PROVER
```

### 3. `deploy.sh` — `prepare_cdk_env`

在生成 `L2_CONFIG` 之前调用 `resolve_cdk_prover_env`，确保直接执行 `cdk-work/scripts/deploy.sh` 也有相同行为。

`envsubst` 由 `ydyl-scripts-lib/deploy_common.sh` 的 `ydyl_kurtosis_deploy` 调用，无需改动。

### 4. `cdk_pipe.sh`

- 可选环境变量说明增加：`USE_REAL_PROVER: 是否使用真实 verifier 并跳过 mock prover（默认 true）`
- `record_input_vars` 记录用户显式传入的 `USE_REAL_PROVER`
- `check_env_compat` 对 `USE_REAL_PROVER` 做续跑一致性校验，避免同一 state 下静默切换 prover 模式
- `PERSIST_VARS` 增加 `USE_REAL_PROVER`，避免 step4 续跑时丢失用户选择
- 在父 shell 中调用 `resolve_cdk_prover_env`，让默认值也写入 `output/cdk_pipe.state`

`step4_deploy_kurtosis_cdk` 无需改代码：子进程继承父 shell 已解析并导出的环境变量即可。

## 使用方式

```bash
# 真实 verifier、不启动 mock prover（默认，与改前模板行为一致）
./cdk_pipe.sh

# 启动 mock prover 服务（开发 / 本地证明）
USE_REAL_PROVER=false ./cdk_pipe.sh
```

## 验收标准

1. 未设置 `USE_REAL_PROVER` 时，渲染后的 `params-<network>.yml` 中三字段为 `true` / `false` / `false`
2. `USE_REAL_PROVER=false` 时，渲染结果为 `false` / `false` / `true`
3. `cdk_pipe.sh` 续跑时 `USE_REAL_PROVER` 从 `output/cdk_pipe.state` 恢复一致
4. `envsubst` 后无残留 `$USE_REAL_PROVER` / `$USE_MOCK_PROVER` 占位符
5. `USE_REAL_PROVER` 为非 `true` / `false` 值时，脚本失败且不渲染非布尔 YAML

## 关联 spec

- 上游：[`2026-05-14-real-prover-in-kurtosis`](2026-05-14-real-prover-in-kurtosis.md)（kurtosis-cdk 模板变量语义）
- 可扩展：[`2026-05-07-multi-sidechain-bulk-deployment`](2026-05-07-multi-sidechain-bulk-deployment-spec.md)（`ydyl-deploy-client` 远程 env 透传，后续迭代）
