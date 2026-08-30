# XJST `ENABLE_BRIDGE` 开关 + step2 L1 目标金额可配置

## 背景

XJST 流水线在主链测试时，用户可能只需部署侧链节点并运行 `ydyl-gen-accounts`，不需要 L1 跨链注册（Counter + `bridgeHub.addBridgeService`）及 step2 的大额 L1 补余额。

同时，三条流水线共用的 `step2_fund_l1_accounts` 将 vault / claim-service / register-bridge 的目标余额硬编码为 5000 / 1000 / 1000 ether，主链或测试环境需要可配置。

## 目标

### XJST 专属：`ENABLE_BRIDGE`

- 可选环境变量，默认 `true`（与现有行为一致）
- 只接受 `true` / `false`
- `false` 时 node-1 跳过：step2 L1 转账、step8 写 bridge env、step9 Counter/bridge 注册、step11 metadata 收集
- 仍执行：部署 L1 合约、节点、L2 充值、gen-accounts 等
- `false` 时 `L1_BRIDGE_HUB_CONTRACT`、`L1_REGISTER_BRIDGE_PRIVATE_KEY` 非必填
- 不写入 `PERSIST_VARS`，不做 `check_input_env_consistency`（与 `ENABLE_GEN_ACC` 相同）

### 全局：step2 L1 目标金额

在 `ydyl-scripts-lib` 中增加三个环境变量，CDK / OP / XJST 共用，无链类型分支：

| 环境变量 | 默认 | 收款地址 |
|----------|------|----------|
| `L1_FUND_VAULT_ETH` | `5000` | `KURTOSIS_L1_FUND_VAULT_ADDRESS` |
| `L1_FUND_CLAIM_SERVICE_ETH` | `1000` | `CLAIM_SERVICE_ADDRESS` |
| `L1_FUND_REGISTER_BRIDGE_ETH` | `1000` | `L1_REGISTER_BRIDGE_ADDRESS` |

- 非负整数（ether）；`0` 跳过该笔
- 仍使用 `fund_eth_up_to` 差额补足语义
- 不写入 `PERSIST_VARS`，不做一致性校验

## 非目标

- 不改 `cdk_pipe.sh` / `op_pipe.sh` 的 `run_all_steps`
- 不改共享 `step7` / `step5_fund_l2_accounts` / `step10_collect_metadata` 本体（XJST 用 `skip_step` 绕过）
- `ydyl-deploy-client` 全局 yaml 增加 `l1FundVaultEth` / `l1FundClaimServiceEth` / `l1FundRegisterBridgeEth`（省略则不透传，pipe 用默认；`0` 跳过该笔）；三条内置 remoteCmd 均透传。XJST 另透传 `ENABLE_BRIDGE`

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-scripts-lib/utils.sh` | `require_non_negative_int_env` |
| `ydyl-scripts-lib/pipeline_steps_lib.sh` | `step2_fund_l1_accounts` 读三笔金额 |
| `ydyl-scripts-lib/utils.test.sh` | helper 测试 |
| `xjst_pipe.sh` | `ENABLE_BRIDGE`、`run_bridge_step`、`require_inputs` |
| `README.md` | 文档 |
| `ydyl-deploy-client/internal/deploy/config.go` | `EnableBridge *bool`、三笔 `L1Fund*Eth *int` |
| `ydyl-deploy-client/internal/deploy/deploy.go` | XJST 透传 `ENABLE_BRIDGE`；三条 pipe 透传 `L1_FUND_*_ETH` |

## 用法示例

```bash
# 主链只测 gen-accounts
ENABLE_BRIDGE=false ENABLE_GEN_ACC=true NODE_ID=node-1 ./xjst_pipe.sh

# 少打 L1 钱但仍跑跨链
L1_FUND_VAULT_ETH=2 L1_FUND_CLAIM_SERVICE_ETH=1 L1_FUND_REGISTER_BRIDGE_ETH=1 ./xjst_pipe.sh
```
