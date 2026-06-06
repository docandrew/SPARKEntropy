# SPARKEntropy CI

`ci/check.sh` is the reproducible hosted-CI lane. It prints tool versions,
builds the library, builds the test harnesses, and runs the quick functional
smoke test.

Formal proof and NIST SP 800-90B entropy assessment runs are intentionally not
part of default hosted CI.

To build and run the NIST SP 800-90B entropy assessment tools inside the Nix
environment:

```shell
nix develop --command bash ci/nist_entropy.sh
```

The optional first argument is the output byte count. The default is 1 MiB,
matching the documented reference run.

The assessment fails if:

- fewer than 1,000,000 bytes are assessed, unless `NIST_ALLOW_SMALL_SAMPLE=1`
  is set for a local dry run;
- any IID statistical test fails;
- IID or non-IID assessed min-entropy is below
  `NIST_MIN_BITS_PER_BYTE`, default `7.0`.
