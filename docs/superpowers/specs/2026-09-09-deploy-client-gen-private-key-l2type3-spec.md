# deploy-client `gen-private-key` 支持 Core Space（l2type=3 / CIP-37）

## 背景

`ydyl-deploy-client gen-private-key` 已能按确定性规则生成 `l2type=0/1/2` 的私钥和 hex 地址，但 `BuildDeterministicPrivateKey` 与 CLI 均拒绝 `l2type=3`。

Conflux Core Space（`l2type=3`）的 `cfx_getBalance` 等 JSON-RPC 要求 CIP-37 base32 地址。需要让 `l2type=3` 用 Core `chainID` 派生私钥，并输出 CIP-37。

私钥布局与 `ydyl-gen-accounts` 一致：

```text
32 字节私钥 = 左侧补零 + selectedID(4 字节) + index(10 字节)
```

## 目标

- 扩展 `ydyl-deploy-client gen-private-key` 支持 `l2type=3`
- `l2type=0/1/2` 输出与会议纪要向量一致的 hex 地址
- `l2type=3` 用 Core `chainID` 派生私钥，`address` 只输出非 verbose CIP-37（带 checksum）
- CIP-37 编码与官方 `js-conflux-sdk` 的 `PrivateKeyAccount(pk, networkId).address` 完全一致
- 不引入 `go-conflux-sdk`

## 非目标

- 本命令不改 `sample-wallets` 的选链逻辑；`sample-wallets` 的 `l2type=3` 见 [2026-09-10 sample-wallets l2type3 spec](2026-09-10-deploy-client-sample-wallets-l2type3-spec.md)，地址编码仍由 `CoreBase32AddressFromPrivateKey` 提供
- `AddressFromPrivateKey` 继续只服务 `0/1/2`，继续拒绝 `l2type=3`
- 不改 `ydyl-gen-accounts`（那边 CLI/进度文件仍用 `0x`）
- 不改 `ydyl-console-service` 的 `L2Type` 枚举
- 本命令不查余额、不调 RPC、不写文件
- 不新增 `--networkId`（`chainID` 同时作为 CIP-37 `networkId`）

## 方案选择

采用本地 CIP-37 编码 + 官方 SDK 金向量。`l2type=3` 先得到与 XJST 相同的 Core 用户 hex（首 nibble=`1`），再编成 CIP-37。

不采用 `go-conflux-sdk`（与现有 `go-ethereum v1.15.11` 版本冲突风险高）。

不采用运行时调用 Node SDK。

## CLI

```bash
cd ydyl-deploy-client
go run . gen-private-key --chainID 10000 --index 200000
go run . gen-private-key --groupID 1 --index 12345 --l2type 2
go run . gen-private-key --chainID 7654 --index 200000 --l2type 3
```

stdout（两行）：

```text
privateKey=0x...
address=...
```

| Flag | 默认 | 规则 |
|------|------|------|
| `--index` | 无 | 必填；非负整数，不超过 10 字节上限 |
| `--l2type` | `0` | `0`/`1`/`2`/`3` |
| `--chainID` | `0` | `l2type=0/1/3` 必填；`3` 时同时作为 CIP-37 `networkId`，必须 `>= 1`。Core 使用配置 `chain_id`（例如私链 7654），不要用 `evm_chain_id` |
| `--groupID` | `0` | `l2type=2` 必填 |

地址输出：

- `0/1`：小写以太坊 `0x` 地址
- `2`：同一地址把 `0x` 后第一个 hex 字符置为 `1`
- `3`：仅 CIP-37。`chainID=7654` → `net7654:`；`1` → `cfxtest:`；`1029` → `cfx:`

已知向量（`docs/测试会议/2026_08_25.md`）：

- `chainID=10000`，`index=200000`，`l2type=0/1` → `privateKey=0x0000000000000000000000000000000000000000271000000000000000030d40`，`address=0xfc737023702a09c01260252d853033ccaa587b5d`
- `groupID=1`，`index=12345`，`l2type=2` → `address=0x1d22176670f087456f2760405469b25917eed45b`

`l2type=3` 金向量以官方 `js-conflux-sdk` 对同一私钥 + `networkId` 的输出为准，测试中钉死。

## 派生与编码

- `l2type=0/1/3`：`selectedID = chainID`
- `l2type=2`：`selectedID = groupID`
- `BuildDeterministicPrivateKey` 接受 `l2type=3`，走 chainID 路径
- 新增 `CoreBase32AddressFromPrivateKey(pkHex, networkID)`：secp256k1 公钥 → hex type-nibble `0x1...` → CIP-37
- `networkID == 0` 时失败

## 错误

失败退出：

- 未传 `--index` 或 index 非法 / 超 10 字节 / 导致全 0 私钥
- `--l2type` 不是 `0/1/2/3`
- `l2type=0/1` 未提供 `--chainID`
- `l2type=3` 未提供 `--chainID`，或 `chainID < 1`
- `l2type=2` 未提供 `--groupID`

## 涉及文件

| 文件 | 改动 |
|------|------|
| `ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil.go` | `BuildDeterministicPrivateKey` 接受 `l2type=3` |
| `ydyl-deploy-client/internal/utils/cryptoutil/cip37.go` | CIP-37 前缀与 payload/checksum |
| `ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil.go` 或同包 | `CoreBase32AddressFromPrivateKey` |
| `ydyl-deploy-client/internal/utils/cryptoutil/cryptoutil_test.go` | 私钥与 CIP-37 金向量 |
| `ydyl-deploy-client/cmd/gen_private_key.go` | Cobra 命令 |
| `ydyl-deploy-client/cmd/gen_private_key_test.go` | flag 与输出校验 |
| `ydyl-deploy-client/README.md` | `l2type=3` 用法 |

## 用法注意

在 `ydyl-deploy-client` 目录执行。Core 私链请传 Core `chain_id`（如 7654），不要传 eSpace `evm_chain_id`。
