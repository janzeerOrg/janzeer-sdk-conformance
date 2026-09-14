#!/usr/bin/env bash
# Propagates the canonical vectors to every SDK and app that vendors them, or verifies the copies.
#   ./sync.sh            # copy vectors/* into every known consumer, then refresh vectors/SHA256SUMS
#   ./sync.sh --check    # verify vectors/ against SHA256SUMS and every vendored copy against vectors/ (exit 1 on drift)
#   ./sync.sh --regen    # regenerate wallet-parity-vectors.json from the node's WalletParityVectorsTest first (needs ../backend_v03)
# Consumers are listed in CONSUMERS below (path relative to the workspace root; missing dirs are skipped).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
CONSUMERS=(
  "sdk_ts/test/vectors"
  "sdk_dart/test/vectors"
  "sdk_kotlin/core/src/test/resources/vectors"
  "sdk_go/internal/testdata"
  "j_frontend/test"
  "jpong/web/test"
  "wallet/test"
)
FILES=(wallet-parity-vectors.json vault-fixture.json)

regen() {
  local repo=$ROOT/backend_v03
  export JAVA_HOME=${JAVA_HOME:-$HOME/.sdkman/candidates/java/17.0.19-librca}; export PATH=$JAVA_HOME/bin:$PATH
  (cd "$repo" && ./gradlew test --tests "*WalletParityVectorsTest" -q)
  cp "$repo/build/wallet-parity-vectors.json" "$HERE/vectors/wallet-parity-vectors.json"
  echo "regenerated vectors/wallet-parity-vectors.json"
}

check() {
  local rc=0
  (cd "$HERE/vectors" && sha256sum -c --quiet SHA256SUMS) || rc=1
  for c in "${CONSUMERS[@]}"; do
    [ -d "$ROOT/$c" ] || continue
    for f in "${FILES[@]}"; do
      [ -f "$ROOT/$c/$f" ] || continue     # apps only vendor the parity file
      cmp -s "$HERE/vectors/$f" "$ROOT/$c/$f" || { echo "DRIFT: $c/$f differs from vectors/$f"; rc=1; }
    done
  done
  [ $rc -eq 0 ] && echo "vectors in sync" || echo "vectors OUT OF SYNC — run ./sync.sh"
  return $rc
}

case "${1:-}" in
  --check) check ;;
  --regen|"")
    [ "${1:-}" = "--regen" ] && regen
    for c in "${CONSUMERS[@]}"; do
      [ -d "$ROOT/$c" ] || continue
      for f in "${FILES[@]}"; do
        # apps (j_frontend, jpong/web, wallet) only take the parity file; SDK dirs take everything
        case "$c" in sdk_*) ;; *) [ "$f" = wallet-parity-vectors.json ] || continue ;; esac
        cp "$HERE/vectors/$f" "$ROOT/$c/$f" && echo "→ $c/$f"
      done
    done
    (cd "$HERE/vectors" && sha256sum "${FILES[@]}" > SHA256SUMS) && echo "SHA256SUMS refreshed"
    ;;
  *) echo "usage: $0 [--check|--regen]"; exit 1 ;;
esac
