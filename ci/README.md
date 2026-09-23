# SPARKEntropy CI

`ci/check.sh` is the reproducible hosted-CI lane. It prints tool versions,
builds the library, builds the test harnesses, and runs the quick functional
smoke test.

Formal proof is intentionally not part of default hosted CI.

The NIST SP 800-90B assessment has its own hosted workflow on pull
requests, pushes to main/master, and manual dispatch. It is separated from the
quick build/smoke lane because it downloads and builds the NIST assessment
tooling and records two million time deltas.

To run it inside the Nix environment:

```shell
nix develop --command bash ci/nist_entropy.sh
```

It follows the procedure the ESV-validated jitterentropy library uses for its
own validation: raw time deltas are recorded before conditioning with the
stuck indicator disregarded (`tests/dump_raw.adb`), the low 8 bits of each
delta are assessed, and the pass mark is the entropy the generator credits
to one delta, 1/OSR bits.

- runtime: `NUM_EVENTS` sequential deltas (default 1,000,000) through
  `ea_non_iid -i -a -v <data> 8`; the reported `min(H_original, 8 X
  H_bitstring)` must be at least `1/OSR`;
- restart: `NUM_RESTARTS` fresh initialisations of `NUM_EVENTS_RESTART`
  deltas each (default 1000 x 1000) through `ea_restart -n -v <data> 8
  1/OSR`; its sanity check must pass and every row and column must keep the
  rate, i.e. `min(H_r, H_c, H_I)` equals `H_I`.

`OSR` defaults to 3 (`Min_OSR`). If the runtime figure comes out below
`1/OSR`, the lane prints the smallest OSR the platform supports; pass that
value to `Init` on such a platform and validate with `OSR=<n>`.

The lane refuses fewer than 1,000,000 samples in either set unless
`NIST_ALLOW_SMALL_SAMPLE=1` is set for a local dry run.
