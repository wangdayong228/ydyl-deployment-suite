# deploy-client `sample-wallets` 抽查确定性账户余额

## 背景

`ydyl-gen-accounts` 用确定性规则从 `chainID`/`groupID` + `index` 派生私钥。现有 `gen-private-key` 只生成单钥，查余额要另跑 `cast` / `2_genSigleAcc.ts`。需要一条本地命令：从已部署节点的 `servers.json` 选链、随机抽若干已生成账户、打印私钥、地址和 L2 余额。

## 目标

- 新命令：`ydyl-deploy-client sample-wallets`
- 必填 `--l2type`（`0=cdk` / `1=op` / `2=xjst`；`3=core` 见 [2026-09-10 l2type3 spec](2026-09-10-deploy-client-sample-wallets-l2type3-spec.md)）
- 读取 `--servers`（默认 `./output/servers.json`）
- 复用 `PickChainEntries` 选机规则，再按 l2type 过滤，用 `crypto/rand` **随机挑 1 条**该类型链
- 从该节点 `ydyl-console-service` 取 `L2_RPC_URL`（可被 `--rpc-url` 覆盖，见 [2026-09-10 spec](2026-09-10-deploy-client-sample-wallets-rpc-url-spec.md)）；EVM 的 `chainID` 取 `L2_CHAIN_ID`；XJST 的 `groupID` 从机器名解析
- 在 `[0, max-index)` 抽取 **10** 个不重复 index（`--max-index` 默认 `1000000`，可配如 `20000000`）
- 用现有 `BuildDeterministicPrivateKey` 生成私钥，按 l2type 派生地址，查询余额并打印

## 非目标

- 不修改现有 `gen-private-key` 行为，本次不补缺失的 `cmd/gen_private_key.go`
- `l2type=3` 由 [2026-09-10 l2type3 spec](2026-09-10-deploy-client-sample-wallets-l2type3-spec.md) 定义（必填 `--rpc-url` + `--chainID`，跳过 servers/console-service）
- 不提供 `--groupID` / `--index` / `--count` / `--config`；`--chainID` 仅 `l2type=3` 使用
- `--rpc-url` 由 [2026-09-10 spec](2026-09-10-deploy-client-sample-wallets-rpc-url-spec.md) 定义为可选覆盖，本 spec 不再禁止
- 不充值、不写输出文件、不 SSH
- 不改变 `PickChainEntries` 选机规则

## 方案选择

采用独立命令 + console-service 发现 RPC/chainID，复用 `PickChainEntries`。可选 `--rpc-url` 只覆盖查余额用的 RPC，不跳过选链与 summary。

不采用：必填 `--rpc-url`、按约定端口拼接 RPC、SSH 到远端跑 TypeScript 查余额、因 `--rpc-url` 跳过 `servers.json`/console-service。

## CLI

```bash
cd ydyl-deploy-client
go run . sample-wallets --l2type 1
go run . sample-wallets --servers ./output/servers.json --l2type 2 --max-index 20000000
go run . sample-wallets --l2type 1 --rpc-url http://10.0.0.1/l2rpc
```

| Flag | 默认 | 规则 |
|------|------|------|
| `--l2type` | 无 | 必填；`0`/`1`/`2`（`3` 见 l2type3 spec）。Cobra 必须要求显式出现该 flag，以便 `--l2type 0` 合法、省略时报错 |
| `--servers` | `./output/servers.json` | `servers.json` 路径 |
| `--max-index` | `1000000` | 必须 `>= 10`；抽样区间 `[0, max-index)`，不含上限 |
| `--rpc-url` | 空 | 可选。`TrimSpace` 后非空则原样作为查余额 RPC，不改写；空或纯空白走 summary 改写规则。详见 [2026-09-10 spec](2026-09-10-deploy-client-sample-wallets-rpc-url-spec.md) |

抽样个数固定为 **10**，不是 flag。

## 选链与发现

1. `LoadServers` + 现有 `PickChainEntries`：`op`/`cdk` 全部参与；`xjst` 仅 name 解析出的组内 `index==1`。
2. 按 l2type 映射过滤：`0→cdk`，`1→op`，`2→xjst`。过滤后为空则失败。
3. 用 `crypto/rand` 在过滤结果中选 1 条。
4. 只请求该 IP 的 `GET /v1/result/pipeline/summary`（`http://<ip>:8080`），不拉 contracts。
5. L2 RPC：若 `--rpc-url` 经 `TrimSpace` 后非空，原样使用且**不**做 `ReplaceLocalhostWithIP`；否则 `ReplaceLocalhostWithIP(summary.L2_RPC_URL, ip)`（导出 crosstxconfig 现有改写函数，行为不变）。未覆盖且改写后为空则失败。覆盖时允许 summary 的 `L2_RPC_URL` 为空。
6. `l2type=0/1`：解析 `summary.L2_CHAIN_ID` 为十进制 `uint64`，缺失或非法则失败。该值用于私钥派生。
7. `l2type=2`：从 name（`tagPrefix-xjst-groupId-index`）解析 `groupID`（正整数），用于私钥派生。不使用 `L2_CHAIN_ID` 派生私钥。name 非法则失败。

## 私钥、地址、余额

私钥公式与 `cryptoutil.BuildDeterministicPrivateKey` / `ydyl-gen-accounts` 一致：

`privateKey = 0x + 左补零到 64 hex(selectedID[4字节] + index[10字节])`

- `l2type=0/1`：`selectedID = chainID`
- `l2type=2`：`selectedID = groupID`

抽样：在 `[0, maxIndex)` 抽 10 个不重复 index。若 `BuildDeterministicPrivateKey` 失败（例如全 0 私钥），丢弃该 index 再抽；凑不满 10 个则失败。

地址：

- `l2type=0/1`：secp256k1 公钥的以太坊地址（`crypto.PubkeyToAddress`）
- `l2type=2`：同一以太坊地址，把 `0x` 后第一个 hex 字符置为 `1`（Conflux/XJST user type nibble）

已知向量（`docs/测试会议/2026_08_25.md`）：

- `chainID=10000`，`index=200000`，`l2type=0/1` → 地址 `0xfc737023702a09c01260252d853033ccaa587b5d`
- `groupID=1`，`index=12345`，`l2type=2` → 地址 `0x1d22176670f087456f2760405469b25917eed45b`

余额：顺序查询 10 次；任一次 RPC 失败则整命令失败。

- `l2type=0/1`：`eth_getBalance(address, "latest")`
- `l2type=2`：`cfx_getBalance(address, "latest_state")`

使用已有 `go-ethereum` JSON-RPC client，不加 Conflux Go SDK。

## 输出

stdout 先打一行元数据，再打表（列：`index`、`privateKey`、`address`、`balanceWei`）。

元数据字段：`name`、`l2type`、EVM 时 `chainID`、XJST 时 `groupID`、实际用于查余额的 L2 RPC（覆盖值或改写后的 summary URL）。

`balanceWei` 为十进制整数（wei/drip）。不写文件。

## 错误

失败退出：

- 未传或非法 `--l2type`
- `max-index < 10`
- 读/解析 `servers.json` 失败
- `PickChainEntries` 失败
- 过滤后无匹配链
- console-service 失败
- 未覆盖 `--rpc-url` 时 summary 缺少可用 `L2_RPC_URL`；EVM 缺少合法 `L2_CHAIN_ID`
- XJST name 无法解析 `groupID`
- 抽不满 10 个合法 index
- 任一余额 RPC 失败

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil.go` | `AddressFromPrivateKey(pkHex string, l2type int) (string, error)` |
| `ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil_test.go` | 地址向量测试 |
| `ydyl-deploy-client/internal/crosstxconfig/crosstxconfig.go` | 导出 `ReplaceLocalhostWithIP` |
| `ydyl-deploy-client/internal/samplewallets/` | 选链、抽样、派生、查余额 |
| `ydyl-deploy-client/cmd/sample_wallets.go` | Cobra 命令 |
| `ydyl-deploy-client/cmd/sample_wallets_test.go` | flag 默认值、`--l2type` 必填、`--rpc-url` 默认空 |
| `ydyl-deploy-client/README.md` | 新命令说明 |

## 用法注意

在 `ydyl-deploy-client` 目录执行，以便默认 `--servers ./output/servers.json` 生效。目标节点需已有可访问的 `ydyl-console-service:8080` 与 L2 RPC。
