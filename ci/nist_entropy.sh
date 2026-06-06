#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ALR_NON_INTERACTIVE=1
export NO_COLOR=1

WORK="${TMPDIR:-/tmp}/sparkentropy-nist"
NIST_REPO="${NIST_REPO:-https://github.com/usnistgov/SP800-90B_EntropyAssessment.git}"
NIST_REF="${NIST_REF:-87c104d0ed4cbc96103e7b8b38d6f2c7e0a6b289}"
NIST_DIR="$WORK/SP800-90B_EntropyAssessment"
OUT="$WORK/entropy.bin"
BYTES="${1:-1048576}"
MIN_SAMPLE_BYTES="${NIST_MIN_SAMPLE_BYTES:-1000000}"
MIN_BITS_PER_BYTE="${NIST_MIN_BITS_PER_BYTE:-7.0}"
ALLOW_SMALL_SAMPLE="${NIST_ALLOW_SMALL_SAMPLE:-0}"
IID_OUT="$WORK/ea_iid.out"
NON_IID_OUT="$WORK/ea_non_iid.out"

mkdir -p "$WORK"

if [ "$BYTES" -lt "$MIN_SAMPLE_BYTES" ] && [ "$ALLOW_SMALL_SAMPLE" != "1" ]; then
  echo "refusing to run NIST assessment with only $BYTES bytes" >&2
  echo "minimum is $MIN_SAMPLE_BYTES bytes; set NIST_ALLOW_SMALL_SAMPLE=1 for local dry runs" >&2
  exit 2
fi

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

echo "== building SPARKEntropy dump tool =="
(
  cd "$ROOT"
  alr -n --no-tty exec -- gprbuild -P test_entropy.gpr
)

echo "== generating $BYTES bytes =="
(
  cd "$ROOT"
  ./obj/tests/dump_entropy "$BYTES" "$OUT"
)

echo "== ea_iid =="
"$NIST_DIR/cpp/ea_iid" -i -a "$OUT" 8 | tee "$IID_OUT"

echo "== ea_non_iid =="
"$NIST_DIR/cpp/ea_non_iid" -i -a "$OUT" 8 | tee "$NON_IID_OUT"

extract_min_entropy() {
  awk '/min\(H_original, 8 X H_bitstring\):/ { value = $NF } END { print value }' "$1"
}

require_at_least() {
  local label="$1"
  local value="$2"
  local threshold="$3"
  awk -v label="$label" -v value="$value" -v threshold="$threshold" '
    BEGIN {
      if (value == "") {
        printf("FAIL: %s min-entropy was not found\n", label);
        exit 1;
      }
      if ((value + 0.0) < (threshold + 0.0)) {
        printf("FAIL: %s min-entropy %.6f < threshold %.6f bits/byte\n",
               label, value, threshold);
        exit 1;
      }
      printf("PASS: %s min-entropy %.6f >= threshold %.6f bits/byte\n",
             label, value, threshold);
    }'
}

IID_MIN="$(extract_min_entropy "$IID_OUT")"
NON_IID_MIN="$(extract_min_entropy "$NON_IID_OUT")"

echo "== NIST acceptance criteria =="
echo "sample bytes: $BYTES"
echo "minimum min-entropy threshold: $MIN_BITS_PER_BYTE bits/byte"

if [ "$ALLOW_SMALL_SAMPLE" != "1" ] &&
   grep -q '\*\*\* Warning: data contains less than 1000000 samples \*\*\*' \
     "$IID_OUT" "$NON_IID_OUT"; then
  echo "FAIL: NIST tools warned that sample size is below 1,000,000" >&2
  exit 1
fi

grep -q '\*\* Passed chi square tests' "$IID_OUT" || {
  echo "FAIL: IID chi-square tests did not pass" >&2
  exit 1
}
grep -q '\*\* Passed length of longest repeated substring test' "$IID_OUT" || {
  echo "FAIL: IID longest repeated substring test did not pass" >&2
  exit 1
}
grep -q '\*\* Passed IID permutation tests' "$IID_OUT" || {
  echo "FAIL: IID permutation tests did not pass" >&2
  exit 1
}

require_at_least "IID" "$IID_MIN" "$MIN_BITS_PER_BYTE"
require_at_least "non-IID" "$NON_IID_MIN" "$MIN_BITS_PER_BYTE"

echo "PASS: NIST SP 800-90B entropy assessment criteria satisfied"
