# Read-only loaded-code identity diagnosis

The coordinator requested this follow-up after freezing integration candidate
`a9a3208a4`. No production file, frozen candidate, S10 source or live cache was
changed. No build or verification gate was launched. This archive is a follow-up
requirement rather than a qualification fix.

## What is proven

`code-digest-drift.py` runs two bounded subprocesses (hash seeds 0 and 1). Each
compiles identical source twice using the identical filename `same.py`. The code
objects compare equal. Holding additional references to one string constant
changes only one object's marshal serialization and SHA-256; releasing those
references restores the original serialization. The equal peer stays unchanged.
On Python 3.14.4 / marshal version 5, the hashes are:

- Initial and equal peer: `7ab7d0f16a57440f66f9590247aac04f303b3364eff1cfe1055a0961daa399c9`.
- After constant alias references: `a820af4eb6140b74616728db5837464e487fd1d952360255b4cb68fbea28c200`.

The first changed tag byte is `0x7a` to `0xfa` (bit `0x80`), with later reference
indices shifted. This proves that these marshal bytes encode object-reference
sharing details which are not captured by code-object semantic equality. Raw
`marshal.dumps(code)` is therefore unsuitable as a canonical semantic identity.
The evidence does not require assuming source edits, different filenames or a
corrupt loader.

`code-equality-probe.py` reads the unchanged S10 C0 source through either the
ordinary source loader or the retained source-only loader policy. For all four
identity-bearing modules, the loaded root code equals freshly compiled source
using the same `co_filename`. Their marshal digests can differ. This probe retains
extra root-code references for inspection, which can itself affect raw digests;
its hashes are diagnostic evidence of noncanonical serialization, not a
replacement for the original command's identity.

`code-loader-route-probe.py` separately avoids retaining root code. It imports C0
through direct import and cache-session bootstrap plus `_GuardedFinder` and then
performs a repeated import and a pure options parse. Each route keeps the same
module object and the same stored four `LOADED_CODE_SHA256` values within the
process. The direct and bootstrap routes in this particular lightweight probe
also agree. This does **not** reproduce the entire live RuntimeGuard startup or
establish every contributor to S10's actual one-shot/retained mismatch.

The actual prior one-shot `core.json` implementation hashes are recorded, with
file/source hashes, in `code-digest-context.json`. Its first digest is
`a832d0f79b9bb0bb50e7ee59f554358117fa9362c56bbf1874e526c176a76621`;
the lightweight import first digest is
`880d6633fc4dc3aaa78631fea034aad7a7f7199f964edee7f6a5828f27b58726`.
The first retained C0 gate was cancelled; this archive uses no fabricated
completed retained result. Reference/intern/constant-sharing differences are a
proven mechanism and a likely contributor to the actual mismatch. Which exact
objects differ across those two real startup paths remains unproven.

## Does a retained process keep changing its stored hashes?

No assignment in the request loop recomputes those values. C0 `load_dispatch`
imports each coordinator once and holds its `main`; `serve` calls those stored
functions sequentially. The four stored string values are assigned at module
load and have no later assignment sites. The lightweight repeated-import probe
confirms their stability. Recomputing marshal bytes later may produce another
value, but the coordinator reads the original stored strings. S10's forced then
warm requests in one frozen retained process therefore avoid this particular
cross-startup identity mismatch. Their actual success/reuse remains S10's result.

The observed mismatch conservatively schedules extra work. No stale acceptance,
incorrect verdict or cache unsoundness is inferred from this evidence.

## Safe fix proposal for a later unfrozen candidate

Introduce one versioned canonical encoder of the **actual loaded code object**.
It should recursively encode explicit type-tagged, length-framed values, without
object addresses, reference counts or shared-reference IDs. Bind all code-object
semantics: bytecode; argument/position-only/keyword-only counts; locals/stack/flags;
constants including nested code; names, variable/free/cell names; exception and
line tables; name/qualified name; first line and filename. Initially retain
filenames and locations to preserve the conservative existing contract. Dropping
paths for cross-worktree reuse needs a separate reviewed identity change.

Constants need exact encodings for `None`, `Ellipsis`, booleans, integers,
float/complex bit patterns including signed zero and NaN payloads, Unicode,
bytes, tuples, frozensets and Python 3.14 slice constants. Sort frozensets by their
canonical encoding. Reject unsupported types conservatively. Do not use `repr`,
source bytes read after load, a directory label, or JSON's lossy float formatting.
Simply switching to marshal versions 0–4 is insufficient: the current modules
contain constants those versions cannot marshal on this Python version.

Stream the encoded data into SHA-256 with explicit format/version and Python
bytecode compatibility identifiers. Bound nesting, visited nodes and encoded
bytes; exhaustion must refuse reusable evidence, never substitute a weaker hash.
Any memo must be local encoding scratch and must not affect emitted value bytes.
Define a migration version so old raw-marshal receipts cannot silently cross the
new boundary.

The exact replacement sites are the expressions
`hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()` in
`verify_cache.py`, `verification_snapshot.py`, `fuzz_campaign_store.py`,
`verification_process.py`, and the bootstrap `cache_session.py`. A new common
Python helper requires complete declared-input closure updates (including
verification/fuzz/Juice consumers) and loaded-helper authentication. If it imports
before RuntimeGuard, preserve `_LOADED_CODE_OBJECT` and check that bootstrap
helper against watched source under the guard, as for the existing snapshot
bootstrap. Bind the helper's own loaded implementation to consumer evidence;
unchanged encoder output shape must not make changed helper semantics equivalent.
Coordinator ownership applies to all shared changes.

Required focused tests before such a fix can land:

1. Equal code digests across fresh compile, pyc load, source-only import, real
   one-shot entry, and RuntimeGuard startup, at identical filename/options.
2. Stability under extra references, strings/interning, different hash seeds,
   different import order and repeated requests in one process.
3. Changed nested body/constant/default-related code, bytecode, flags, exception
   metadata, optimization/Python compatibility and encoder implementation must
   invalidate. Unknown constants and bounds must fail closed.
4. Include slices, frozensets, signed zero/NaN bit patterns and nested code.
5. Preserve existing stale-pyc, source-change-during-load, bootstrap compiled-code
   authentication, source ABA and publication safety tests.
6. Force one reference request then compare one-shot and retained coverage/results
   using a small complete fake inventory first. Real gate reuse/performance must
   then qualify the exact changed candidate; no claim from this read-only probe.

## Commands and statuses

All commands below exited 0. Python cache writes were disabled; only S08 evidence
was written. Subprocesses have a 10-second bound. No isolated latency is claimed.

```bash
TMPDIR="$PWD/.tmp/s08-tmp" PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=/dev/null python3 experiments/development-loop-closeout-20261012/S08/code-digest-drift.py
PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=/dev/null python3 experiments/development-loop-closeout-20261012/S08/code-loader-route-probe.py /home/epentland/ai/canopy/mylang-dl-closeout-20261012-S10 direct
PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=/dev/null python3 experiments/development-loop-closeout-20261012/S08/code-loader-route-probe.py /home/epentland/ai/canopy/mylang-dl-closeout-20261012-S10 retained
PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=/dev/null python3 experiments/development-loop-closeout-20261012/S08/code-equality-probe.py /home/epentland/ai/canopy/mylang-dl-closeout-20261012-S10
PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=/dev/null python3 experiments/development-loop-closeout-20261012/S08/code-equality-probe.py /home/epentland/ai/canopy/mylang-dl-closeout-20261012-S10 --guarded
```

Matching output files are `code-digest-drift.json`, `code-loader-direct.json`,
`code-loader-retained.json`, `code-equality-direct.json`, and
`code-equality-guarded.json`.
