#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export ALR_NON_INTERACTIVE=1
export NO_COLOR=1
if [ -z "${SPARKENTROPY_HOST_ARCH:-}" ]; then
  case "$(uname -m)" in
    x86_64|amd64) SPARKENTROPY_HOST_ARCH=x86_64 ;;
    aarch64|arm64) SPARKENTROPY_HOST_ARCH=aarch64 ;;
    *) SPARKENTROPY_HOST_ARCH=unsupported ;;
  esac
  export SPARKENTROPY_HOST_ARCH
fi

echo "== default build =="
alr -n --no-tty build

echo "== test build =="
alr -n --no-tty exec -- gprbuild -P test_entropy.gpr
