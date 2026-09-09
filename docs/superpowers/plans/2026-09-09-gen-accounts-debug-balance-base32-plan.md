# gen:contract DEBUG 打印 balance 与 CIP-37 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `DEBUG=true` 时，`gen:contract` 现有账户调试行在发交易前增加 `base32`（仅 Core）和链上 `balance`。

**Architecture:** 不改 CLI / 进度文件的 `0x` 约定。扩展 `formatDebugAccountLog` 与 DEBUG 循环。CIP-37 编码放在 `coreSpaceAddress.ts`；余额通过运行时 `debugAccountExtras` 查询，失败只写日志。

**Tech Stack:** TypeScript、官方 `js-conflux-sdk`（l2type=3）、ethers / 内嵌 XJST SDK。

## Global Constraints

- CLI、进度文件与合约 ABI 地址仍为 `0x`
- `base32` 仅 `l2type=3`，verbose CIP-37
- `balance` 为十进制 drip/wei，查询失败为 `balance=err` 且不中断发送
- `DEBUG=false` 零额外 RPC
- `coreSpaceAddress.ts` 不得引入 TypeChain 或 `libs/js-conflux-sdk`

详见 [spec](../specs/2026-09-09-gen-accounts-debug-balance-base32-spec.md)。
