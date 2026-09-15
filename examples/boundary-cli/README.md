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
$ printf 'a\nb\n' > /tmp/boundary-sample.my
$ mylang run examples/boundary-cli/main.my -- /tmp/boundary-sample.my
{"lines":2,"characters":4}
$ MYLANG_ACCEPT_MODE=1 mylang run examples/boundary-cli/main.my -- /tmp/boundary-sample.my
reading /tmp/boundary-sample.my
{"lines":2,"characters":4}
```
