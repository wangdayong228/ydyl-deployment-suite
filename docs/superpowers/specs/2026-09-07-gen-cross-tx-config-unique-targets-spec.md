# gen-cross-tx-config target 不可重复

## 背景

`ydyl-deploy-client gen-cross-tx-config` 为每条参与链生成 1 条跨链 job。旧实现里每个源链独立随机选目标，多条源链可以打到同一条目标链；XJST 源链还被硬编码为指向自身，进一步放大重复。

压测需要每个目标链实例只承接一条入向跨链流。三种链类型（op / cdk / xjst）可以任意互跨，只要 target 不同。

## 目标

- 每条参与链（`PickChainEntries` 结果）生成 **1 条** job
- 目标分配是全体链实例的 **derangement**：源 ≠ 目标，且每个链实例作为 target **恰好 1 次**
- 唯一键是链实例（`servers.json` 的 `name`，job 上体现为互不相同的 `target_l2_rpc`），**不是** `target_l2_chain_type`
- 取消「XJST 源链固定指向自身」。XJST 可以作为别人的 target，也可以指向 OP/CDK
- 不新增 CLI 参数

## 非目标

- 不改 `PickChainEntries`（XJST 仍只取组内 node-1）
- 不改 job 字段映射（除目标链选择外）
- 不把 `WaitForReceipts` 改成按目标链类型：仍按源链类型（xjst 源为 false）
- 不改写 `2026-05-07` 报告提纲里的「笛卡尔积 100×99」措辞

## 分配规则

`GenerateJobs` 先调用 `assignUniqueTargets(chainKeys)` 得到 `sourceName -> targetName`：

1. 链数量 `< 2` 时失败（与 `Generate` 的「至少 2 条链」一致）
2. 复制 `chainKeys`，Fisher–Yates + `crypto/rand` 洗牌
3. 环移 1：`assignment[shuffled[i]] = shuffled[(i+1)%n]`
4. 洗牌失败时回退为对已排序 keys 做同样环移（仍保证 derangement）

3 链示例只会得到一个 3-环（例如 `op→cdk→xjst→op`），不会出现两条都打 xjst。

## 保持不变的映射

- `WaitForReceipts`：`source.Type != "xjst"`
- `target.Type == "xjst"` 时 `TargetL1Bridge` 使用 `L1BridgeSendContract`，否则 `L1BridgeReceiveContract`
- 全部 job 共用一次生成的 12-word mnemonic

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig.go` | `assignUniqueTargets`；`GenerateJobs` 取消 XJST 自指 |
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig_test.go` | 唯一 target、源≠目标、同类型多实例、XJST 可互跨 |
| `ydyl-deploy-client/cmd/gen_cross_tx_config.go` | 更新 `Long` 文案 |

## 用法

```bash
cd ydyl-deploy-client
go run . gen-cross-tx-config --servers ./output/servers.json --config ./config.deploy.yaml
```
