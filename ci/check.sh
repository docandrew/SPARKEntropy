#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ci/versions.sh
ci/build.sh

echo "== smoke test =="
./obj/tests/test_entropy

