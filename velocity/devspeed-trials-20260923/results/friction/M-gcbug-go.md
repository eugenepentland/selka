# FRICTION.md — M-gcbug-go

## The bug

`lox/ports/go/internal/heap/gc.go`, function `blacken`, case `*object.Closure`:

```go
case *object.Closure:
    rt.markObject(o.Function)
```

SPEC.md §7.4 step 2 says the trace order is "Closure: function, then upvalues." The
Go port's `blacken` only marked `o.Function` and never walked `o.Upvalues`
(`[]value.ObjRef`). Once an upvalue is *closed* (the enclosing call returns and
`closeUpvalues` unlinks it from `Runtime.OpenUpvalues`), the only remaining path to
that `Upvalue` object is through the closure that owns it. With that path unmarked,
the next collection sweeps the upvalue as garbage even though the closure — and
whatever called it — is still very much alive. `--gc-stress` collects on *every*
allocation, so any garbage allocated between "capture the closure" and "call the
closure" (the `"x" + "y"` loop in the report) is enough to trigger it; without
`--gc-stress` you need to get unlucky with the threshold, and the tree engine has no
`Closure`/`Upvalue` objects at all (it closes over an `Env` chain, whose `blacken`
case does trace `Slots`), which is exactly the "only vm, only with --gc-stress"
shape in the report.

Fix: trace the upvalues too.

```go
case *object.Closure:
    rt.markObject(o.Function)
    for _, u := range o.Upvalues {
        rt.markObject(u)
    }
```

`markObject` already treats `value.NoObj` as a no-op, so this is safe for the
upvalue slots a `CLOSURE` instruction hasn't filled in yet.

## How I found it — and what actually cost time

1. **Reading `gc.go` cold against SPEC.md §7.4 found the root cause before I ran
   anything.** The spec's trace-order sentence ("Closure: function, then upvalues.")
   sits right next to the code that implements it; the `Closure` case visibly
   handles only one of the two fields. This was the fastest part of the whole task —
   maybe 10 minutes of reading `gc.go`, `vm.go`, and the relevant SPEC.md section
   side by side. **Nothing in the toolchain flagged this**: it's a plain Go
   `switch` over an interface type, and neither `go build` nor `go vet` has any
   notion that every case *should* mirror every field of the struct it matches. The
   omission is invisible to the compiler by construction — it type-checks perfectly
   whether or not a field is traced.

2. **Confirming it needed exactly one test run**, but the fix was easy to
   second-guess without a repro. Before touching anything I ran `go test ./...`
   (after setting `GOTOOLCHAIN=local`, `GOCACHE`, `GOMODCACHE` per `NOTES.md` —
   documented up front, so no friction there) and got an existing test to fail on
   its own:
   ```
   --- FAIL: TestRunGcStressSameOutput (0.00s)
   panic: interface conversion: object.Obj is *object.String, not *object.Upvalue [recovered, repanicked]
   lox/internal/heap.(*Runtime).AsUpvalue(...)
       .../internal/heap/heap.go:151
   lox/internal/vm.(*vm).run(...)
       .../internal/vm/vm.go:287
   ```
   That message is a *symptom* several allocations downstream of the actual defect:
   it tells you a stale `ObjRef` now points at a live object of the wrong kind, not
   that the collector forgot to root something two calls earlier. If I hadn't
   already read `blacken` and formed a hypothesis, this panic alone would have sent
   me hunting through `vm.go`'s upvalue bookkeeping (`captureUpvalue`,
   `closeUpvalues`, the `OpenUpvalues` list) before landing back on `gc.go`. I did
   spend a few minutes independently re-checking two other spots that looked
   suspicious on first read and turned out fine: the `OpClosure` case allocates the
   closure *before* pushing it (is the not-yet-rooted closure itself in danger
   during that allocation? No — it doesn't exist yet, so there's nothing to root),
   and the `for u := rt.OpenUpvalues; ...; u = rt.AsUpvalue(u).NextOpen` root-walk in
   `markRoots` (calling `AsUpvalue` on a root mid-walk looked like it could race
   with a collection, but root-marking never triggers a nested collection, so it's
   fine). Call it one false start, resolved by reading rather than experiment, so it
   cost minutes not attempts.
3. **Verifying the fix was cheap and unambiguous**: same `go test ./...` went green
   immediately, and running the built binary directly against the exact program
   from the report (`./prog --engine=vm --gc-stress counter.lox`) printed `1` then
   `2` as specified. One attempt, no iteration needed once the field was added.
4. **`gofmt` reformatted my new test's trailing `// function` / `// upvalue`
   comments** (column-aligned them) — cosmetic, `go fmt ./...` handled it, not
   worth calling friction beyond noting that `gofmt -l` should be run as part of
   verification, since it silently *fixes* rather than *reports* by default.

## Tools used

`grep`/reading source directly (`gc.go`, `vm.go`, `heap.go`, `object.go`) cross-
referenced against `SPEC.md` §7.4 was the whole diagnosis. `go test ./...`,
`go vet ./...`, `go build ./...`, and `gofmt -l` for verification. The Python
harness (`lox_bench.py conformance --binary ./prog --engine both --stress`) for the
corpus check. No debugger, no profiler — none would have helped here; the defect is
a missing line in a hand-written trace function, not a logic error a debugger would
have surfaced faster than reading the two adjacent lines that *do* work (`Function`,
`Instance`, `Env` all trace their reference-typed fields correctly; `Closure` is the
one outlier).

## Three tooling/language changes that would have saved the most time, ranked

1. **Give `ObjRef` a generation tag.** Right now a freed slot is just `obj = nil`
   until reused; once reused, a stale `ObjRef` aliases silently onto whatever now
   lives there. The only reason this bug surfaced as a clean panic
   (`interface conversion: ... is *object.String, not *object.Upvalue`) is that the
   slot happened to be reused by a *different* kind. If it had been reused by
   another `Upvalue`, the program would have silently printed the wrong number
   instead of crashing — a far worse outcome, and the one the bug report's "or print
   wrong values" clause is presumably describing. A generation counter per slot,
   checked in `Get`/`AsUpvalue`/etc. and folded into `ObjRef`'s comparison, turns
   every instance of this bug class (not just this one) into an immediate, specific
   panic ("stale ObjRef: generation 3 vs 4") the moment the reference is used,
   independent of what got reused. This is a bigger lever than fixing today's one
   missing case, because the same class of mistake (add a new reference-typed field
   to an object kind, forget to add it to `blacken`) is trivially easy to reintroduce
   and today's structure gives zero defense against it.
2. **Make the mark-phase trace exhaustive by construction instead of by hand-written
   `switch`.** The bug is exactly "a `switch` case that should mirror a struct's
   fields drifted out of sync with it," and Go's type system has no way to require
   that. Something as simple as a table — `map[reflect.Type][]fieldOffsetOrAccessor`
   built once per kind, checked at init time against every exported `value.ObjRef`
   and `value.Value` field via reflection — or, more in the spirit of this
   hand-written interpreter, a unit test that reflects over each `object.*` struct
   and asserts every `value.ObjRef`/`value.Value`-typed field is mentioned in
   `blacken`'s source for that case, would have caught this at `go test` time with
   no reliance on a program happening to allocate garbage between capturing a
   closure and calling it. `TestRunGcStressSameOutput` almost caught this by luck
   (it happens to allocate a string between creating and using a closure); a
   structural check wouldn't need luck.
3. **A `--gc-debug` mode that logs each freed slot's prior kind/allocation site and
   asserts on reuse-of-the-wrong-kind, rather than only guarding the nil case.**
   `heap.Get` already has a nice, deliberate message for the "read a free slot"
   case (`"heap: dereferenced a free slot"`); there's no equivalent for "read a
   slot that's been freed *and reused* as a different kind since this reference was
   taken," which is the actually-dangerous case and the one this bug hit. Even a
   debug-only ring buffer of "slot N: freed at allocation count K, was kind X"
   would have turned the type-assertion panic into a direct answer instead of a
   five-minute trace back through three files.
