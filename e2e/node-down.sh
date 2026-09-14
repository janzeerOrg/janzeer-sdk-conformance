#!/usr/bin/env bash
set -euo pipefail
NODE_REPO=${NODE_REPO:-$(cd "$(dirname "$0")" && pwd)/../../backend_v03}
cd "$NODE_REPO" && ./run/nodes.sh stop
