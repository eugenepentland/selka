# Program suite — mylang against Zig and Rust (2026-09-22)

Eleven small programs of the kind people actually write, each ported to mylang,
Zig and Rust so that **all ports print byte-identical stdout**. The earlier
micro-kernel suite (`experiments/perf-parity-audit-20260921/micro`) isolates one
primitive per kernel; this suite measures whole program shapes — allocation-heavy
trees, float kernels over records, index-heavy integer code, dictionaries over
substrings, sorting, nested lists, record-returning math, and text processing.

## Rules for every port

- **Idiomatic, single-threaded, standard library only.** Write what a competent
  programmer in that language would write first: no SIMD intrinsics, no `unsafe`
  (Rust), no threads, no hand-rolled allocators beyond what is named below, no
  third-party crates or packages. Rust uses `std` only; Zig uses `std` only.
- **The algorithm and the order of every floating-point operation are fixed by
  this file.** Evaluate `a * b * c` as `(a * b) * c`, `x -= e` as `x = x - e`,
  and so on, exactly as written below, so that every port produces the same
  IEEE-754 results. No fused multiply-add, no fast-math, no reassociation.
- **Output is integers and fixed text only.** A float result is printed as
  `int(x * 1e9)` (truncation toward zero) or as named below, never with a float
  formatter.
- **One process, no input files, no arguments.** Sizes are constants. In Zig,
  pass the top-level size through `common.opaqueN` (see `common.zig`); in Rust,
  pass it through `std::hint::black_box`. mylang needs no guard.
- **Print with the language's ordinary buffered output.** mylang: `out.print`
  on a `Stream` parameter of `main`. Rust: lock `stdout` and wrap it in a
  `BufWriter` (or build one `String` and write it once). Zig: a buffered stdout
  writer or one `bufPrint`/`allocPrint` then a single write, as `common.zig`
  shows.
- **File names.** `<bench>.my`, `<bench>.zig`, `<bench>.rs` for the main port;
  a variant is `<bench>_<variant>.<ext>` and must print the same bytes.
  `_tuned.my` is reserved for the fastest formulation found *within* mylang
  (e.g. different containers, wrapping arithmetic, avoiding slices) when it
  differs materially from the idiomatic one; say what changed in a comment at
  the top.
- **Target size.** The Zig ReleaseFast port should take roughly 0.05–1.0 s.
  If a size below makes the Zig port run outside that range on this machine,
  say so in `NOTES.md` rather than changing the size; the harness owner decides.

## Shared generators

- `lcg`: `seed = (seed * 3877 + 29573) % 139968`, starting from `seed = 42`;
  each call updates `seed` and returns the new value (always `< 139968`).
- `xorshift`: a `u64` state starting at `88172645463325252`; each step does
  `x ^= x << 13; x ^= x >> 7; x ^= x << 17` (shifts discard high bits, logical
  right shift) and yields `x >> 33` as a non-negative integer (`< 2^31`).
- `mix(c, v) = (c * 31 + v) % 1000000007` — the running checksum used below;
  with `0 <= c < 1000000007` and `0 <= v < 2^31` it never overflows 64 bits.

## 1. `binary_trees` — allocation and a tracing heap

`max_depth = 16`, `min_depth = 4`. A node has two optional children.

```
make(d): if d == 0: return Node(no children) else Node(make(d-1), make(d-1))
check(n): if n has no left child: return 1 else 1 + check(left) + check(right)

stretch = max_depth + 1
print "stretch tree of depth {stretch}\t check: {check(make(stretch))}"
long_lived = make(max_depth)
d = min_depth
while d <= max_depth:
    iterations = 1 << (max_depth - d + min_depth)
    total = 0
    repeat iterations times: total += check(make(d))
    print "{iterations}\t trees of depth {d}\t check: {total}"
    d += 2
print "long lived tree of depth {max_depth}\t check: {check(long_lived)}"
```

Expected first line: `stretch tree of depth 17\t check: 262143`.
Ports: `binary_trees.my` (a `class` node on the collecting heap);
`binary_trees_recursive.my` (a recursive value union with immutable boxed
branches, producing the same output as the class port);
`binary_trees_arena.my` (the former class tree migrated to a recursive value
record, with each short-lived tree built and checked inside its own
`with arena():` block); `binary_trees.zig` (one `std.heap.ArenaAllocator` per
depth batch, `reset(.retain_capacity)` after each tree; the stretch and
long-lived trees in their own arena); `binary_trees_gpa.zig`
(`std.heap.smp_allocator` `create`/`destroy` per node, tree freed after its
check); `binary_trees.rs` (`Option<Box<Node>>`, dropped normally).

## 2. `nbody` — float arithmetic over a list of records

Five bodies, `steps = 5000000`, `dt = 0.01`.

```
PI = 3.141592653589793; SOLAR_MASS = 4.0 * PI * PI; DAYS_PER_YEAR = 365.24
bodies (x, y, z, vx, vy, vz, mass), in this order:
 sun:     0, 0, 0, 0, 0, 0, SOLAR_MASS
 jupiter: 4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
          1.66007664274403694e-03*DPY, 7.69901118419740425e-03*DPY, -6.90460016972063023e-05*DPY,
          9.54791938424326609e-04*SOLAR_MASS
 saturn:  8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
          -2.76742510726862411e-03*DPY, 4.99852801234917238e-03*DPY, 2.30417297573763929e-05*DPY,
          2.85885980666130812e-04*SOLAR_MASS
 uranus:  1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
          2.96460137564761618e-03*DPY, 2.37847173959480950e-03*DPY, -2.96589568540237556e-05*DPY,
          4.36624404335156298e-05*SOLAR_MASS
 neptune: 1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
          2.68067772490389322e-03*DPY, 1.62824170038242295e-03*DPY, -9.51592254519715870e-05*DPY,
          5.15138902046611451e-05*SOLAR_MASS
 (DPY = DAYS_PER_YEAR; each velocity is literal * DPY, each mass literal * SOLAR_MASS)

offset_momentum: px = py = pz = 0.0; for b in bodies: px = px + b.vx * b.mass; (same py, pz)
                 sun.vx = (0.0 - px) / SOLAR_MASS; sun.vy = (0.0 - py) / SOLAR_MASS; sun.vz = (0.0 - pz) / SOLAR_MASS
energy: e = 0.0
        for i in 0..5: b = bodies[i]
            e = e + 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
            for j in i+1..5: c = bodies[j]
                dx = b.x - c.x; dy = b.y - c.y; dz = b.z - c.z
                e = e - (b.mass * c.mass) / sqrt(dx * dx + dy * dy + dz * dz)
advance: for i in 0..5: for j in i+1..5:
            dx = bi.x - bj.x; dy = bi.y - bj.y; dz = bi.z - bj.z
            d2 = dx * dx + dy * dy + dz * dz
            mag = dt / (d2 * sqrt(d2))
            bi.vx = bi.vx - dx * bj.mass * mag   (then vy with dy, vz with dz)
            bj.vx = bj.vx + dx * bi.mass * mag   (then vy, vz)
         for b in bodies: b.x = b.x + dt * b.vx; b.y = b.y + dt * b.vy; b.z = b.z + dt * b.vz
main: offset_momentum; print int(energy * 1e9); repeat steps: advance; print int(energy * 1e9)
```

`0.5 * b.mass * (...)` is `(0.5 * b.mass) * (...)`; `dx * bj.mass * mag` is
`(dx * bj.mass) * mag`. First line: `-169075164`.
Ports: `nbody.my` (a `record Body` held in a `list[Body]` and updated in place
through `bodies[i].field = ...`); `nbody_class.my` (the historical class variant, now migrated to a value record and indexed store-back for D9); `nbody.zig`
(an array of structs); `nbody.rs` (an array or `Vec` of structs, index loops).

## 3. `spectral_norm` — float kernel through small function calls

`n = 2000`.

```
a(i, j) = 1.0 / float((i + j) * (i + j + 1) / 2 + i + 1)        (integer arithmetic, exact division by 2)
mul_av(v, out):  for i in 0..n: s = 0.0; for j in 0..n: s = s + a(i, j) * v[j]; out[i] = s
mul_atv(v, out): for i in 0..n: s = 0.0; for j in 0..n: s = s + a(j, i) * v[j]; out[i] = s
mul_atav(v, out, tmp): mul_av(v, tmp); mul_atv(tmp, out)
main: u = n × 1.0; v = n × 0.0; tmp = n × 0.0
      repeat 10: mul_atav(u, v, tmp); mul_atav(v, u, tmp)
      vbv = 0.0; vv = 0.0; for i: vbv = vbv + u[i] * v[i]; vv = vv + v[i] * v[i]
      print int(sqrt(vbv / vv) * 1e9)
```

`a` must stay a separate function in every port (the compiler may inline it).

## 4. `fannkuch_redux` — small integer arrays, swaps, permutation order

`n = 10`. The benchmarks-game C algorithm, verbatim:

```
perm1[i] = i; r = n; max_flips = 0; checksum = 0; perm_count = 0
loop:
    while r != 1: count[r-1] = r; r = r - 1
    perm[i] = perm1[i] for all i
    flips = 0
    while (k = perm[0]) != 0:
        k2 = (k + 1) >> 1
        for i in 0..k2: swap perm[i], perm[k-i]
        flips = flips + 1
    max_flips = max(max_flips, flips)
    checksum = checksum + (flips if perm_count % 2 == 0 else -flips)
    loop:
        if r == n: print checksum; print "Pfannkuchen({n}) = {max_flips}"; stop
        perm0 = perm1[0]
        for i in 0..r: perm1[i] = perm1[i+1]
        perm1[r] = perm0
        count[r] = count[r] - 1
        if count[r] > 0: break
        r = r + 1
    perm_count = perm_count + 1
```

Expected output: `73196` then `Pfannkuchen(10) = 38`.

## 5. `mandelbrot` — float loop, bit packing

`size = 1600` (width = height), `iterations = 50`, `limit = 4.0`.

```
checksum = 0
for y in 0..size:
    ci = 2.0 * float(y) / float(size) - 1.0              ((2.0*y)/size) - 1.0
    byte = 0; bits = 0
    for x in 0..size:
        cr = 2.0 * float(x) / float(size) - 1.5
        zr = zi = tr = ti = 0.0; i = 0
        while i < iterations and tr + ti <= limit:
            zi = 2.0 * zr * zi + ci                         ((2.0*zr)*zi)+ci
            zr = tr - ti + cr                               (tr-ti)+cr
            tr = zr * zr; ti = zi * zi; i = i + 1
        byte = byte * 2 + (1 if tr + ti <= limit else 0); bits = bits + 1
        if bits == 8: checksum = mix(checksum, byte); byte = 0; bits = 0
    if bits > 0: byte = byte << (8 - bits); checksum = mix(checksum, byte); byte = 0; bits = 0
print "P4 {size} {size}"; print checksum
```

## 6. `knucleotide` — substrings as dictionary keys

`length = 1000000`. Sequence: for each position, `s = lcg()` and the base is
`"ACGT"[s * 4 / 139968]` (integer division).

```
frequencies(k): counts = map from k-letter string to int
                for i in 0..length-k+1: key = seq[i:i+k]; counts[key] = counts[key] + 1 (0 if absent)
for k in [1, 2]: counts = frequencies(k)
                 sort entries by count descending, then key ascending
                 print "{key} {count}" per entry
for key in ["GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT"]:
    counts = frequencies(len(key)); print "{counts[key] or 0}\t{key}"
```

Every `frequencies` call builds a fresh map over the whole sequence (so the
k = 12 and k = 18 maps hold about a million distinct keys). mylang: `dict[str,
int]` keyed by slices of a `str`. Rust: `HashMap<&[u8], u32>` (or `&str`) with
the default hasher. Zig: `std.StringHashMap(u32)` over slices.
`knucleotide_arena.my` is the same program with every counting phase (the map,
its slice keys and the sorted report) inside its own `with arena():` block. Only
the generated sequence stays on the collecting heap. It checks that an
arena-wrapped phase is no slower than the collecting one.

## 7. `sort_builtin`, `sort_quick`, `sort_records` — sorting

`n = 2000000` values, `values[i] = xorshift()` in order.

- `sort_builtin`: sort ascending with the standard *stable* sort (mylang
  `values.sort()`, Rust `slice::sort`, Zig `std.mem.sort` with
  `std.sort.asc(i64)`).
- `sort_quick`: this exact recursive quicksort, same data:
  ```
  quicksort(xs, lo, hi):                 # inclusive bounds
      while lo < hi:
          pivot = xs[lo + (hi - lo) / 2]; i = lo; j = hi
          while i <= j:
              while xs[i] < pivot: i = i + 1
              while xs[j] > pivot: j = j - 1
              if i <= j: swap xs[i], xs[j]; i = i + 1; j = j - 1
          if j - lo < hi - i: quicksort(xs, lo, j); lo = i
          else: quicksort(xs, i, hi); hi = j
  quicksort(values, 0, n - 1)
  ```
- Both print `"{xs[0]} {xs[n/2]} {xs[n-1]}"` then `c = 0; for v in xs: c = mix(c, v)`; print `c`.
- `sort_records`: `n = 1000000` records `{key = xorshift() % 100000, id = i}`,
  stable-sorted by `key` through the language's key/comparator sort (mylang
  `sort.sort_by_key` or the closest standard spelling, Rust
  `sort_by_key(|r| r.key)`, Zig `std.mem.sort` with a `lessThan` on `key`).
  Print `"{first.key} {last.key}"`, then `c = mix(c, r.id)` over the sorted
  records; print `c`.

## 8. `sieve` — memory-bound indexed writes

`n = 20000000`.

```
flags = (n + 1) × true; flags[0] = flags[1] = false
i = 2
while i * i <= n:
    if flags[i]: j = i * i; while j <= n: flags[j] = false; j = j + i
    i = i + 1
print number of true flags
```

Expected: `1270607`. Ports: `sieve.my` (`list[bool]`), plus a variant on
whichever byte container mylang offers if it is materially different
(`sieve_bytes.my`); Zig `[]bool`; Rust `vec![true; n + 1]`.

## 9. `matmul` — nested lists against flat storage

`n = 500`. Fill `A` row-major with `float(lcg()) / 139968.0`, then `B` the same
way (continuing the same generator). `C = 0`.

```
for i in 0..n: for k in 0..n: aik = A[i][k]; for j in 0..n: C[i][j] = C[i][j] + aik * B[k][j]
trace = 0.0; for i: trace = trace + C[i][i]
total = 0.0; for i: for j: total = total + C[i][j]
print int(trace * 1000.0); print int(total * 1000.0)
```

Ports: `matmul.my` (`list[list[float]]`, the Python shape); `matmul_flat.my`
(one `list[float]` indexed `i * n + j`); Zig and Rust flat.

## 10. `raytrace` — small value records returned from small functions

A `Vec3 {x, y, z: float}` value type with `add`, `sub`, `scale(v, s)`, `dot`
and `normalize(v) = scale(v, 1.0 / sqrt(dot(v, v)))`, each a separate function
returning a new `Vec3`. Spheres `{center: Vec3, radius: float, color: Vec3}`,
in this order:

```
((0, -1000, 0), 999, (0.5, 0.5, 0.5))
((0, 0, -3), 1, (1.0, 0.2, 0.2))
((-2, 0, -4), 1, (0.2, 1.0, 0.2))
((2, 0, -4), 1, (0.2, 0.2, 1.0))
((0, 2, -6), 1.5, (1.0, 1.0, 0.2))
((-1.5, -0.5, -2), 0.5, (0.2, 1.0, 1.0))
light = normalize((1, 1, 1))
intersect(origin, dir, s) -> float:
    oc = sub(origin, s.center); b = dot(oc, dir); c = dot(oc, oc) - s.radius * s.radius
    disc = b * b - c
    if disc < 0.0: return -1.0
    root = sqrt(disc)
    t = (0.0 - b) - root; if t > 0.001: return t
    t = (0.0 - b) + root; if t > 0.001: return t
    return -1.0
shade(origin, dir) -> Vec3:
    best = -1.0; hit_index = -1
    for each sphere s at index k: t = intersect(origin, dir, s)
        if t > 0.0 and (hit_index < 0 or t < best): best = t; hit_index = k
    if hit_index < 0: return (0.6, 0.7, 0.9)
    s = spheres[hit_index]
    point = add(origin, scale(dir, best)); normal = normalize(sub(point, s.center))
    diffuse = dot(normal, light); if diffuse < 0.0: diffuse = 0.0
    if diffuse > 0.0: for each sphere q: if intersect(point, light, q) > 0.0: diffuse = 0.0; stop
    return scale(s.color, 0.1 + 0.9 * diffuse)
width = 1920, height = 1080, aspect = float(width) / float(height), origin = (0, 0, 0)
checksum = 0
for y in 0..height: for x in 0..width:
    u = (2.0 * (float(x) + 0.5) / float(width) - 1.0) * aspect      (((2.0*(x+0.5))/width)-1.0)*aspect
    v = 1.0 - 2.0 * (float(y) + 0.5) / float(height)                 1.0-((2.0*(y+0.5))/height)
    c = shade(origin, normalize((u, v, -1.5)))
    r = int(min(c.x, 1.0) * 255.0), same g from c.y, b from c.z      (min: a if a < b else b)
    checksum = mix(checksum, r * 65536 + g * 256 + b)
print checksum
```

Ports: `raytrace.my` (`record Vec3`, `record Sphere`, spheres in a
`list[Sphere]`); Zig and Rust with plain structs passed and returned by value.

## 11. `text_ops` — building, splitting, parsing and rewriting text

`lines = 200000`.

```
line(i) = "item{i},{(i * 7919) % 100003},{'x' repeated (i % 7) times}"
text = the lines joined with "\n" (no trailing newline)
total = 0; widths = 0; sevens = 0
for each line in text split on "\n":
    fields = line split on ","
    total = total + int(fields[1]); widths = widths + len(fields[2])
    if fields[0] ends with "7": sevens = sevens + 1
rewritten = text with every "item" replaced by "it"
print "{total} {widths} {sevens}"
print "{len(text)} {len(rewritten)} {number of non-overlapping occurrences of ',1' in text}"
```

mylang: `str` methods (`split`, `join`, `replace`, `endswith`, `count`, `int()`),
f-strings. Rust: `String`, `format!`/`write!`, `split`, `parse`, `replace`,
`matches(...).count()`. Zig: `std.ArrayList(u8)`, `std.fmt`, `std.mem.splitScalar`,
`std.fmt.parseInt`, `std.mem.replaceOwned`, `std.mem.count`.
