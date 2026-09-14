#!/usr/bin/env bash
# Owner-only: parity suites + e2e of every SDK (and the parity checks of the apps) against ONE running network.
#   ./e2e/node-up.sh && ./run-all.sh ; ./e2e/node-down.sh
#   NETWORK=testnet ./e2e/node-up.sh && NETWORK=testnet ./run-all.sh   # same, on the janzeer-testnet id (proves the SDKs' networkId knob)
# Skips any repo that is not present. Exit 1 if anything fails.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
eval "$("$HERE/e2e/node-up.sh" --env)"
export JAVA_HOME=${JAVA_HOME:-$HOME/.sdkman/candidates/java/17.0.19-librca}; export PATH=$JAVA_HOME/bin:$PATH
fail=0
run() { local name=$1; shift; echo "=== $name"; if "$@"; then echo "=== $name PASS"; else echo "=== $name FAIL"; fail=1; fi; }

run "vectors in sync" "$HERE/sync.sh" --check
[ -d "$ROOT/sdk_ts" ]     && run "sdk_ts unit+vectors"   bash -c "cd '$ROOT/sdk_ts' && npm test --silent" \
                          && run "sdk_ts e2e"            bash -c "cd '$ROOT/sdk_ts' && npm run e2e --silent"
[ -d "$ROOT/sdk_dart" ]   && run "sdk_dart unit+vectors" bash -c "cd '$ROOT/sdk_dart' && dart test" \
                          && run "sdk_dart e2e"          bash -c "cd '$ROOT/sdk_dart' && dart test --tags e2e"
[ -d "$ROOT/sdk_kotlin" ] && run "sdk_kotlin build+test" bash -c "cd '$ROOT/sdk_kotlin' && ./gradlew -q build" \
                          && run "sdk_kotlin e2e"        bash -c "cd '$ROOT/sdk_kotlin' && ./gradlew -q :client:e2eTest -Djanzeer.node.url=$JANZEER_NODE_URL -Djanzeer.rpc.url=$JANZEER_RPC_URL -Djanzeer.ws.url=$JANZEER_WS_URL"
[ -d "$ROOT/sdk_go" ]     && run "sdk_go"                bash -c "cd '$ROOT/sdk_go' && go test ./... && go test -tags e2e ./e2e/..."
[ -f "$ROOT/j_frontend/scripts/wallet-parity-check.mjs" ] && run "j_frontend parity" bash -c "cd '$ROOT/j_frontend' && node scripts/wallet-parity-check.mjs"
[ -f "$ROOT/jpong/web/package.json" ] && run "jpong/web parity" bash -c "cd '$ROOT/jpong/web' && npm run --silent test:wallet-parity"
[ -f "$ROOT/wallet/pubspec.yaml" ] && run "wallet (Flutter) parity" bash -c "cd '$ROOT/wallet' && flutter test test/janzeer_crypto_parity_test.dart"
exit $fail
