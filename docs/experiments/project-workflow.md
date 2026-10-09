# Combined project feedback

Use the existing checked navigation and declared verification infrastructure through
one command, from any working directory:

```sh
python3 scripts/project.py --compiler zig-out/bin/selka \
  --entry path/to/app/main.selka --manifest path/to/app/verify.json \
  --query validate --cache-dir /path/outside/app/cache \
  --report /path/to/evidence/attempt-001.json
```

The manifest lives beside main.selka; its commands run relative to that directory.
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

The command prints one `project-feedback-v1` JSON receipt and saves a full
`project-workflow-v1` report. The receipt contains the verdict, elapsed time,
compiler and manifest hashes, hashes of the source and project inventories,
identity stability, and an absolute `report_path`. Inventory hashes use SHA-256
over the inventory's UTF-8 JSON with sorted keys and compact separators.

Verification counts describe selected **steps**, including their passed, failed,
blocked, executed, and cached counts. `declared_test_steps` counts selected test,
parity, or mutation steps; it does not count individual test cases. The receipt's
`test_case_count` is explicitly null because arbitrary verification commands do
not provide a reliable case count. Passing selected steps does not imply full
manifest acceptance; both verdicts remain visible.

Success output excludes source inventories, navigation snippets, per-step rows,
and command streams. Failures show at most three steps and two command excerpts
per shown step, with each text field limited to 512 characters plus a truncation
marker. Omitted counts direct readers to the report. Compiler failures also emit
bounded diagnostics. The saved report retains all captured streams (subject to
the existing verification output budgets), navigation, inventories, and verification
progress logging. Add `--details` to print that full report on stdout as well;
`--query` and `--symbol` select context in the saved report in either mode.

Each attempt requires a new report path; existing reports are never overwritten.
Exit 0 means checked source and passing declared tests on unchanged inputs; exit 1
means a source/test/staleness failure; exit 2 means invocation/infrastructure failure.
Navigation caches validate source and compiler identities; v2 test caches must be
outside the source directory. Store reports outside that directory as well to avoid
unnecessary verification snapshot churn. Exact agent turns/tokens are not measured.

Exports may now appear before, between, or after top-level declarations. CLI
regressions execute each placement and preserve located duplicate-export
diagnostics. Older experiment reports describing `E_EXPORT_PLACEMENT` record the
previous grammar; other existing JSON diagnostics retain their contracts.
