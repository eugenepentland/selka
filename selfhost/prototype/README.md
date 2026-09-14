# Lexer/parser prototype

Run these commands from the repository root after `zig build`:

```sh
zig-out/bin/mylang run selfhost/prototype/lexer.my --print-result
zig-out/bin/mylang run selfhost/prototype/parser.my --print-result
zig-out/bin/mylang run selfhost/prototype/bench.my --print-result
```

The lexer prints:

```text
lexer: tokens=21 checksum=1752
lexer error at 2:1: unterminated string
lexer error at 1:4: unknown character @
0
```

The parser prints:

```text
parser: tokens=24 nodes=17 checksum=1242
parser error at 1:17: expected an integer, string, name, or '('
0
```

The benchmark's clock value varies.  Its stable fields are:

```text
bench: chars=229780 pieces=4000 joins=1 tokens=36001 lex_ms=<milliseconds>
0
```

The benchmark constructs its 229,780-character input as 4,000 independent
pieces and joins exactly once. See [api_report.md](api_report.md) for the API
inventory, complexity argument, and limitations.
