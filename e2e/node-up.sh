#!/usr/bin/env bash
# Boots the local 4-anchor Janzeer network with the dev faucet funding the canonical test wallet, waits until
# blocks are being produced, and prints the JANZEER_* environment every SDK e2e test reads.
#   ./e2e/node-up.sh            # start (builds the jar first if missing)
#   eval "$(./e2e/node-up.sh --env)"   # only print the exports (net already running)
# Requires the node repo as a sibling: ../backend_v03 (private; the conformance kit itself has no node code).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NODE_REPO=${NODE_REPO:-$HERE/../../backend_v03}
FAUCET=${FAUCET:-0x06e1c0fa9955a700876f8cb0acc7f13fba9fb8ba:100000}
export JAVA_HOME=${JAVA_HOME:-$HOME/.sdkman/candidates/java/17.0.19-librca}
export PATH=$JAVA_HOME/bin:$PATH

print_env() {
  cat <<ENV
export JANZEER_NODE_URL=http://localhost:7019/api/v1/
export JANZEER_RPC_URL=http://localhost:7019/rpc
export JANZEER_WS_URL=ws://localhost:7029/rpc/ws
export JANZEER_E2E_MNEMONIC="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
export JANZEER_E2E_RECIPIENT=0x598b1301acef3baba6ce25e38dd17b723f7b98b1
ENV
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
