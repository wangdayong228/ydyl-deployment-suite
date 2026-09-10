# deploy-client `sample-wallets` 支持 l2type=3（CIP-37）

覆盖 [2026-09-08 sample-wallets spec](2026-09-08-deploy-client-sample-wallets-spec.md) 与 [2026-09-10 rpc-url spec](2026-09-10-deploy-client-sample-wallets-rpc-url-spec.md) 中「不支持 `l2type=3`」。`0/1/2` 选链与可选 `--rpc-url` 覆盖不变。

## 背景

Conflux Core Space（`l2type=3`）不在 `servers.json` 的 op/cdk/xjst 条目里。Core `chain_id`（如 7654）不能用 L2 console-service 的 `L2_CHAIN_ID`。`cfx_getBalance` 要求 CIP-37 base32 地址。会议纪要用法：

```bash
go run . gen-private-key --chainID 7654 --index 50000 --l2type 3
cast rpc cfx_getBalance net7654:... --rpc-url http://52.12.7.189/cspace
```

## 目标

- `sample-wallets --l2type 3` 必填 `--rpc-url` 与 `--chainID`（`>=1`，同时作 CIP-37 `networkId`）
- 跳过 `servers.json`、`PickChainEntries`、console-service
- 地址：非 verbose CIP-37（`CoreBase32AddressFromPrivateKey`）；`chainID=7654` 前缀 `net7654:`
- 余额：`cfx_getBalance(address, "latest_state")`
- 仍抽 10 个 index；私钥公式与 `BuildDeterministicPrivateKey` 的 `l2type=3`（`selectedID=chainID`）一致
- `0/1/2` 行为不变

## 非目标

- 不把 `0/1/2` 的 `--rpc-url` 改为必填
- `l2type=3` 不读 `servers.json` / 不打 console-service
- 不新增 `--networkId` / `--groupID` / `--index` / `--count`
- 不改 `PickChainEntries`
- 不改 `AddressFromPrivateKey`（仍只服务 `0/1/2`，仍拒绝 `3`）
- 不改 `gen-private-key` 命令行为

## CLI

```bash
cd ydyl-deploy-client
go run . sample-wallets --l2type 3 --chainID 7654 --rpc-url http://52.12.7.189/cspace
```

| Flag | 默认 | 规则 |
|------|------|------|
| `--l2type` | 无 | 必填；现允许 `0`/`1`/`2`/`3` |
| `--rpc-url` | 空 | `l2type=3` 时 `TrimSpace` 后必须非空，原样使用。`0/1/2` 仍为可选覆盖 |
| `--chainID` | `0` | 仅 `l2type=3` 使用，必须 `>=1`。`0/1/2` 忽略 |
| `--servers` | `./output/servers.json` | `l2type=3` 忽略 |
| `--max-index` | `1000000` | 仍必须 `>= 10` |

## 解析（l2type=3）

`Run` 在校验 `l2type==3`、`max-index`、`balances != nil` 后早退：

```text
rpcURL = TrimSpace(Params.RPCURL)
if rpcURL == "": fail "l2type=3 必须提供 --rpc-url"
if Params.ChainID < 1: fail "l2type=3 时 chainID 必须 >= 1"
抽 10 钥（groupID=0, chainID=Params.ChainID, l2type=3）
地址 = CoreBase32AddressFromPrivateKey(pk, chainID)
BalanceAt(rpcURL, cip37, 3)
Result.Name = "core"
```

不要求 fetcher；不读 `ServersPath`。

## 输出

元数据：`name=core l2type=3 chainID=<id> rpc=<url>`。

`address` 列为 CIP-37。

## 错误

相对既有 spec，`l2type=3` 额外失败：

- 未传或空白 `--rpc-url`
- `chainID < 1`
- `CoreBase32AddressFromPrivateKey` 失败

`0/1/2` 的 servers/summary 错误路径不适用于 `l2type=3`。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/samplewallets/samplewallets.go` | `Params.ChainID`；`Run` 早退；CIP-37；`cfx_getBalance` 含 3 |
| `ydyl-deploy-client/internal/samplewallets/samplewallets_test.go` | Core 路径、必填、cfx 方法 |
| `ydyl-deploy-client/cmd/sample_wallets.go` | `--chainID`；l2type 说明含 3 |
| `ydyl-deploy-client/cmd/sample_wallets_test.go` | `--chainID` 默认 0 |
| `ydyl-deploy-client/README.md` | l2type=3 示例 |

## 用法注意

Core 请传 Core `chain_id`（如私链 7654），不要传 eSpace `evm_chain_id`。
