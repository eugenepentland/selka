# Module graph boundary and tooling acceptance

`zig build test` now runs `tests/module_scaling.py` against the built compiler.
The driver creates real temporary source files, runs CLI commands with explicit
expected outcomes, and deletes its fixtures afterward. It covers the default module
and import-edge boundaries through the integrated frontend and VM, beyond the
loader's existing configurable-limit and allocation-failure unit tests.

## Deep graph

A 256-module chain exports and calls one function per dependency. The entry returns
256 with an explicit 256-frame budget. A 255-frame budget traps at m254.my:5, retaining
the original source location. Header reports list each module exactly once in
leaf-to-entry order and repeat byte for byte. Project checking and canonical
formatting checks pass.

Quality reporting identifies all 256 functions as reachable from main, all 255
exported dependency functions as interface roots, and the 255 resolved call sites.
Duplicate discovery indexes all 256 functions, reports no exact groups (each caller
resolves to a different next function), and explicitly reports approximate
truncation under a one-unit budget.

Changing the deepest leaf's return value changes only that file's content digest
and changes execution from 256 to 257. This verifies fresh loading, not incremental
cache invalidation. Changing that return to an invalid boolean rejects checking,
quality reporting, and duplicate discovery without partial stdout, at m255.my:4.
Adding a leaf-to-entry import reports a cycle with both leaf and entry locations.
Extending the valid chain to 257 modules rejects with E_MODULE_LIMIT.

## Shared dense graph

A 92-module directed acyclic graph has exactly 4,096 import edges, with every module
reachable directly from the entry and additional shared dependency edges. Header
reports contain exactly 92 modules and 4,096 imports, repeat deterministically, and
the checked project executes successfully. Adding one more edge rejects with
E_IMPORT_LIMIT. This tests shared graph accounting at the configured CLI boundary;
it does not claim that importing a module executes its functions or that uncalled
functions have runtime coverage.

## Scope

Both Debug and ReleaseFast host builds run these checks. The cases establish
behavior at the default limits, not a timing threshold, unbounded scalability,
production usefulness, or new native support. Configurable embedding limits, source
byte limits, provider read-once behavior, and partial-allocation cleanup retain their
existing loader tests. Ordinary-program corpus review remains pending, alongside
generics, compile-time/schema/incremental work, wider native operations, and other
unfinished roadmap requirements.
