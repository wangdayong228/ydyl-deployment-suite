# tps 汇总写入 TOTALTPS.json 实施计划

对应 spec：[bench-cross-tx tps 汇总写入 TOTALTPS.json](../specs/2026-09-10-bench-cross-tx-tps-summary-spec.md)

> 详细步骤见已批准的 Cursor plan。本文件只作 INDEX 追溯。

**Goal:** `totalTPS()` 覆盖写 `output/jobs/TOTALTPS.json`，补齐 ISO 时间、经历时长、链数量、每链用户数。

**做法:**

1. `scripts/lib/tpsSummary.js` 纯函数 + `node:test`
2. `h_TPSjob.js` 传入原始 jobs；`h_L2TPSCalulation.js` 读 `{hash}-l1.json` 的 `start_timestamp`
3. 更新 `ydyl-deploy-client/README.md`
