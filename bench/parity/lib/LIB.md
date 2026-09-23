# Runtime-library micro benchmarks (wave 0)

Programs that time one runtime-library routine family against the Zig standard
library routine an idiomatic Zig program calls for the same job. They follow
`../suite/SUITE.md`'s rules (idiomatic, single-threaded, standard library only,
integer output, sizes as constants, Zig sizes through `common.opaqueN`, one
buffered write), and `bench.py` times them the same way: pass
`--src experiments/perf-parity-plan-20260922/lib`.

## Shared text

```
line(i) = "item{i},{(i * 7919) % 100003},{'x' repeated (i % 7) times}\n"
block   = line(0) + line(1) + ... + line(1999)          (36,661 octets)
text    = block repeated 110 times                       (4,032,710 octets)
```

`text` is ASCII and is built once per program: the block with the language's
ordinary formatting, then the copies in one join (mylang
`"".join([block for _ in range(110)])`, Zig `appendSlice` into one
`std.ArrayList(u8)`), so building it is a small share of every program.

## `scan_count` — `str.count` against `std.mem.count`

```
rounds = 12
repeat rounds times:
    a = count(",1"); b = count("\n"); c = count("item1"); d = count("x\nitem")
    total = total + a + b + c + d
print "{len(text)} {a} {b} {c} {d} {total}"
```

Non-overlapping counts. The needles cover a one-octet needle (Zig's
`countScalar`), a two-octet needle whose first octet is frequent (Zig's linear
scan), and five- and six-octet needles (Zig's Boyer-Moore-Horspool), the last
one with a first octet that recurs about three times per line without matching.

## `scan_replace` — `str.replace` against `std.mem.replaceOwned`

```
rounds = 4
repeat rounds times:
    a = text.replace("item", "it")        (shrinks; 220,000 matches)
    b = text.replace(",", ";;")           (grows; one-octet needle)
    c = text.replace("x\nitem1", "|")     (rare seven-octet needle)
    total = total + len(a) + len(b) + len(c)
print "{len(a)} {len(b)} {len(c)} {total}"
```

Zig frees each result with the allocator it came from
(`std.heap.smp_allocator`); mylang leaves each result to the collector.

## `scan_split` — `str.split(sep)` against `std.mem.splitSequence`

```
rounds = 3
repeat rounds times:
    for piece in text split on "\n":      lines += 1; width += len(piece)
    for piece in text split on ",":       fields += 1
    for piece in text split on "x\nitem": runs += 1; run_width += len(piece)
print "{lines} {width} {fields} {runs} {run_width}"
```

The sums run over all rounds. `splitSequence` is an iterator over slices of the
input, while mylang's `split` answers a `list[str]` of fresh strings — one
object per piece until shared string slices (plan §5.4) land — so this program
measures the scan plus that per-piece allocation and collection.

## `phases/` — `text_ops` ablation

`p1_build.my` … `p4_replace.my` are cumulative cuts of `../suite/text_ops.my`:

- `p1_build.my` builds the text only;
- `p2_lines.my` adds the line split;
- `p3_fields.my` adds the per-line field split, `int()` and `endswith`;
- `p4_replace.my` is the build plus `replace` and `count`.

Timing them one after another gives each phase's cost.
They are not timed by `bench.py`: no `.zig` port matches them.

## Expected output

`expected.py` transcribes the three programs into CPython and rewrites the
`.expected` files; every port must print them byte for byte.
