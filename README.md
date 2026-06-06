# SPARKEntropy

A SPARK/Ada implementation of CPU-jitter–based entropy collection,
following NIST SP 800-90B.  The output bytes are suitable as a
`Random_Bytes_Fn` for `sparktls`, the `sparktls_cli` cert/CSR/key
generators, and any other consumer that needs cryptographically
strong randomness without relying on `/dev/urandom`.

## Architecture

The pipeline has two stages.  From the perspective of a consumer
calling `Generate (State, Output, OK)`, both stages together *are*
the noise source — there is no separate "raw output" surface.

1. **Noise**.  `SPARKEntropy.Noise` repeatedly times a deliberately
   variable CPU workload (Keccak-f[1600] permutations on a scratch
   `Jitter_State`, plus pseudo-random memory accesses to perturb the
   cache).  Each iteration's wall-time delta `Dt` is a 64-bit
   timestamp difference; the lowest bits carry the jitter signal.
2. **Conditioning**.  Every `Dt` is folded into a SHAKE-256 sponge
   (`SHAKE.SHAKE256` from the [damaki/libkeccak](https://github.com/damaki/libkeccak)
   Alire crate).  `Generate` extracts from a *copy* of the sponge so
   the original keeps absorbing future jitter — the live sponge
   stays in `Updating` state for the lifetime of the connection.

Health tests (NIST SP 800-90B §4.4 RCT, APT, and a lag predictor)
run on every sample. `Generate` returns `OK := False` on health-test failure;
callers should reinitialize the entropy state before retrying.

`SPARKEntropy.Jitter_Permute` is a small in-house Keccak-f[1600]
permutation kept *only* as the variable-time CPU stressor in
`Hash_Loop`.  All cryptographically meaningful Keccak operations go
through libkeccak.

## Platform Support

SPARKEntropy currently supports Linux on `x86_64` and `aarch64`.

The timer backend is architecture-specific:

- `x86_64`: `rdtsc`
- `aarch64`: `CNTVCT_EL0`

Other architectures intentionally fail at compile time until a timer backend
with suitable resolution is added and assessed.

```
alr build
```

The Alire crate brings in `libkeccak ^3.0.0` automatically.

## Running

The package exposes:

```ada
Init     (State : out Entropy_State; OK : out Boolean);
Generate (State : in out Entropy_State; Output : out Byte_Seq; OK : out Boolean);
```

`Init` runs a 1024-sample power-up self-test.  `OK := False` if the
host timer is too coarse for jitter (e.g. inside some VMs).

## Testing

There is a quick functional smoke test:

```
alr exec -- gprbuild -P test_entropy.gpr
./obj/tests/test_entropy
```

You should see `Init OK` followed by five 32-byte hex dumps and
`PASS`.

## NIST SP 800-90B entropy assessment

`tests/dump_entropy.adb` writes a binary file of `Generate()` output
that can be fed to NIST's
[SP 800-90B EntropyAssessment](https://github.com/usnistgov/SP800-90B_EntropyAssessment)
tools (`ea_iid`, `ea_non_iid`, `ea_restart`).

### Building the NIST tools (Ubuntu/Debian)

```
sudo apt-get install libbz2-dev libdivsufsort-dev libjsoncpp-dev \
                     libssl-dev libmpfr-dev libgmp-dev build-essential
git clone https://github.com/usnistgov/SP800-90B_EntropyAssessment.git
cd SP800-90B_EntropyAssessment/cpp && make
```

### Running the assessments

From the sparkentropy directory:

```
alr exec -- gprbuild -P test_entropy.gpr
./obj/tests/dump_entropy                      # writes 1 MB to entropy.bin
$NIST/cpp/ea_iid     -i -a entropy.bin 8      # IID estimator
$NIST/cpp/ea_non_iid -i -a entropy.bin 8      # non-IID (conservative) estimator
```

With Nix, the tool build and entropy assessment can be run as:

```
nix develop --command bash ci/nist_entropy.sh
```

The reproducible assessment gate requires at least 1,000,000 bytes, passing
IID statistical tests, and assessed IID/non-IID min-entropy of at least
7.0 bits/byte by default. Override the threshold with
`NIST_MIN_BITS_PER_BYTE` if needed.

`-i` is the initial entropy-estimation pass; `-a` reports all
estimators; `8` is the symbol size in bits.

### Reference results (libkeccak swap, 2026-04-29)

Hardware: Linux 6.8 x86_64.  1 MB sample.

**`ea_iid`:**

| Estimator                    | Value (bits) |
|------------------------------|--------------|
| H_original                   | 7.881665     |
| H_bitstring                  | 0.998626     |
| min(H_original, 8·H_bitstring) | 7.881665   |
| chi-square tests             | PASS         |
| longest-repeated-substring   | PASS         |
| IID permutation tests        | PASS         |

**`ea_non_iid`:**

| Estimator                    | Value (bits) |
|------------------------------|--------------|
| H_original                   | 7.349074     |
| H_bitstring                  | 0.909275     |
| min(H_original, 8·H_bitstring) | 7.274199   |

Both estimators report `min` well above NIST's 0.5 bits/byte floor
that's commonly used for accreditation, with the IID estimator
within 0.12 bits of the 8.0 ideal and all three IID statistical
tests passing.

### Restart test

NIST SP 800-90B §3.1.4 also requires a **restart test**: 1000
re-initializations of the noise source, each producing 1000
samples, used to confirm that the entropy estimate is stable
across restarts.

`tests/dump_restart.adb` does this — call it once after building:

```
./obj/tests/dump_restart                 # writes 1,000,000 bytes to restart.bin
$NIST/cpp/ea_restart -i restart.bin 8 7.27   # H_I = 7.27 from ea_non_iid
```

Reference run on the libkeccak swap (2026-04-29):

| Quantity                        | Value     |
|---------------------------------|-----------|
| X_max (sanity check)            | 16  (cutoff: 24) |
| H_r  (row min-entropy)          | 7.877522  |
| H_c  (column min-entropy)       | 7.877522  |
| H_I  (input)                    | 7.270000  |
| IID statistical tests           | PASS      |
| Restart validation test         | PASS      |
| **min(H_r, H_c, H_I)**          | **7.270 bits/byte** |

The dump takes ~3 minutes wall-time (~1000 power-up self-tests at
1024 samples each, plus 1000 × 1000 conditioned-output samples)
and the assessment itself is a few seconds.

### Reproducing results

The `dump_entropy` binary is deterministic in size but not in
content (each run reseeds from real CPU jitter).  Re-running the
assessment after any code change in `SPARKEntropy.Noise`,
`SPARKEntropy.Jitter_Permute`, or the libkeccak version is the
recommended regression test for the noise source.

## Formal verification

Run `alr gnatprove --mode=prove --level=1 -j4`.  As of the libkeccak
swap (2026-04-29):

| Category              | Total | Flow / Proved | Justified | Unproved |
|-----------------------|-------|---------------|-----------|----------|
| Data Dependencies     | 899   | 899           | .         | 0        |
| Flow Dependencies     | 371   | 371           | .         | 0        |
| Initialization        | 5106  | 5028          | 78        | 0        |
| Non-Aliasing          | 232   | 232           | .         | 0        |
| Run-time Checks       | 10541 | 10541         | .         | **0**    |
| Assertions            | 1415  | 1415          | .         | **0**    |
| Functional Contracts  | 2189  | 2189          | .         | **0**    |
| Termination           | 353   | 353           | .         | **0**    |
| **Total**             | 21106 | 21028         | 78        | **0**    |

The 78 justified checks are pre-existing libkeccak annotations.
sparkentropy itself contributes zero unproved or justified checks
at SPARK Silver (absence of run-time errors).

## License

BSD-3-Clause.  See `LICENSE`.

Embeds NIST test vectors and references the NIST SP 800-90B
EntropyAssessment tool suite, which is public-domain
NIST-developed software.

Depends on `libkeccak` (BSD-3-Clause, Daniel King) for the
SHAKE-256 conditioning sponge.
