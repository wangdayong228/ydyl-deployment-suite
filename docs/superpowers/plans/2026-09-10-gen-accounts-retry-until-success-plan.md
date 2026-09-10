# by-contract `--retryUntilSuccess` 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 by-contract 增加 `--retryUntilSuccess`（默认关闭）。关闭时保持现有失败语义；打开后卡住当前这笔直到提交并拿到成功回执才推进。`3_concurrency.ts` 把该 flag 透传给 PM2 worker。

**Architecture:** 发送与 flush 抽到 `scripts/byContractSend.ts`。在现有 `sendSingleChunk` / `waitLastReceipt` 控制流上加分支。提交失败外套循环（同 nonce）；回执失败刷新 nonce 后只重发窗口最后一笔。

**Tech Stack:** TypeScript、Hardhat mocha/chai、PM2 worker args。

## Global Constraints

- 只改 by-contract；不改 by-eoa、op_pipe、xjst_pipe、远端 `gen-accounts start`
- CLI 默认关闭；`cdk_pipe.sh` 默认 `RETRY_UNTIL_SUCCESS=true`
- 打开后提交失败默认沿用当前 assignedNonce；nonce 已被占用则刷新 nonce；`already known` 优先按错误中的 hash 当作已提交。回执失败必须新 nonce，且按下标钉死只重发窗口最后一笔（补发提交失败后不得改打前一笔）
- 超时/找不到交易仍走现有同 nonce 补发
- CLI `--retryUntilSuccess`，环境变量 `RETRY_UNTIL_SUCCESS` / `envToBool`

详见 [spec](../specs/2026-09-10-gen-accounts-retry-until-success-spec.md)。
