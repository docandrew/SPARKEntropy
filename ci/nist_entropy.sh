#!/usr/bin/env bash
# NIST SP 800-90B assessment of the noise source, done the way the
# ESV-validated jitterentropy library does it (tests/raw-entropy in its
# source tree, and the "User Verification" section of its public-use
# validation documents):
#
#   1. record raw time deltas in timer ticks (the GCD Init measured is not
#      divided out, as in jitterentropy-hashtime), stuck indicator
#      disregarded, before any conditioning (tests/dump_raw.adb): a
#      sequential runtime set of NUM_EVENTS deltas, and a restart set of
#      NUM_RESTARTS fresh initialisations of NUM_EVENTS_RESTART deltas each
#      (SP 800-90B 3.1.1 and 3.1.4);
#   2. keep the low 8 bits of every delta (jitterentropy's extractlsb with
#      mask FF:8);
#   3. ea_non_iid -i -a -v <runtime> 8   and   ea_restart -n -v <restart> 8 H_I
#      with H_I = 1/OSR, the entropy the generator credits to one delta;
#   4. pass when the runtime min-entropy is at least 1/OSR bits per sample
#      and the restart assessment keeps that rate (its sanity check passes
#      and min(H_r, H_c, H_I) = H_I).
#
# With (256 + safety factor) * OSR non-stuck deltas per 256-bit block, a
# noise source that meets 1/OSR per delta yields full-entropy output; the
# conditioned output itself is not assessed here, as it is not in an ESV
# validation. If the runtime figure is below 1/OSR the platform needs a
# larger OSR: pass it to Init, and re-run with OSR=<n>.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

WORK="${TMPDIR:-/tmp}/sparkentropy-nist"
NIST_REPO="${NIST_REPO:-https://github.com/usnistgov/SP800-90B_EntropyAssessment.git}"
NIST_REF="${NIST_REF:-87c104d0ed4cbc96103e7b8b38d6f2c7e0a6b289}"
NIST_DIR="$WORK/SP800-90B_EntropyAssessment"

OSR="${OSR:-3}"                                   # Min_OSR in sparkentropy.ads
NUM_EVENTS="${NUM_EVENTS:-1000000}"               # jitterentropy: NUM_EVENTS
NUM_RESTARTS="${NUM_RESTARTS:-1000}"              # jitterentropy: NUM_RESTART
NUM_EVENTS_RESTART="${NUM_EVENTS_RESTART:-1000}"  # jitterentropy: NUM_EVENTS_RESTART
ALLOW_SMALL_SAMPLE="${NIST_ALLOW_SMALL_SAMPLE:-0}"

RUNTIME="$WORK/raw-runtime"
RESTART="$WORK/raw-restart"
RUNTIME_OUT="$WORK/ea_non_iid_runtime.out"
RESTART_OUT="$WORK/ea_restart.out"

if ! [[ "$OSR" =~ ^[0-9]+$ ]] || [ "$OSR" -lt 1 ] || [ "$OSR" -gt 20 ]; then
  echo "OSR must be an integer in 1 .. 20 (got '$OSR')" >&2
  exit 2
fi
H_I="$(awk -v o="$OSR" 'BEGIN { printf("%.6f", 1.0 / o) }')"

if [ "$ALLOW_SMALL_SAMPLE" != "1" ] &&
   { [ "$NUM_EVENTS" -lt 1000000 ] || [ "$((NUM_RESTARTS * NUM_EVENTS_RESTART))" -lt 1000000 ]; }; then
  echo "refusing to assess fewer than 1,000,000 samples (SP 800-90B 3.1.1);" >&2
  echo "set NIST_ALLOW_SMALL_SAMPLE=1 for a local dry run" >&2
  exit 2
fi

mkdir -p "$WORK"

if [ ! -d "$NIST_DIR/.git" ]; then
  echo "== initializing NIST SP800-90B EntropyAssessment checkout =="
  git clone --no-checkout --filter=blob:none "$NIST_REPO" "$NIST_DIR"
fi
echo "== fetching NIST SP800-90B EntropyAssessment ref $NIST_REF =="
git -C "$NIST_DIR" fetch --depth 1 origin "$NIST_REF"
git -C "$NIST_DIR" checkout --detach FETCH_HEAD

echo "== building NIST tools =="
JSONCPP_CFLAGS="$(pkg-config --cflags jsoncpp)"
JSONCPP_LIBS="$(pkg-config --libs jsoncpp)"
make -C "$NIST_DIR/cpp" \
  ARCH=generic \
  CXXFLAGS="-std=c++17 -fopenmp -O2 -ffloat-store $JSONCPP_CFLAGS" \
  SHARED_LIB="$JSONCPP_LIBS -lcrypto"

echo "== building SPARKEntropy raw-delta recorder =="
(
  cd "$ROOT"
  alr -n --no-tty build
  alr -n --no-tty exec -- gprbuild -P test_entropy.gpr
)

echo "== recording $NUM_EVENTS runtime deltas =="
( cd "$ROOT" && ./obj/tests/dump_raw "$NUM_EVENTS" 1 "$RUNTIME" )
echo "== recording $NUM_RESTARTS restarts x $NUM_EVENTS_RESTART deltas =="
( cd "$ROOT" && ./obj/tests/dump_raw "$NUM_EVENTS_RESTART" "$NUM_RESTARTS" "$RESTART" )

echo "== ea_non_iid (runtime, low 8 bits of each delta) =="
"$NIST_DIR/cpp/ea_non_iid" -i -a -v "$RUNTIME.lsb8" 8 | tee "$RUNTIME_OUT"

echo "== ea_restart (H_I = 1/OSR = $H_I) =="
"$NIST_DIR/cpp/ea_restart" -n -v "$RESTART.lsb8" 8 "$H_I" | tee "$RESTART_OUT"

echo "== acceptance criteria (jitterentropy's: at least 1/OSR bits per delta) =="
echo "OSR: $OSR   required min-entropy per delta: $H_I"

RUNTIME_MIN="$(awk '/min\(H_original, 8 X H_bitstring\):/ { value = $NF } END { print value }' "$RUNTIME_OUT")"
if [ -z "$RUNTIME_MIN" ]; then
  echo "FAIL: runtime min-entropy not found in ea_non_iid output" >&2
  exit 1
fi
# The smallest OSR this platform supports, for the record
OSR_NEEDED="$(awk -v h="$RUNTIME_MIN" 'BEGIN { o = int(1 / h); if (o * h < 1) o++; if (o < 3) o = 3; print o }')"
echo "runtime min-entropy per delta: $RUNTIME_MIN   (smallest admissible OSR: $OSR_NEEDED)"
awk -v v="$RUNTIME_MIN" -v t="$H_I" 'BEGIN { exit !((v + 0.0) >= (t + 0.0)) }' || {
  echo "FAIL: runtime min-entropy $RUNTIME_MIN < 1/OSR = $H_I bits per delta; this platform needs OSR >= $OSR_NEEDED" >&2
  exit 1
}

if grep -q -i 'sanity check failed' "$RESTART_OUT"; then
  echo "FAIL: restart sanity check failed (a restart row or column is too repetitive)" >&2
  exit 1
fi
grep -q 'Validation Test Passed' "$RESTART_OUT" || {
  echo "FAIL: ea_restart did not report 'Validation Test Passed'" >&2
  exit 1
}
RESTART_MIN="$(awk '/min\(H_r, H_c, H_I\):/ { value = $NF } END { print value }' "$RESTART_OUT")"
if [ -z "$RESTART_MIN" ]; then
  echo "FAIL: restart min-entropy not found in ea_restart output" >&2
  exit 1
fi
echo "restart min(H_r, H_c, H_I): $RESTART_MIN"
awk -v v="$RESTART_MIN" -v t="$H_I" 'BEGIN { exit !((v + 0.0) >= (t + 0.0) - 1e-6) }' || {
  echo "FAIL: restart assessment $RESTART_MIN < 1/OSR = $H_I (a restart row or column falls below the claimed rate)" >&2
  exit 1
}

echo "PASS: noise source provides at least 1/OSR = $H_I bits of min-entropy per delta, stable across restarts"
