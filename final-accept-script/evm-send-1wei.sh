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

if [[ -z "${ydyl_l2_pk:-}" ]]; then
  echo "error: ydyl_l2_pk is not set" >&2
  exit 1
fi

run() {
  printf '$ %s\n' "$*"
  "$@"
}

echo "========== 1. 查询当前余额 =========="
run cast balance "$ADDR" --rpc-url "$L2_RPC"
echo "========== 2. 发送 1 wei =========="
run cast send --legacy --rpc-url "$L2_RPC" --private-key "$ydyl_l2_pk" --value 1 "$ADDR"
echo "========== 3. 查询发送后的余额 =========="
run cast balance "$ADDR" --rpc-url "$L2_RPC"
