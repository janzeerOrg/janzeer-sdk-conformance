#!/usr/bin/env bash
# Boots the local 4-anchor Janzeer network with the dev faucet funding the canonical test wallet, waits until
# blocks are being produced, and prints the JANZEER_* environment every SDK e2e test reads.
#   ./e2e/node-up.sh            # start (builds the jar first if missing)
#   eval "$(./e2e/node-up.sh --env)"   # only print the exports (net already running)
#   NETWORK=testnet ./e2e/node-up.sh   # same net on the "janzeer-testnet" id (+ faucet on node 1 via FAUCET_SECRET)
# Requires the node repo as a sibling: ../backend_v03 (private; the conformance kit itself has no node code).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NODE_REPO=${NODE_REPO:-$HERE/../../backend_v03}
FAUCET=${FAUCET:-0x06e1c0fa9955a700876f8cb0acc7f13fba9fb8ba:100000}
export NETWORK=${NETWORK:-mainnet}
# Testnet: node 1 also runs the HTTP faucet (POST /api/v1/faucet) from the dev-fund wallet — its private key is derived
# from the canonical mnemonic with the TS SDK (nodes.sh passes FAUCET_SECRET to node 1 only; refused on mainnet anyway).
if [ "$NETWORK" != "mainnet" ] && [ -z "${FAUCET_SECRET:-}" ] && [ -f "$HERE/../../sdk_ts/dist/crypto.js" ]; then
  FAUCET_SECRET=$(node --input-type=module -e "import {accountFromMnemonic} from '$HERE/../../sdk_ts/dist/crypto.js'; console.log(accountFromMnemonic('abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about').privHex)" 2>/dev/null || true)
  export FAUCET_SECRET
fi
export JAVA_HOME=${JAVA_HOME:-$HOME/.sdkman/candidates/java/17.0.19-librca}
export PATH=$JAVA_HOME/bin:$PATH

print_env() {
  cat <<ENV
export JANZEER_NODE_URL=http://localhost:7019/api/v1/
export JANZEER_RPC_URL=http://localhost:7019/rpc
export JANZEER_WS_URL=ws://localhost:7029/rpc/ws
export JANZEER_E2E_MNEMONIC="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
export JANZEER_E2E_RECIPIENT=0x598b1301acef3baba6ce25e38dd17b723f7b98b1
export JANZEER_NETWORK_ID=$([ "${NETWORK:-mainnet}" = mainnet ] && echo janzeer || echo "janzeer-${NETWORK}")
ENV
  # Dev net only: the first anchor's WALLET mnemonic (token CREATE needs a validator wallet). j_helper/out/anchors.json is
  # the git-ignored output of `nodes.sh fresh`. It is exported ONLY when that file describes the network that is running
  # here: its first anchor must be the node answering on :7019, and it must not be a mainnet ceremony file (those carry
  # "genesisWallets"). Since the mainnet ceremony that file holds REAL seeds — never print one into an environment.
  local anchors=$HERE/../../j_helper/out/anchors.json
  if [ -f "$anchors" ]; then
    local m
    m=$(python3 - "$anchors" <<'PYEOF' 2>/dev/null || true
import json, sys, urllib.request
a = json.load(open(sys.argv[1]))
if "genesisWallets" in a:
    sys.exit(0)
try:
    info = json.load(urllib.request.urlopen("http://localhost:7019/api/v1/info", timeout=3))["payload"]
except Exception:
    sys.exit(0)
first = a["anchors"][0]
if str(info.get("nodeKey", "")).lower() == str(first.get("nodePublic", "")).lower() and first.get("mnemonic"):
    print(first["mnemonic"])
PYEOF
)
    [ -n "$m" ] && echo "export JANZEER_E2E_VALIDATOR_MNEMONIC=\"$m\""
  fi
}
[ "${1:-}" = "--env" ] && { print_env; exit 0; }

[ -d "$NODE_REPO/run" ] || { echo "node repo not found at $NODE_REPO (set NODE_REPO)"; exit 1; }
cd "$NODE_REPO"
[ -f run/secrets.env ] || { echo "run/secrets.env missing — cp run/secrets.env.example run/secrets.env"; exit 1; }
ls build/libs/janzeer-*.jar >/dev/null 2>&1 || ./run/nodes.sh build
NODE_EXTRA_ARGS="--janzeer.dev-fund=$FAUCET ${NODE_EXTRA_ARGS:-}" ./run/nodes.sh start

echo "waiting for the API..." >&2
for _ in $(seq 1 90); do
  curl -sf http://localhost:7019/api/v1/info >/dev/null 2>&1 && break; sleep 2
done
curl -sf http://localhost:7019/api/v1/info >/dev/null || { echo "node 1 did not come up"; exit 1; }
echo "waiting for block production (needs 3 of 4 anchors)..." >&2
tip() { curl -s -X POST http://localhost:7019/rpc -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"janzeer_getTip"}' | sed -n 's/.*"height":\([0-9]*\).*/\1/p'; }
h0=$(tip || echo 0)
for _ in $(seq 1 60); do
  h=$(tip || echo 0); [ -n "$h" ] && [ "${h:-0}" -gt "${h0:-0}" ] && break; sleep 3
done
[ "${h:-0}" -gt "${h0:-0}" ] || { echo "no new block in 3 minutes — check run/logs"; exit 1; }
echo "network up, tip $h" >&2
print_env
