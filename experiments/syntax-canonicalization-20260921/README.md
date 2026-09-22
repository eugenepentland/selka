# Canonical syntax and performance probes

Evidence for [the audit](../../docs/audits/canonical-syntax-performance-2026-09-21.md).

Run from the repository root:

```sh
python3 experiments/syntax-canonicalization-20260921/probe.py
```

The script uses the installed `zig-out/bin/mylang`; it does not rebuild the
compiler or invoke Guardian. It overwrites only its generated `sources/`,
`ir/`, and `evidence.json` artifacts in this directory. It checks 22 small
programs, emits QBE for the 17 accepted programs, and runs one behavioral
program through the native guest build route. Five check rejections are
intentional probes. No timing benchmark is performed.

`evidence.json` records compiler hashes before/after, implementation source
hashes after capture, commands, exits, diagnostic text and native output.
`ir/*.ssa` contains source-function IL extracted from the emitted JSON units,
with a comment naming each function. Imported library function bodies and the
JSON bundle's runtime metadata are omitted. These files are for inspection,
not standalone linkable programs; counts describe emitted IR, not optimized
machine code or dynamic allocation counts.

Native behavior output contrasts the prelude and library floating parsers,
then shows `d.items()` as an expression and as a two-binding loop. The retained
compiler identity is stable across the capture, but no claim is made that it
contains every concurrent working-tree edit. See the report for conclusions
and migration constraints.
