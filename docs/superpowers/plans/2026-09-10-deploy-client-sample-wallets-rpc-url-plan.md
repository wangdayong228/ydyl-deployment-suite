# sample-wallets 可选 --rpc-url 实施计划

> **面向执行代理：** 必须使用 `executing-plans` 或 `subagent-driven-development`，按任务逐项执行。所有步骤使用复选框跟踪状态。

**目标：** 给 `ydyl-deploy-client sample-wallets` 增加可选 `--rpc-url`：有值则原样用于查余额，省略或空白则仍走 console-service `L2_RPC_URL` + `ReplaceLocalhostWithIP`。

**架构：** 在现有 `samplewallets.Params` / `Run` 上增加覆盖字段；Cobra 增加同名 flag。选链、summary、派生逻辑不变。

**技术栈：** Go 1.25、Cobra、现有 `internal/samplewallets` 测试桩

## 全局约束

- spec 真理之源：`docs/superpowers/specs/2026-09-10-deploy-client-sample-wallets-rpc-url-spec.md`
- 基线 spec：`docs/superpowers/specs/2026-09-08-deploy-client-sample-wallets-spec.md`（已修订，不再禁止 `--rpc-url`）
- 不把 `--rpc-url` 改为必填；不跳过 `servers.json` / console-service
- 不新增 `--chainID` / `--groupID` / `--index` / `--count` / `--config`
- 仍不支持 `l2type=3`；不改 `PickChainEntries`；不改 `gen-private-key`
- 覆盖 URL 不做 `ReplaceLocalhostWithIP`
- 生产代码遵循红、绿、重构；每个测试必须先因缺少目标行为而失败
- 用户未要求 commit：不要提交

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `ydyl-deploy-client/internal/samplewallets/samplewallets.go` | `Params.RPCURL` 与 `Run` 解析 |
| `ydyl-deploy-client/internal/samplewallets/samplewallets_test.go` | 覆盖 / 回退 |
| `ydyl-deploy-client/cmd/sample_wallets.go` | `--rpc-url` |
| `ydyl-deploy-client/cmd/sample_wallets_test.go` | flag 默认空 |
| `ydyl-deploy-client/README.md` | 覆盖示例 |

---

### Task 1: samplewallets RPC 覆盖（TDD）

**文件：**

- 修改：`ydyl-deploy-client/internal/samplewallets/samplewallets.go`
- 修改：`ydyl-deploy-client/internal/samplewallets/samplewallets_test.go`

**接口：**

- `Params` 增加 `RPCURL string`
- `Run`：`TrimSpace(p.RPCURL)` 非空则原样使用；否则 `ReplaceLocalhostWithIP(summary.L2_RPC_URL, ip)`，空则失败

- [x] **步骤 1：写失败测试**

在 `samplewallets_test.go` 增加：覆盖不改写、覆盖允许空 summary RPC、空白 `RPCURL` 回退改写。

- [x] **步骤 2：确认 RED**

```bash
cd ydyl-deploy-client && go test ./internal/samplewallets -run 'TestRun_UsesRPCURLOverrideWithoutRewriting|TestRun_OverrideAllowsEmptySummaryRPC|TestRun_BlankRPCURLFallsBackToRewrittenSummary' -count=1
```

期望：因尚未解析覆盖而失败（RPC 仍被改写，或空 summary RPC 失败）。

- [x] **步骤 3：最小实现**

`Params.RPCURL` + `Run` 中按 spec 解析 RPC。

- [x] **步骤 4：确认 GREEN**

```bash
cd ydyl-deploy-client && go test ./internal/samplewallets -count=1
```

---

### Task 2: Cobra flag + README

**文件：**

- 修改：`ydyl-deploy-client/cmd/sample_wallets.go`
- 修改：`ydyl-deploy-client/cmd/sample_wallets_test.go`
- 修改：`ydyl-deploy-client/README.md`

- [x] **步骤 1：写失败测试**

`TestSampleWalletsFlagDefaults` 断言 `--rpc-url` 默认 `""`。

- [x] **步骤 2：确认 RED**

```bash
cd ydyl-deploy-client && go test ./cmd -run TestSampleWalletsFlagDefaults -count=1
```

- [x] **步骤 3：注册 `--rpc-url`，传入 `Params.RPCURL`，更新 Long 与 README**

- [x] **步骤 4：确认 GREEN**

```bash
cd ydyl-deploy-client && go test ./cmd ./internal/samplewallets -count=1 && go run . sample-wallets --help
```

`--help` 出现 `--rpc-url`。
