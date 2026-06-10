# Superpowers 文档索引

记录项目内所有 spec 与 plan 的对应关系，便于追溯改动来源。

约定参见 `CLAUDE.md` "Superpowers 工作流约定"：
- 改动涉及需求/设计 → 先改 spec，再改产物
- 改动是纯实施细节 → 改产物，但完成后扫一遍 spec 确认仍一致
- spec 与产物不一致 → 视为 bug，必须修复

---

## Specs

| 日期 | Spec | 对应报告章节 | 写作产物 | 负责人 |
|------|------|-------------|---------|--------|
| 2026-05-06 | [Rollup 侧链接入方案](specs/2026-05-06-rollup-sidechain-integration-spec.md) | 4.2 | `doc-report/4.2-rollup-sidechain-integration.md` | 大勇 |
| 2026-05-07 | [多类型侧链规模化部署](specs/2026-05-07-multi-sidechain-bulk-deployment-spec.md) | 4.4 | `doc-report/4.4-multi-sidechain-bulk-deployment.md`（待写） | 大勇 |
| 2026-06-10 | [deploy-client 日志收集与统计](specs/2026-06-10-deploy-client-log-collection-spec.md) | 4.4 扩展 | — | 大勇 |

## Plans

（暂无）

---

## Spec 间依赖

- 4.4 spec 上游依赖 4.2 spec：jsonrpc-proxy 的 block hash 修正、CDK 内核侧改造、L1 origin drift 等论点在 4.2 论证后被 4.4 引用，不重述
- 2026-06-10 日志 spec 扩展 4.4 的 `ydyl-deploy-client` 编排：新增 `collect-logs` / `stats-logs`，详见该 spec
