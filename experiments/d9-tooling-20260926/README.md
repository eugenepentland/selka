# D9 tooling fixes

`starters/` contains formatter-clean copies of the nine P4 task starters from
`/home/epentland/ai/trials/value-semantics-20260924/tasks/*/starter/*.my`.
They retain the original signatures, comments and `todo` bodies; only formatting
changed. Use these copies when preparing another trial. The original pilot kit
and its recorded sessions remain historical evidence.

T2 also formats the repository's current `examples/**/*.my` files. The old
`restrict_resource[read](fs)` spelling in `examples/attenuation.my` is migrated
to its supported replacement, `fs.read_only()`, so the example parses.

To verify the shipped examples and starter copies after a Debug build:

```bash
rg --files examples experiments/d9-tooling-20260926/starters -g '*.my' \
  | while IFS= read -r path; do zig-out/bin/mylang fmt "$path" --check || exit; done
```

`fmt --check`, `fmt-module --check` and `fmt-project --check` now report the
first differing location as `path:line:column: formatting differs`. This is
the location in the input file, including its end when a final newline is
missing. The commands keep their existing exit statuses and output streams.
