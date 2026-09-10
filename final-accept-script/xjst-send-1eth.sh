#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <L2_RPC> <ADDR>" >&2
  exit 1
}

if [[ $# -ne 2 || -z "${1:-}" || -z "${2:-}" ]]; then
  usage
fi

L2_RPC="$1"
ADDR="$2"
XJST_PK="0xc28da5b949956922986bab322e320acf159ea5da3a5f97dbd643a6b049bc89ed"

run() {
  printf '$ %s\n' "$*"
  "$@"
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/ydyl-gen-accounts"

echo "========== 1. 查询当前余额 =========="
run ts-node scripts/2_genSigleAcc.ts balance --addr "$ADDR" --l2type 2 --rpc-url "$L2_RPC"
echo "========== 2. 发送 1 ETH =========="
run ts-node scripts/2_genSigleAcc.ts send --pk "$XJST_PK" --to "$ADDR" --amount 1 --rpc-url "$L2_RPC" --l2type 2
echo "========== 3. 查询发送后的余额 =========="
run ts-node scripts/2_genSigleAcc.ts balance --addr "$ADDR" --l2type 2 --rpc-url "$L2_RPC"
