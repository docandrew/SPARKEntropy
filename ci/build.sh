#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export ALR_NON_INTERACTIVE=1

echo "== default build =="
alr build

echo "== test build =="
alr exec -- gprbuild -P test_entropy.gpr

