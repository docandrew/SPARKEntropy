# SPARKEntropy

A SPARK/Ada implementation of CPU-jitter–based entropy collection,
following [NIST SP 800-90B](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-90B.pdf).
The output bytes are suitable as a `Random_Bytes_Fn` for `sparktls`, the
`sparktls_cli` cert/CSR/key generators, and any other consumer that needs
cryptographically strong randomness without relying on `/dev/urandom`.

This crate is a port of the FIPS-certified userspace
(Jitterentropy)[https://github.com/smuellerDD/jitterentropy-library] library but
is NOT FIPS-certified.

## Architecture

See the original (Jitterentropy)[https://github.com/smuellerDD/jitterentropy-library]
library for a description of the entropy source, conditioning and health tests.

## Platform Support

SPARKEntropy currently supports Linux on `x86_64` and `aarch64`.

The timer backend is architecture-specific:

- `x86_64`: `rdtsc`
- `aarch64`: `CNTVCT_EL0`

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
tools (`ea_iid`, `ea_non_iid`, `ea_restart`). See the `NIST` CI workflow for
an example of how to run the assessment and interpret results.

### Building the NIST tools (Ubuntu/Debian)

```
sudo apt-get install libbz2-dev libdivsufsort-dev libjsoncpp-dev \
                     libssl-dev libmpfr-dev libgmp-dev build-essential
git clone https://github.com/usnistgov/SP800-90B_EntropyAssessment.git
cd SP800-90B_EntropyAssessment/cpp && make
```

### Running the assessments

From the `sparkentropy` directory:

```shell
alr exec -- gprbuild -P test_entropy.gpr
./obj/tests/dump_entropy                      # writes 1 MB to entropy.bin
$NIST/cpp/ea_iid     -i -a entropy.bin 8      # IID estimator
$NIST/cpp/ea_non_iid -i -a entropy.bin 8      # non-IID (conservative) estimator
```

With Nix, the tool build and entropy assessment can be run as:

```shell
nix develop --command bash ci/nist_entropy.sh
```

The reproducible assessment gate requires at least 1,000,000 bytes, passing
IID statistical tests, and assessed IID/non-IID min-entropy of at least
7.0 bits/byte by default. Override the threshold with
`NIST_MIN_BITS_PER_BYTE` if needed.

`-i` is the initial entropy-estimation pass; `-a` reports all
estimators; `8` is the symbol size in bits.

### Reference results

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

This project is SPARK "silver" verified for absence of runtime errors (AoRTE).
This should not be construed as a formal proof of entropy properties or
functional correctness.

## License

BSD-3-Clause.  See `LICENSE`.

Embeds NIST test vectors and references the NIST SP 800-90B
EntropyAssessment tool suite, which is public-domain
NIST-developed software.

Depends on `libkeccak` (BSD-3-Clause, Daniel King) for the
SHAKE-256 conditioning sponge.
