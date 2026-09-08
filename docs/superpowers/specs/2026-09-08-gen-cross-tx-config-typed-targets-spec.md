# gen-cross-tx-config 分池目标与 wallet_amount 默认值

覆盖 [2026-09-07 unique-targets spec](2026-09-07-gen-cross-tx-config-unique-targets-spec.md) 中的「op/cdk/xjst 可互跨」与「禁止 XJST 自指」。池内 uniqueness（n≥2 时源 ≠ 目标、每个实例作 target 恰好一次）仍然有效。

## 背景

压测桥接约束：XJST 跨链目标必须是 XJST；OP/CDK 只能打 OP 或 CDK。全体链 derangement 会生成 `op → xjst` 这类非法边。单实例池（例如只有 1 条 xjst）必须允许自指，否则无法生成 job。

`--wallet-amount` 默认 100 过大，默认改为 10。

## 目标

- 每条参与链（`PickChainEntries` 结果）生成 **1 条** job
- 目标按链类型分两个独立池分配：
  - **xjst 池**：源只能打 xjst
  - **rollup 池**（op + cdk）：源只能打 op 或 cdk
- 每个非空池独立做 uniqueness：
  - `n == 0`：跳过
  - `n == 1`：自环（`assignment[k] = k`）
  - `n >= 2`：Fisher–Yates + 环移 1（池内源 ≠ 目标，池内每个实例作 target 恰好一次）
- `--wallet-amount` CLI 默认值为 **10**
- 不新增 CLI 参数
- `GenerateWithFetcher` 最少 **1** 条参与链（单链自指合法）

## 非目标

- 不改 `PickChainEntries`
- 不改 job 字段映射（除目标链选择与 CLI 默认值外）
- 不把 `WaitForReceipts` 改成按目标链类型：仍按源链类型（xjst 源为 false）
- 不改写已生成的 `output/jobs/*.json`（重新跑命令后才会覆盖）
- 不改写 `2026-05-07` 报告提纲里的「笛卡尔积 100×99」措辞

## 分配规则

`GenerateJobs` 先调用 `assignTargetsByType(chainKeys, infos)` 得到 `sourceName -> targetName`：

1. 按 `infos[key].Type` 分成 xjst 与 op|cdk；未知类型失败
2. 每个非空池独立调用 `assignUniqueTargets`
3. 合并两池 assignment 后按原 `chainKeys` 顺序生成 job

`assignUniqueTargets`：

1. `n == 0`：返回空 map
2. `n == 1`：自环
3. `n >= 2`：复制 keys，Fisher–Yates + `crypto/rand` 洗牌；环移 1：`assignment[shuffled[i]] = shuffled[(i+1)%n]`；洗牌失败时回退为对已排序 keys 做同样环移

典型 1 op + 1 cdk + 1 xjst：

- `op ↔ cdk`
- `xjst → xjst`

## 保持不变的映射

- `WaitForReceipts`：`source.Type != "xjst"`
- `target.Type == "xjst"` 时 `TargetL1Bridge` 使用 `L1BridgeSendContract`，否则 `L1BridgeReceiveContract`
- 全部 job 共用一次生成的 12-word mnemonic

## CLI

`--wallet-amount` 默认 `10`。显式传参行为不变。

`gen-cross-tx-config` 的 `Long` 说明：xjst 只打 xjst，op/cdk 只打 op/cdk，单实例可自指。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig.go` | `assignTargetsByType`；`assignUniqueTargets` 支持 n=0/1；最少 1 条链 |
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig_test.go` | 分池、自指、池内 uniqueness |
| `ydyl-deploy-client/cmd/gen_cross_tx_config.go` | `--wallet-amount` 默认 10；更新 `Long` |

## 用法

```bash
cd ydyl-deploy-client
go run . gen-cross-tx-config --servers ./output/servers.json --config ./config.deploy.yaml
```
