# deploy-client `sample-wallets` 可选 `--rpc-url`

覆盖 [2026-09-08 sample-wallets spec](2026-09-08-deploy-client-sample-wallets-spec.md) 中「不提供 `--rpc-url`」：查余额 RPC 可被 CLI 覆盖，其它选链、派生、抽样规则不变。

## 背景

默认仍从选中节点的 console-service summary 取 `L2_RPC_URL`，再 `ReplaceLocalhostWithIP`。部分场景需要打到指定 RPC（本机、公网入口、与 summary 不一致的路径），因此增加可选 `--rpc-url`。

## 目标

- `sample-wallets` 增加可选 `--rpc-url`，默认空
- `TrimSpace` 后非空：原样作为查余额 RPC，**不做** `ReplaceLocalhostWithIP`
- 空或纯空白：走原规则 `ReplaceLocalhostWithIP(summary.L2_RPC_URL, ip)`；改写后为空则失败
- 覆盖时允许 summary 的 `L2_RPC_URL` 为空
- 仍读 `servers.json`、仍 `PickChainEntries`、仍请求 console-service（EVM 的 `chainID` 仍来自 `L2_CHAIN_ID`；XJST 的 `groupID` 仍从机器名解析）
- `Result.RPC` 与全部 `BalanceAt` 调用使用最终解析出的 URL

## 非目标

- 不把 `--rpc-url` 改为必填
- 不因 `--rpc-url` 跳过 `servers.json` 或 console-service
- 本 spec 不定义 `--chainID` / `--groupID` / `--index` / `--count` / `--config`（`--chainID` 与 `l2type=3` 见 [l2type3 spec](2026-09-10-deploy-client-sample-wallets-l2type3-spec.md)）
- `0/1/2` 的 `--rpc-url` 仍为可选覆盖，不因本 spec 跳过 servers/console-service
- 不改 `PickChainEntries`、不改 `gen-private-key`

## CLI

```bash
cd ydyl-deploy-client
go run . sample-wallets --l2type 1
go run . sample-wallets --l2type 1 --rpc-url http://10.0.0.1/l2rpc
go run . sample-wallets --l2type 1 --rpc-url http://127.0.0.1/custom
```

| Flag | 默认 | 规则 |
|------|------|------|
| `--rpc-url` | 空 | 可选。`TrimSpace` 后非空则原样使用（含 `127.0.0.1` / `localhost`）；空或纯空白回退 summary 改写 |

## 解析

在 `FetchSummary` 成功之后：

```text
rpcURL = TrimSpace(Params.RPCURL)
if rpcURL == "":
    rpcURL = TrimSpace(ReplaceLocalhostWithIP(summary.L2_RPC_URL, picked.IP))
    if rpcURL == "":
        fail "L2_RPC_URL 为空"
```

覆盖路径不校验 URL 形态；非法地址在 `BalanceAt` 时失败。

## 错误

相对 2026-09-08 spec：

- 「summary 缺少可用 `L2_RPC_URL`」仅在未覆盖时失败
- 覆盖时 summary 仍必须可取（console-service 失败仍失败）；EVM 仍要求合法 `L2_CHAIN_ID`

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/samplewallets/samplewallets.go` | `Params.RPCURL`；`Run` 按上式解析 RPC |
| `ydyl-deploy-client/internal/samplewallets/samplewallets_test.go` | 覆盖不改写、覆盖允许空 summary RPC、空白回退 |
| `ydyl-deploy-client/cmd/sample_wallets.go` | `--rpc-url` flag |
| `ydyl-deploy-client/cmd/sample_wallets_test.go` | `--rpc-url` 默认空 |
| `ydyl-deploy-client/README.md` | 覆盖示例 |

## 用法注意

覆盖只改变查余额入口，不改变抽到哪条链、用哪个 `chainID`/`groupID` 派生私钥。
