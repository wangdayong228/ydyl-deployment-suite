# sample-wallets 支持 l2type=3（CIP-37）实施计划

> **面向执行代理：** 必须使用 `executing-plans` 或 `subagent-driven-development`，按任务逐项执行。所有步骤使用复选框跟踪状态。

**目标：** 给 `sample-wallets` 增加 `l2type=3`：必填 `--rpc-url` 与 `--chainID`，跳过 servers/console-service，地址输出 CIP-37，余额走 `cfx_getBalance`。

**架构：** `Run` 对 `l2type==3` 早退；地址用已有 `CoreBase32AddressFromPrivateKey`；`JSONRPCBalanceClient` 把 3 与 2 同样走 `cfx_getBalance`。

**技术栈：** Go、Cobra、现有 cryptoutil CIP-37

## 全局约束

- spec 真理之源：`docs/superpowers/specs/2026-09-10-deploy-client-sample-wallets-l2type3-spec.md`
- `0/1/2` 行为不变；不改 `PickChainEntries`；不改 `AddressFromPrivateKey`
- 不新增 `--networkId`；`chainID` 同时作 CIP-37 networkId，必须 `>=1`
- Result.Name 固定为 `core`
- 生产代码遵循红、绿、重构
- 用户未要求 commit：不要提交

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `ydyl-deploy-client/internal/samplewallets/samplewallets.go` | ChainID、Core 早退、CIP-37、cfx 含 3 |
| `ydyl-deploy-client/internal/samplewallets/samplewallets_test.go` | Core 路径测试 |
| `ydyl-deploy-client/cmd/sample_wallets.go` | `--chainID` |
| `ydyl-deploy-client/cmd/sample_wallets_test.go` | 默认 0 |
| `ydyl-deploy-client/README.md` | 示例 |

---

### Task 1: samplewallets Core 路径（TDD）

- [x] **步骤 1：写失败测试**（成功路径、缺 rpc-url、chainID=0、cfx_getBalance）
- [x] **步骤 2：确认 RED**
- [x] **步骤 3：最小实现**
- [x] **步骤 4：确认 GREEN**

### Task 2: Cobra + README

- [x] **步骤 1：`--chainID` 默认 0 测试**
- [x] **步骤 2：确认 RED**
- [x] **步骤 3：注册 flag、更新 Long/README**
- [x] **步骤 4：确认 GREEN**
