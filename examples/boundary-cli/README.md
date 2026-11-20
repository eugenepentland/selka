# Boundary acceptance CLI

A small two-module program that exercises the Wave 2 program boundary:

- `main(args: list[str], fs: Filesystem, env: Environment)` receives guest
  arguments, reads the named source file through the filesystem capability, and
  consults the process environment through the explicit `Environment` authority;
- `print` publishes machine-readable output on stdout, `eprint` sends an
  optional trace to stderr, and `Err(message)` produces the checked failure
  status;
- `summary.render` is reusable from guest tests and ordinary imports.

Run it from the repository root:

```console
$ printf 'a\nb\n' > /tmp/boundary-sample.selka
$ selka run examples/boundary-cli/main.selka -- /tmp/boundary-sample.selka
{"lines":2,"characters":4}
$ SELKA_ACCEPT_MODE=1 selka run examples/boundary-cli/main.selka -- /tmp/boundary-sample.selka
reading /tmp/boundary-sample.selka
{"lines":2,"characters":4}
```
