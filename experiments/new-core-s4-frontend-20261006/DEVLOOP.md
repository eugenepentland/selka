# Reusable S4-X dev-loop measurement

`measure_devloop.py` prepares synthetic projects with the existing generator and
changes one function to a previously unseen source version for every measured
edit. Each role/mode has its own fresh semantic/object/link cache. It retains
the compiler hashes, source commit, exact commands, per-command logs, edit hashes,
machine reports, process traces and gate decisions in `summary.json`.

Cold, unchanged and every edited output executable also runs on CPU 10, with
its own command log and output hashes. Old/new exit status, stdout and stderr
must match in each mode. These execution durations are separate from build
timings. The traced fresh edit receives its own old-core build/run oracle, and
the parallel cold output is checked against the old cold output at the same
size. A run selecting only one compiler role is an unqualified tool smoke.

Build both compiler hosts in the same explicitly recorded mode, normally
ReleaseFast. Debug/release below select the guest's optimization mode. The old
Wave-0 ReleaseFast pin is
`/home/epentland/.cache/mylang/s4-wave0-20261006/mylang-s4-pin/bin/mylang`.

Run from a qualified S4-C integration worktree with a new evidence/work directory:

```bash
scripts/build-slot.sh build -- python3 \
  experiments/new-core-s4-frontend-20261006/measure_devloop.py \
  --core .mylang-cache/s4-x/rf/bin/mylang-core \
  --old /home/epentland/.cache/mylang/s4-wave0-20261006/mylang-s4-pin/bin/mylang \
  --host-mode ReleaseFast \
  --evidence experiments/new-core-s4-20261006/integration/devloop-01 \
  --work .mylang-cache/s4-x/devloop-01 \
  --core-extra=--stats
```

Each ordinary build acquires `/run/user/1000/mylang-slots/cpu10.lock` and runs on
CPU 10 with `MYLANG_JOBS=1`; waiting for the lock is outside its measured duration.
The 192k-line cold release build uses `MYLANG_JOBS=16` and the build wrapper's
affinity, and appears separately in `parallel`, including its CPU set and worker
count. It does not borrow CPU 10. `--parallel-size=0` disables that separate run.

For a quick instrumentation check before spending time on the large builds, use
fresh `smoke-01` paths and add `--sizes 2 --roles core --rounds 1
--parallel-size 0`. Before S4-C, it deliberately reports unqualified cache/unit
targets: the old monolithic driver starts `zig cc` on unchanged requests and
has no separate `-O3 -c` unit command. This check is tool validation, not S4-X
qualification. The script's trace parser was checked against successful/failed
execs, internal clang execs, process lifetimes, unique units and ambiguous units
in `devloop-parser-check-01.log`.

The untraced edited build duration drives the time gates. A distinct fresh
release edit gets a process trace to recover the actual LLVM compile invocation.
That invocation is replayed with a fresh `ZIG_LOCAL_CACHE_DIR` on CPU 10, giving
the edited unit's `-O3` comparator without the process-tracing overhead. The
runtime/link commands do not count as LLVM units. If multiple LLVM units compile,
the machine report must map `source_path` to `llvm_path`; absent an unambiguous
mapping, the script reports the comparator unresolved; the required 48k
measurement fails qualification.

The release time comparator gates the required 48k edit. Comparisons at other
sizes remain reported in `release_edit_comparison` without imposing additional
time targets. Qualification requires the 48k edit measurements and the separate
192k cold release build with 16 workers; smaller smoke runs stay unqualified.

The S4-C stderr report can be one JSON object with a `units` array or one JSON
object per unit. Each unit should expose `name`, `kind`, `source_path`,
`llvm_path`, `object_path`, `key`, `cache_hit`, `compile_argv` and
`compile_seconds`. Phase reports are retained as their exact JSON records. The
script sets `MYL_CORE_BUILD_REPORT=1`. C's final report schema may require a small
tool-only adaptation. Keep the unit LLVM files until the replay finishes.

The harness uses `strace -f -ttt -e trace=process` to count successful `zig cc`
execs independently of compiler reports. An unchanged request is accepted only
when this count is zero. Failed PATH lookup attempts and Zig's internal clang
execs are not counted as separate driver invocations. All trace files are kept.

The compiler hosts' optimization mode is the caller's build receipt; the tool
records the claimed mode and executable SHA-256. Retain the matching build logs
alongside this run. `--timeout` defaults to 1200 seconds so the old compiler's
known slow large cold builds are not confused with cache correctness failures.
