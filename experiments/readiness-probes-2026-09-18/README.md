# Readiness probes, 2026-09-18

Guest programs written for `docs/audits/real-project-readiness-2026-09-18.md`. Each
was written the way a Python programmer would write it first, then repaired until the
compiler accepted it; the audit records every repair. Run from this directory with the
compiler at `zig-out/bin/mylang`:

- `sexpr-str/main.my` — character-level S-expression parser over `str`, with tests
  (`mylang test sexpr-str/main.my`). `perf_main.my.txt` is the same parser with a
  file-reading `main` (renamed so the directory stays a single program).
- `sexpr-bytes/main.my` — the same parser over `bytes` (`mylang run sexpr-bytes/main.my -- big.kicad_pcb`).
- `expr/main.my` — token-based precedence-climbing expression parser with a recursive
  AST; needs `class` payloads (`mylang test expr/main.my`).
- `proj/` — three-module project (`sexpr.tokenizer`, `sexpr.parser`, root-level
  `parser_test.my`); `mylang test proj` and `mylang run proj/main.my -- big.kicad_pcb`.
- `micro/main.my` — string index / iterate / append / slice micro-benchmarks
  (`mylang build micro/main.my -o micro_bin && ./micro_bin big.kicad_pcb index`).
- `sexpr_char_reference.py` — the CPython reference for `sexpr-str`.
- `python3 gen_big.py` writes `big.kicad_pcb` (1,287,988 bytes, 247,008 nodes).
