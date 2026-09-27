#!/usr/bin/env bash
# check.sh — one-screen health check for an Asentum validator.
# Usage: bash check.sh [ase1…address]   (defaults to this machine's validator)
set -uo pipefail

PEER=${ASENTUM_PEER:-http://204.168.132.194:8545}
G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[2m'; N='\033[0m'
strip() { sed -E 's/\x1b\[[0-9;]*m//g; s/\\033\[[0-9;]*m//g'; }
kv() { printf "  %-16s %b\n" "$1" "$2"; }

command -v jq >/dev/null || { echo "jq is required: apt-get install -y jq"; exit 1; }

ADDR=${1:-}
if [[ -z "$ADDR" ]] && command -v asentum-validator >/dev/null; then
  ADDR=$(asentum-validator status 2>/dev/null | strip | awk '/^ *address/ {print $2}')
fi
[[ -n "$ADDR" ]] || { echo "Pass your validator address: bash check.sh ase1…"; exit 1; }

SERVICE=$(systemctl is-active asentum-validator 2>/dev/null || echo "n/a")
V=$(curl -fs --max-time 10 "$PEER/validators" \
  | jq -c --arg a "$ADDR" '.validators[] | select(.address==$a)' 2>/dev/null)
HEADS=$(curl -fs --max-time 10 "$PEER/v3/heads" 2>/dev/null)
FIN=$(jq -r '.finalized // "?"' <<<"${HEADS:-{\}}")

printf "\n  ${G}ASENTUM VALIDATOR · HEALTH CHECK${N}\n"
kv "address" "$ADDR"
kv "service" "$SERVICE"

if [[ -z "$V" ]]; then
  kv "network status" "${Y}not found in validator set${N} ${D}(not bonded yet?)${N}"
  echo; exit 1
fi

STATUS=$(jq -r '.status' <<<"$V")
COMMITTEE=$(jq -r '.committeeState // "-"' <<<"$V")
VOTED=$(jq -r '.lastVotedHeight // "-"' <<<"$V")
MISSES=$(jq -r '.consecutiveMisses // 0' <<<"$V")
NEXT=$(jq -r '.nextCommitteeEntryAt // empty' <<<"$V")
LOCAL=""
if command -v asentum-validator >/dev/null; then
  LOCAL=$(asentum-validator status 2>/dev/null | strip | awk '/block height/ {print $3}')
fi
kv "network status" "$STATUS"
[[ -n "$LOCAL" ]] && kv "local height" "$LOCAL   ${D}(network finalized $FIN)${N}"
kv "committee" "$COMMITTEE${NEXT:+   ${D}(next committee entry at block $NEXT)${N}}"
kv "last voted" "$VOTED"
kv "misses in a row" "$MISSES"
if command -v asentum-validator >/dev/null; then
  BAL=$(asentum-validator balance "$ADDR" 2>/dev/null | strip | grep -oE '[0-9.]+ ASE' | head -1)
  kv "wallet" "${BAL:-?}"
fi

BEHIND=0
if [[ "$LOCAL" =~ ^[0-9]+$ && "$FIN" =~ ^[0-9]+$ ]]; then BEHIND=$(( FIN - LOCAL )); fi

if [[ "$SERVICE" != "active" && "$SERVICE" != "n/a" ]]; then
  printf "  ${R}✗ service is $SERVICE. Run: asentum-validator restart${N}

"
  exit 1
elif (( BEHIND > 100 )); then
  printf "  ${Y}… node is $BEHIND blocks behind. Let it catch up (asentum-validator logs)${N}

"
  exit 1
elif [[ "$STATUS" == "active" && ( "$COMMITTEE" == "dormant" || "$COMMITTEE" == "waiting_epoch_entry" ) ]]; then
  printf "  ${G}✔ healthy, waiting for a committee slot${N} ${D}(only part of the set signs each epoch; the node re-enters on its own)${N}

"
elif [[ "$STATUS" == "active" && "$COMMITTEE" == "signing" && "$MISSES" -lt 20 ]]; then
  printf "  ${G}✔ looks healthy${N}\n\n"
elif [[ "$STATUS" == "pending" ]]; then
  printf "  ${Y}… pending: becomes active at the next epoch (~20–25 min)${N}\n\n"
else
  printf "  ${R}✗ not signing. Check: asentum-validator logs${N}\n\n"
  exit 1
fi
