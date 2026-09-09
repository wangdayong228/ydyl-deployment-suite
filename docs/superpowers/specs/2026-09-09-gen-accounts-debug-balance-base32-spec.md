# `ydyl-gen-accounts` gen:contract DEBUG 打印余额与 CIP-37

## 背景

`gen:contract` 在 `DEBUG=true`（或 `--debugAccounts`）时，于发送 `batchSendETH` 之前为每个生成账户打印：

```text
DEBUG idx=<index> address=0x... pk=0x...
```

Core Space 上 `BatchSender.batchSendETH` 会跳过余额已 ≥ `targetAmount` 的地址。只打印 hex 地址无法直接查 `cfx_getBalance`（JSON-RPC 地址字段必须是 CIP-37），也无法从日志看出该账户发交易前是否已有余额。

本 spec 补充 [2026-09-03 Core Space spec](2026-09-03-gen-accounts-core-space-support-spec.md)：CLI、进度文件与合约 ABI 仍只用 `0x`；DEBUG 日志在保留 `address=0x...` 的前提下额外打印 CIP-37 与链上余额。

## 目标

- `DEBUG=true` 时，`scripts/2_genAccsByContract.ts` 的账户调试行在发交易前增加 native `balance`。
- `l2type=3` 额外打印 verbose CIP-37 `base32`。
- 余额查询失败只写入日志，不中断发送。
- `DEBUG=false` 时零额外 RPC，日志格式不变。

## 非目标

- 不改 `gen:eoa`、`3_concurrency.ts`、进度 JSON、CLI 入参。
- 不把 CIP-37 作为 CLI 输入或进度文件输出。
- 不把 DEBUG 路径改为 JSON-RPC batch 查余额。

## 方案选择

采用 DEBUG 循环内按账户查询余额再打日志。DEBUG 本就会逐账户打印私钥，额外 RPC 可接受。

不采用只本地编码 CIP-37：无法验证「已有余额被跳过」。

不采用整 chunk batch RPC：实现更重，超出排查日志范围。

## 行为

`l2type=3` 目标行（字段插在 `pk=` 之前）：

```text
DEBUG idx=102999 address=0x1fdf3d3dc04a628fe2da209b1504378859378eca base32=NET7654:TYPE.USER:... balance=0 pk=0x...
```

规则：

- `address`、`pk` 保持不变。
- `base32`：仅 `l2type=3`，官方 `js-conflux-sdk` 的 `encodeCfxAddress(hex, networkId, true)`。其它 l2type 不输出该字段。
- `balance`：发交易前 native 余额，十进制 drip/wei（`0`、`1`…），不用 `0x`。`l2type=0/1/2/3` 只要 DEBUG 打开都打印。
- 查询失败：`balance=err` 或 `balance=err:<短消息>`，不 throw。
- `DEBUG=false`：不查余额、不编码 CIP-37。

余额数据源：

- `l2type=0/1`：`provider.getBalance(address)`
- `l2type=2`：内嵌 SDK `cfx.getBalance(address, 'latest_state')`
- `l2type=3`：先 CIP-37，再 `cfx.getBalance(base32)`（`useHexAddressInParameter: false`）

## 实现约束

- CIP-37 编码放在 `ydyl-gen-accounts/scripts/coreSpaceAddress.ts`，只使用官方 `js-conflux-sdk`，禁止引入 TypeChain 或 `libs/js-conflux-sdk`。
- 运行时通过 `debugAccountExtras(address)` 注入查询，DEBUG 循环 `await` 后再 `formatDebugAccountLog`。
- 查询发生在 `准备发送` 日志之前。

## 测试

- `formatDebugAccountLog`：无 extras 仍为旧格式；有 `base32`/`balance` 时字段在 `pk=` 前。
- Core hex + `networkId=7654` 的 CIP-37 以 `NET7654:TYPE.USER:` 开头，`decodeCfxAddress` 还原同一 hex。
- extras 抛错时得到 `balance=err`（可带消息），不向外抛。
