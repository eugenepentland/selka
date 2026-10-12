# A10 command and installed-package inventory

Base C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
This is a source inventory, not passed qualification.

| Path | C0 implementation | Required qualification |
| --- | --- | --- |
| build/build --run | core cli_args + pipeline; explicit ownership flags | all five build configurations, negative moves, ABI |
| developer build options | separate core main.buildCommand parser | same flags and mode |
| run/run-project | core cli_run delegates cli_args/pipeline | arguments, projects, Result entry |
| check with ownership flag | C0 core cli dispatch -> check_command; command-support uses full frontend | source ownership plus library, diagnostics and report behavior |
| developer check --typed/--stats | dedicated core profiling parser remains separate | executable entry required by its frontend; this developer path is not the library check interface |
| ordinary check | src/main.zig old front-end/navigation parser | default must validate ownership without losing diagnostic/report/library behavior |
| check-session | persistent frontend check-project loop | followup admits explicit ownership flags, validates on every cold/warm request |
| dump-ir | core main.developer | explicit source check and mode-aware lowering |
| test file | core main.testCommand -> test_runner | C0 rejects flag; mode missing in every lowering and receipt domain |
| test directory | test_runner_directory/union | in-process roots and spawned children must agree |
| cached/local/portable/indexed test | receipt settings + test keys | mode isolation and source changes must prevent stale success |
| affected tests | test_runner_affected reachable lowering | retain unsupported tests in selection |
| doctest/examples | doctest_command spawns same installed compiler run/check | C0 had no ownership opt-in forwarding; followup adds explicit zero-RC selection; ordinary defaults are inherited |
| cost/interface cost | direct lowering preceded emission options in C0 | fixed eager validation and shared lowering/emission mode; explicit cost opt-in and future inherited defaults |
| coverage | per-function developer sweep used implicit legacy Input | followup propagates explicit selected ABI and rejects invalid source ownership before the sweep |
| allocation warnings | frontend Sessions and lint lowered noalloc roots with implicit legacy Input | followup selects caller ABI, preserves historical controls until C2, classifies owned encode/reverse copies accurately |
| installed mylang | installed bin plus libexec components and tools | preserve complete layout; compiler alone is incomplete |
| installed test-index/cache-plan | selfhost/components.zig builds both with separate pinned seed | installed components are guest binaries and need separate zero-RC qualification |

## Installed components block package-wide RC retirement

`selfhost/component-seed.json` pins historical commit
`0689d3407c17df34915aeb2a92e309af3a04921c`. This predates prototype
`9225adeb0`; `selfhost/components.zig:260` invokes the seed with `build` and
no ownership selection. Its component build key and qualified installation
manifest bind that seed recipe. These actively installed artifacts therefore
remain outside a claim that all installed language components are RC-free.

The immutable seed is a historical bootstrap input and must not be rewritten.
A concrete packaging change must first qualify both present component sources
with the integrated zero-RC compiler (protocol oracles and leak/ABI audit), then
introduce a separately keyed final component build stage using that qualified
compiler, keeping seed provisioning independent to avoid a build dependency
cycle. Build/install dependencies need coordinator and self-hosting-owner review.
Do not merely add a flag the old seed cannot accept, alter its historical pin, or
reuse an RC component cache manifest under a zero-RC claim.

Command support commits are recorded in `handoff.md`. Default promotion and active
RC removal wait for coordinator qualification approval; unapplied patches are
under `rollout/`.

Support5 diagnostic distinction: `check` success is source admission. `dump-ir`
(and its `--facts` form) returns diagnostic intermediate Core, which can include a
state later refused by native lowering. A08's cache-plan
`cache-plan-support5-facts-v2.ir` exposes a retain while the matching owned build
refuses `E_ZERO_RC_LOWERING`; dump status0 is not executable or RC-free runtime
admission. The positive A10 dump row only qualifies dispatch/source checking.
