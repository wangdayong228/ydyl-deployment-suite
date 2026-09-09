# gen-private-key 支持 l2type 3（CIP-37）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 补回 `gen-private-key`，并让 `l2type=3` 按 Core chainID 派生私钥、输出与官方 `js-conflux-sdk` 一致的 CIP-37 地址。

**Architecture:** 私钥仍由 `BuildDeterministicPrivateKey` 生成。`AddressFromPrivateKey` 只服务 0/1/2。Core 走 `CoreBase32AddressFromPrivateKey`（type-nibble hex + 本地 CIP-37）。Cobra 命令打印 `privateKey=` / `address=`。

**Tech Stack:** Go、Cobra、go-ethereum crypto、官方 js-conflux-sdk 金向量（仅测试对照，不引入 go-conflux-sdk）。

## Global Constraints

- `l2type=3` 使用 `--chainID` 作为私钥 selectedID 与 CIP-37 networkId，必须 `>= 1`
- Core 使用配置 `chain_id`（如 7654），不要用 `evm_chain_id`
- `address` 对 l2type=3 只输出非 verbose CIP-37
- 不引入 `go-conflux-sdk`，不查 RPC，不写文件
- `AddressFromPrivateKey` 继续拒绝 `l2type=3`

详见 [spec](../specs/2026-09-09-deploy-client-gen-private-key-l2type3-spec.md)。
