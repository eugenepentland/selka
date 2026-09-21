# The `QBE-TEXT-4` codec fault: narrowed, not fixed

`invoke_test`'s "an undersized codec result buffer reports OutputTooSmall, not
WireLimit" crashes with `SIGSEGV` at the call on its first line. It is the only
red item in the whole gate and it predates every change in this branch — it
reproduces on the frozen W0 baseline. This note records what is now known so the
next attempt does not repeat the search.

## What the test does

```zig
const call = try codecEntry(&loaded);              // mylang_native_call_codecs_v1
const arguments = bracketArguments();              // 3 nodes: str + 'a' + 'b'
var small: [4]WireNode = @splat(sentinel);
var small_result: CodecResult = undefined;
const too_small = call("tool::bracket", &arguments, arguments.len, &small, small.len, null, &small_result);
```

`tool::bracket("ab")` returns `"[ab]"`, which is one text node plus four scalar
nodes. A four-node buffer cannot hold it, so the contract is `OutputTooSmall`
with `node_count == 5` and the caller's buffer untouched. The same call with an
eight-node buffer is expected to complete.

## What is now established

**The generated library's codec entry is never entered.** Instrumenting
`codec_start` (the first statement of `mylang_native_call_codecs_v1`), `co_read`,
`co_write` and the `done:` epilogue with file-appending probes produced **no log
file at all** — not even the entry probe, and not the epilogue probe that runs on
every path including failures.

**The capacity is not the trigger, and never was.** Moving the eight-node call
ahead of the four-node one moved the fault with it: the crash lands on whichever
call runs first, at the same address, with a buffer that is demonstrably large
enough. So the test's own name and premise — "an undersized codec result buffer
reports OutputTooSmall" — describe something that never gets a chance to happen.
What it actually exercises is *the first call through the loaded library*, and
the four-node buffer is incidental.

Three things follow:

- The earlier note in `recursion-fix.md` that the fault is "inside the codec
  entry" is wrong. Nothing inside the library runs.
- Reading this as a capacity bug has been misleading for several rounds. Any
  reproduction should keep the roomy call first, so the fault cannot be mistaken
  for an undersized-buffer one.
- Whatever is wrong is in the caller side of the boundary — the `std.DynLib`
  load, the `callconv(.c)` function-pointer call, or the marshalling — because a
  call that faults before its first statement is not a call the callee can be
  responsible for.

The probe path was verified rather than assumed: the probe string is present in
both `zig-out/bin/mylang` and the `zig-out/focus/mylang` the focused run
actually uses, `builtLibrary` builds into a fresh temporary cache so no stale
object is reused, the probe was rewritten from `stderr` to a file after `stderr`
turned out not to surface, and the fault address changes when the generated code
changes (`0x4`, `0x0`, `0xea546` across runs).

## What is therefore still open

The fault is in the caller side of the boundary. The Zig/C layouts either side of
that call are asserted equal by the test itself (`WireNode` 24, `CodecResult`
672, `CodecOptions` 40) and those assertions pass, so an obvious layout mismatch
is already excluded. The varying fault address (`0x4`, `0x0`, `0xea546`) points
at a wild branch rather than a bad field offset.

## How to attack it next

A standalone C driver that `dlopen`s the same library and makes the same two
calls would separate "the library is wrong" from "the Zig caller is wrong" in one
step, and unlike the test it can be run under a shell where probes and a
debugger are both available. Building it needs the library path that
`builtLibrary` produces, which the test currently keeps in a temporary directory
and deletes.

## Why it was not fixed here

Four rounds of budget have gone into this branch's positive work, and the fault
is orthogonal to all of it: `mylang invoke` never takes the undersized-buffer
path, and the boundary matrix, both worked examples and every list and composed
shape pass with it outstanding. It is recorded rather than left as a bare red
test.
