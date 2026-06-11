# Kurtosis Runtime Log Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement CDK/OP Kurtosis runtime log filtering from `2026-06-11-kurtosis-runtime-log-filter-spec.md`.

**Architecture:** `log_monitor_runtime.sh` will explicitly receive `--stack cdk|op`, select a stack-specific service whitelist, and filter DEBUG/TRACE rows after service filtering. `ydyl-deploy-client` will pass the stack argument when starting the remote monitor, while XJST docker monitoring remains unchanged.

**Tech Stack:** Bash, Kurtosis CLI output parsing, Go deploy client tests, Markdown specs.

---

### Task 1: Failing Tests

**Files:**
- Modify: `ydyl-deploy-client/internal/deploy/logs_test.go`
- Create: `ydyl-scripts-lib/log_monitor_runtime.test.sh`

- [x] **Step 1: Add Go expectations for `--stack`**

Update `TestBuildRuntimeMonitorCommand` to assert CDK commands include `--stack cdk`, OP commands include `--stack op`, and XJST commands do not include `--stack`.

- [x] **Step 2: Add Bash filter behavior tests**

Create `ydyl-scripts-lib/log_monitor_runtime.test.sh` that sources `log_monitor_runtime.sh` in source-only mode, checks CDK/OP service regex selection, verifies CDK keeps `status-checker-1` and `zkevm-bridge-service-1`, and verifies DEBUG/TRACE rows are removed while INFO/WARN/ERROR rows remain.

- [x] **Step 3: Run tests and confirm RED**

Run:

```bash
bash ydyl-scripts-lib/log_monitor_runtime.test.sh
cd ydyl-deploy-client && go test ./internal/deploy -run TestBuildRuntimeMonitorCommand -count=1
```

Expected before implementation: Bash source-only/filter helpers are missing and Go command lacks `--stack`.

### Task 2: Runtime Monitor Implementation

**Files:**
- Modify: `ydyl-scripts-lib/log_monitor_runtime.sh`

- [x] **Step 1: Add `--stack cdk|op` parsing and validation**

Kurtosis mode requires both `--enclave` and `--stack`; docker mode keeps only `--container`.

- [x] **Step 2: Add stack-specific service whitelist helpers**

Define CDK and OP whitelist regexes from the spec and expose helpers used by both service listing and log line filtering.

- [x] **Step 3: Add DEBUG/TRACE filtering helper**

Filter OP `lvl=debug|trace`, CDK zap tab-delimited `DEBUG|TRACE`, and erigon `[dbg]` / `[trace]` style rows without dropping INFO/WARN/ERROR.

- [x] **Step 4: Move Kurtosis watchdog activity to the raw stream**

Keep the existing watchdog process model and reconnect behavior, but for Kurtosis streams update the activity timestamp before service/level filters drop rows. Use a small activity marker file or equivalent side channel so DEBUG/TRACE-only periods do not trigger false reconnects.

### Task 3: Deploy Client Wiring

**Files:**
- Modify: `ydyl-deploy-client/internal/deploy/exec_helpers.go`

- [x] **Step 1: Pass `--stack cdk` for CDK runtime monitors**

Update the CDK branch in `buildRuntimeMonitorCommand`.

- [x] **Step 2: Pass `--stack op` for OP runtime monitors**

Update the OP branch in `buildRuntimeMonitorCommand`.

- [x] **Step 3: Keep XJST unchanged**

Confirm XJST docker runtime monitor commands still use `--mode docker --container testchain_node1` and no `--stack`.

### Task 4: Documentation Sync

**Files:**
- Modify: `docs/superpowers/specs/2026-06-10-deploy-client-log-collection-spec.md`
- Modify: `docs/superpowers/INDEX.md`

- [x] **Step 1: Update log collection spec §3.1**

Replace the old blacklist description with the CDK/OP whitelist plus DEBUG/TRACE filtering behavior from the new spec.

- [x] **Step 2: Register this plan**

Add the plan to the Plans section of `docs/superpowers/INDEX.md`.

### Task 5: Verification

**Files:**
- Verify: `ydyl-scripts-lib/log_monitor_runtime.sh`
- Verify: `ydyl-scripts-lib/log_monitor_runtime.test.sh`
- Verify: `ydyl-deploy-client/internal/deploy/exec_helpers.go`
- Verify: `ydyl-deploy-client/internal/deploy/logs_test.go`
- Verify: `docs/superpowers/specs/2026-06-10-deploy-client-log-collection-spec.md`
- Verify: `docs/superpowers/specs/2026-06-11-kurtosis-runtime-log-filter-spec.md`

- [x] **Step 1: Run Bash syntax and behavior checks**

Run:

```bash
bash -n ydyl-scripts-lib/log_monitor_runtime.sh
bash -n ydyl-scripts-lib/log_monitor_runtime.test.sh
bash ydyl-scripts-lib/log_monitor_runtime.test.sh
```

- [x] **Step 2: Run Go tests**

Run:

```bash
cd ydyl-deploy-client && go test ./internal/deploy -run 'TestBuildRuntimeMonitorCommand|TestShouldCollectXjstRuntimeByName' -count=1
```

- [x] **Step 3: Run consistency checks**

Confirm implementation, specs, plan, and `INDEX.md` agree on CDK/OP service lists, `--stack`, runtime-only scope, and XJST unchanged behavior.
