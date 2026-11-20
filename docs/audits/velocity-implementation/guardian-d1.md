# Guardian feedback: package D1 (structured native trap detail)

Date: 2026-09-15. Worktree `velocity-d1`, branch `codex/velocity-d1`.

Guardian ran automatically on every `zig build`, `zig build test-units` and
`zig build test-qbe` invocation. All findings below were fixed in the package
commit rather than accepted; `guardian-check` reports 88/88 checks passing in
the diff-scoped mode for the touched files.

## Good findings (all fixed)

- `type-size` rejected a `Detail` with eight fields. Restructuring the five
  captured values into a nested `Values` struct kept the frozen field set while
  satisfying the cap; the transport `present` bitmask still describes them.
- `function-size` rejected an eight-parameter `fromRaw` constructor. Replacing it
  with a one-parameter `operationFromName` plus sequential field reads in the
  caller is clearer about stream ordering anyway.
- `try-in-return` flagged `return try std.json.Stringify...`; binding the JSON
  string first made the allocation path explicit.
- `repeated-string-literal` forced the shared `dictionary_length` and
  `index_failure` constants in `qbe_managed.zig`.
- `spec` rejected both invented tags (`QBE-RUNTIME-TRAP-DETAIL-*`) as unlinked
  and a reused `// spec: QBE-2` as a duplicate. The tests now use
  `// spec-case: QBE-2`; a new D1 requirement tag belongs in `SPEC.md`, which is
  integrator-owned, so the package reports that registration patch instead of
  editing the spec.

## Friction

- The `spec` check cannot see a new requirement until `SPEC.md` changes. A
  package that owns only the runtime path must either invent a tag, which fails
  as unlinked, or attach its regression to an existing requirement. That made
  the package's true guarantee less visible than it should be; an
  integrator-owned `QBE-TRAP-DETAIL-1` tag is the right home.
- The native test-runner response is a hand-written length-prefixed wire format
  with no version byte, so adding fields is a breaking consumer/producer change.
  The package bumps `MYLANG_NATIVE_EMBED_ABI` and adds a compile-time layout
  assertion between `MylQbeTrapDetail` and `MylangTrapDetail`, but a versioned
  header would make future additions cheaper.
- `line-length` and `function-length` remain report-only on the package's C
  helpers; the longest added line is the bounded JSON append and the existing
  runtime already exceeds the advisory limits.
