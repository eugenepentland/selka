# Zero-copy by default, without lifetimes (plan, 7 November 2026)

**Status:** the direction was approved by the user on 7 November. Part 0, the census, ran first
(`experiments/copy-census-redo-20261107/`). It found 1,513 sites: 34% temporary collections (part 2), 25% long-lived (part 3),
26% real transfers, 14% plain locals and arguments (part 1). Part 2's realistic reach is about 22% of the sites, and at most about
4% of `build` wall time, though about half the class's agent time. **The user chose to wait on part 2:** parts 1, 3 and 4 go
first, and a narrowed part "2a" (collections of borrows that stay local or are returned under `from`) is reconsidered after
parts 1 and 3 land, by counting what remains.

## The problem

The G3 redo (`~/ai/canopy/netlisp-selka-redo`, `REPORT.md` and `docs/FRICTION-COMPARISON.md`) ported netlisp from Zig in one
night and met every exit. Its agents' largest cost was ownership:

| Cause | Agent time | Sites |
| --- | ---: | ---: |
| A record, list or dictionary cannot hold a borrow, so a store copies | 8.2 h | 1,508 |
| The checker refuses correct read-only or disjoint code | 8.2 h | 84 |
| Shared mutable places: a cache lent while `mut` calls follow | 3.5 h | 33 |

The cause is a mismatch of models:
- **Zig:** a struct may hold a slice or pointer into memory that lives elsewhere, and nothing checks for how long.
- **Selka:** every value has one owner, borrows are checked, and a borrow cannot be stored.

Every stored pointer in the Zig became a copy, a handle or a restructure.

## The goal

The default path must be the fast one. An agent writing the natural code should get no copy where Zig has none. The model stays
the one the user chose:
- **No lifetimes in types.** The user turned down "views with lifetime ties" in October as too complicated.
- **No second memory model** such as regions or arenas.
- **Copies are flagged, not inserted.** An earlier recommendation, that `mylang fix` write every store's `copy(...)`, is dropped,
  because it would make the slow path the default.

## The parts

### Part 0. The census (3-5 h, first)

Strip each of the redo's `copy(...)` sites that carry a friction marker for this class, and sort each into one of:
- **(T)** a temporary collection of borrows that dies before its sources, or is returned `from` them. Part 2 removes these.
- **(L)** a long-lived structure that points into a long-lived owner: tokens and parse-tree text into the source, names into the
  design, cache entries. Part 3 removes these.
- **(X)** a real transfer that must copy or move.

Report counts and the main sites per class, and estimate what part 2 would cost against the sites it removes. This is the same
method lane O2 used for 1A: it found 32 of 828 constructors, which kept 1A small.

### Part 1. Checker precision (15-26 h)

This accepts code that is already correct, so it costs nothing at run time.
- **Option narrowing.** After `if x is None: return` (or `fail`, `break`, `continue`), read `x` as a known `Some`.
  `x.unwrap_or(b"")` is then a borrow of the payload. Redo ids F-RA-204, -206, -214, -308, -400, -402, F-RC-4, -7.
- **Field-precise loans inside loops and on element fields.** Writing `self.adjacency` while iterating `self.nets` is accepted.
  Today the workaround is to take the field out and put it back (F-RC-204, F-RA-610, -501, -505, F-RC-211, -212, F-RB-16).
- **A slice of a view is a view** (F-RA-300, F-RC-103, -203, F-RA-403).
- **Rule 4f accepts a literal or a `from` call beside places** in a `mut` local (F-RA-303, -311, F-RC-118, -119, -120).

Each needs certificate-validator fixtures. Changing the validator or the Lean proof is a review stop.

### Part 2. Inferred borrowed collections (30-45 h, if the census supports it)

This extends 1A: a record built only from borrows is already a borrowed value. With part 2, a list or dictionary of such records,
or of borrowed text, is also a borrowed value:
- **How long it lives:** until the last owner it borrows from is written or dies.
- **Where it can go:** it may be returned under `from source`.
- **Layout:** its buffer is owned and freed; its elements are views and are never dropped.
- **No syntax:** nothing to declare.

When such a collection would outlive its sources, the error names the source and the line. Its certain repair is `copy(...)` at
the store.

The target shape is the Zig habit of building report rows, findings or BOM entries that point into the design block and then
using or returning them: F-RB-21, 449 sites, and much of F-RC-3 and F-RC-209.

### Part 3. Spans and keys for long-lived data (6-10 h of library work, plus the guide)

This is the values-and-keys model applied to text, for data that lives beside the buffer it points into, which no inference
covers.
- **A `spans` module.** A `Span` is a start and a length into an owner, read through it: `text(source, span) -> bytes from
  source`. It compares and hashes against `bytes`. Parse trees store spans, not copies (F-RA-1, -205, -404: about 750 sites).
- **A `symbols` module.** It interns a name once and returns a key; the text is read through the table. Repeated net names and
  reference designators become keys.
- **A cache idiom.** A cache is a table: hold the key, and re-read after a `mut` call, instead of holding a borrow across it
  (F-RA-502, F-RC-208, F-RA-12).
- **`docs/` and the port's guide** teach these as the default for long-lived data.

### Part 4. Copies flagged where they cost

Keep the copy-in-loop lint, and point its message at the zero-copy form that fits: a borrow, a span, a key, or `own` at a last
use. Then the cheap way to silence the warning is also the fast way.

## Order and measures

1. Part 0, then part 1, which needs no decision.
2. Part 3 beside part 1: library and guide work, disjoint files.
3. Part 2 only if the census's T class is large enough to pay for it. The coordinator reports the census and asks.
4. Part 4 last, so the lint can name parts 2 and 3.

Measure on the redo port after each part:
- copy sites in the friction class, before and after;
- `copy(` lines;
- release-build instructions and wall time against netlisp, with `tools/compare_zig.py` inside a timing window;
- `equiv s1a`, which must stay 217/217.

Any claim of a speed-up needs that measurement.

## Not in this plan

These are the redo's other recommendations, still for the user to choose:
- the cheap fix batch (the `listdir` cap and a listing with kinds, a non-durable atomic write, defaults, release with unreachable
  holes, `Unit`, Z3 naming the statement, the hole summary line);
- reporting every error of a file;
- the check-versus-build shapes;
- `byte_builder.append_format`;
- the guide fixes;
- adopting the redo as the port;
- S1b.
