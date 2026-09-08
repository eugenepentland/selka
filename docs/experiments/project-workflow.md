# Combined project feedback

Use the existing checked navigation and declared verification infrastructure through
one command, from any working directory:

```sh
python3 scripts/project.py --compiler zig-out/bin/mylang \
  --entry path/to/app/main.my --manifest path/to/app/verify.json \
  --query validate --cache-dir /path/outside/app/cache \
  --report /path/to/evidence/attempt-001.json
```

The manifest lives beside main.my; its commands run relative to that directory.
Version 1 manifests execute every selected command. Version 2 retains existing
explicit input/tool completeness, invalidation and successful-receipt caching.
`--only` selects declared step IDs and prerequisites; navigation never guesses
which tests prove a change. At least one test/parity/mutation step must be selected.

A checked source-pinned navigation index supplies the type-check verdict and up to
20 context symbols/relationships with 8 KiB snippets. Broken source emits compiler
JSON diagnostics and skips tests. Successful compilation runs declared checks;
project-file, compiler or manifest changes during execution invalidate acceptance.
The report includes a conservative regular-file project inventory, including Python
tests and JSON fixtures; v2 verification adds its declared input/tool snapshot.
Tests must put generated artifacts outside the source directory. This is a local developer workflow, not hostile-process
confinement or a proof that declared tests cover all behavior.

The command prints compact JSON and saves full verification streams and identities.
Each attempt requires a new report path; existing reports are never overwritten.
Exit 0 means checked source and passing declared tests on unchanged inputs; exit 1
means a source/test/staleness failure; exit 2 means invocation/infrastructure failure.
Navigation caches validate source and compiler identities; v2 test caches must be
outside the source directory. Store reports outside that directory as well to avoid
unnecessary verification snapshot churn. Exact agent turns/tokens are not measured.

The export-placement diagnostic now identifies the keyword with
`E_EXPORT_PLACEMENT` and tells agents to move the declaration after imports and
before types/functions. CLI regression tests execute the corresponding repaired
programs. Other existing JSON diagnostics retain their contracts.
