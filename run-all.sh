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
                          && run "sdk_kotlin e2e"        bash -c "cd '$ROOT/sdk_kotlin' && ./gradlew -q :janzeer-sdk-client:e2eTest -Djanzeer.node.url=$JANZEER_NODE_URL -Djanzeer.rpc.url=$JANZEER_RPC_URL -Djanzeer.ws.url=$JANZEER_WS_URL"
# Python: the SDK's own virtualenv when it exists (python -m venv .venv && pip install -e ".[dev]"), else the python3 on PATH
PY=python3; [ -x "$ROOT/sdk_python/.venv/bin/python" ] && PY="$ROOT/sdk_python/.venv/bin/python"
[ -d "$ROOT/sdk_python" ] && run "sdk_python unit+vectors" bash -c "cd '$ROOT/sdk_python' && '$PY' -m pytest -q" \
                          && run "sdk_python e2e"          bash -c "cd '$ROOT/sdk_python' && '$PY' -m pytest -q -m e2e tests/e2e"
command -v go >/dev/null 2>&1 || { [ -x "$HOME/sdk/go/bin/go" ] && export PATH="$HOME/sdk/go/bin:$PATH"; }
[ -d "$ROOT/sdk_go" ]     && run "sdk_go unit+vectors"   bash -c "cd '$ROOT/sdk_go' && go test -count=1 ./..." \
                          && run "sdk_go e2e"            bash -c "cd '$ROOT/sdk_go' && go test -count=1 -tags e2e -run TestE2E ."
[ -f "$ROOT/j_frontend/scripts/wallet-parity-check.mjs" ] && run "j_frontend parity" bash -c "cd '$ROOT/j_frontend' && node scripts/wallet-parity-check.mjs"
[ -f "$ROOT/jpong/web/package.json" ] && run "jpong/web parity" bash -c "cd '$ROOT/jpong/web' && npm run --silent test:wallet-parity"
[ -f "$ROOT/wallet/pubspec.yaml" ] && run "wallet (Flutter) parity" bash -c "cd '$ROOT/wallet' && flutter test test/janzeer_crypto_parity_test.dart"
exit $fail
