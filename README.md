# SPARKEntropy

A SPARK/Ada implementation of CPU-jitter–based entropy collection,
following [NIST SP 800-90B](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-90B.pdf).

This crate is a port of the FIPS-certified userspace
(Jitterentropy)[https://github.com/smuellerDD/jitterentropy-library] library but
is NOT FIPS-certified. It is intended for evaluation and research purposes, and
should not be treated as a drop-in replacement for a certified entropy source
in production use.

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

The assessment follows the procedure the ESV-validated
[jitterentropy](https://github.com/smuellerDD/jitterentropy-library)
library uses for its own validation (`tests/raw-entropy` there, and the
"User Verification" section of its public-use validation documents):
the noise source is assessed on its **raw time deltas**, recorded before
any conditioning with the stuck indicator disregarded, and the pass mark
is the entropy the generator credits to one delta, **1/OSR bits**. With
`(256 + safety factor) * OSR` non-stuck deltas absorbed per 256-bit
block, a noise source that meets that rate yields full-entropy output.
The conditioned output is not what SP 800-90B assesses (Section 3.1.1
asks for raw data), so it is not gated; `tests/dump_entropy.adb` remains
for anyone who wants to look at it.

`tests/dump_raw.adb` is the recorder (jitterentropy's
`jitterentropy-hashtime` equivalent); `ci/nist_entropy.sh` runs the whole
lane, and the hosted `NIST Entropy` workflow runs it on every pull
request. With Nix:

```shell
nix develop --command bash ci/nist_entropy.sh
```

Steps, with the [SP 800-90B EntropyAssessment](https://github.com/usnistgov/SP800-90B_EntropyAssessment)
tools at `$NIST`:

```shell
./obj/tests/dump_raw 1000000 1    raw-runtime   # 3.1.1 sequential dataset
./obj/tests/dump_raw 1000    1000 raw-restart   # 3.1.4 restart dataset
$NIST/cpp/ea_non_iid -i -a -v raw-runtime.lsb8 8
$NIST/cpp/ea_restart -n -v raw-restart.lsb8 8 0.333   # H_I = 1/OSR
```

`.lsb8` holds the low 8 bits of every delta (jitterentropy's `extractlsb`
with mask `FF:8`); `.u64` keeps the full deltas. Deltas are raw timer
ticks: the recorder sets the timer GCD that `Init` measured to 1, as
`jitterentropy-hashtime` does (`--counter-ticks` records the GCD-divided
deltas the generator actually absorbs). The lane passes when the
runtime `min(H_original, 8 X H_bitstring)` is at least `1/OSR`, the
restart sanity check passes, and `min(H_r, H_c, H_I)` equals `H_I`, that
is, no restart row or column falls below the claimed rate.

### Reference results

Linux 6.8 x86_64, Ryzen 9 9950X3D (TSC step 43 ticks), OSR 3, 2026-09-22.

**Runtime, `ea_non_iid` on 1,000,000 deltas:**

| Estimator                        | Value (bits per delta) |
|----------------------------------|------------------------|
| H_original                       | 2.445842 |
| H_bitstring                      | 0.281950 |
| min(H_original, 8 X H_bitstring) | **2.255602** |
| required (1/OSR)                 | 0.333333 |

**Restart, `ea_restart` on 1000 x 1000 deltas:**

| Quantity                    | Value |
|-----------------------------|-------|
| X_max (sanity check)        | 224 (cutoff 849) |
| H_r (row min-entropy)       | 2.409826 |
| H_c (column min-entropy)    | 2.459159 |
| H_I (input, 1/OSR)          | 0.333000 |
| Validation test             | PASS |
| **min(H_r, H_c, H_I)**      | **0.333000** |

For comparison, jitterentropy's own `jitterentropy-hashtime` (library
commit 7c65405, default settings, 256 KB memory block) recorded on the
same machine minutes apart and assessed with the same tool gave
H_original 2.950809, H_bitstring 0.349159, min 2.793271 bits per delta;
its delta distribution (multiples of the 43-tick TSC step, about ten
common values, median 16125 ticks) matches this crate's (median about
18200 ticks). Recording takes a few seconds per set; the assessments a
few minutes.

### Choosing the oversampling rate

`Init` takes an `OSR` argument (default `Min_OSR` = 3, maximum 20), the
number of non-stuck deltas collected per output bit; the health-test
cutoffs scale with it. On a platform whose runtime figure comes out below
`1/OSR`, the lane prints the smallest admissible OSR; pass that value to
`Init` there and validate with `OSR=<n>`. This is how jitterentropy's
validated deployments are tuned: the certified operating environments
carry their own OSR, chosen from the same measurement.

Re-run the assessment after any change to `SPARKEntropy.Noise`,
`SPARKEntropy.Health`, the timer, or the libkeccak version.

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
