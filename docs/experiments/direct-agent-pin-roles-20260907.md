# Pin-role shared-contract calibration — 2026-09-07

All three fresh participants implemented optional pin roles and passed the common
private suite: seven groups containing 142 EDA cases and four malformed requests.
This third exploratory block tests a shared input/report contract change after the
planner priority feature and EDA clearance repair. It starts from original EDA v1
baselines, not previous participants' edits, so it is not a longitudinal study.

| Participant | Preparation | Task including checks | Public submissions | Failed public submissions | Private result |
|---|---:|---:|---:|---:|---|
| Python | 26.7 s | 122.9 s | 1 | 0 | 7/7 passed |
| `.selka` | 26.9 s | 198.7 s | 2 | 0 | 7/7 passed |
| Zig + Guardian | 60.1 s | 254.5 s | 2 | 1 | 7/7 passed |

Preparation and task clocks had common 20/30-minute maxima. All participants
passed the 21-case practice suite on their first check. Task time includes tool
and public-check waits, but excludes private grading after sealing. `.selka`'s two
public checks both passed; they are not two failed repair attempts.

## Changes and quality evidence

The feature adds strict optional `pin_roles` assignment arrays, with passive
defaults and schema rejection for invalid/repeated/unknown assignments. After
existing reference checks, nets gain `multiple-drivers` and `undriven-input-net`
findings. Original inputs, geometry, net/span reports and SVG must retain their
original behavior. Application dependencies stayed stdlib-only. No compiler, VM,
Zig host or harness implementation changes were needed for this block.

Python added role validation, component/pin role lookup and finding emission,
with 27 local tests passing. `.selka` added the same behavior and expanded its existing
packed parser key radix from 16 to 32 to represent the additional fields. It passed
compiler checking, original CLI tests and new schema/role/escape tests. Zig added
three Debug tests and integration coverage; all 12 Debug tests passed.

Guardian stopped Zig's first public submission because `pin_roles` appeared three
times as a string literal. Extracting `pinRolesKey` allowed its next submission to
pass all 88 checks; 25 line-length findings remained advisory. The failed check
latency was 2.412 s; agent repair time was not separately measured. Independent
review judged the constant a modest maintainability improvement, not a correctness
bug fix. No policy changes or frozen debt were introduced.

An independent reviewer inspected each sealed implementation against public
requirements without hidden cases or execution. It found no new application
correctness defects. In particular, `.selka`'s radix change was consistent across
construction, parent extraction and lookup; role defaults, component-local pin
identity, validation precedence and finding ordering were preserved in all three.

Optional test improvements include cross-component nets with shared pin names,
independently specified role-bearing reports with nonzero spans, and a stronger
`.selka` 32-assignment assertion that checks the expected finding count. Zig's own
tests could additionally cover escaped role keys and role-bearing reference
failures. These are coverage suggestions, not demonstrated application defects.
The `.selka` CLI test path remains coupled to the trial sandbox. Sealed sources were
not edited in response to review or private feedback.

## Verification and measurement limits

The corrected `suite-build-reuse-v1` policy remained frozen. Zig practice built
once for 21 inputs. The final public suite ran Guardian/Debug/build once before its
two inputs, and private grading once before seven inputs. Failed prerequisites
were not cached. The earlier rejected public submission ran Guardian against both
public groups but never reached build/run. Source and tool/environment receipts
verified; coordinator source inventory matched before and after grading.

No API key was used. Participants had fresh contexts and instructions to use only
their own namespace-isolated gateway. Whole-agent host-tool access was restricted
by instruction rather than enforced confinement; exact model ID, token/cost data
and host-contention attribution are unavailable. No repeated trials or randomized
large-codebase blocks have established uncertainty bounds.

Python was fastest in this block, followed by `.selka` and Zig with Guardian. The
result demonstrates feasibility, not a `.selka` productivity or defect-reduction
advantage. Parser encoding changes and test-path adaptation exposed practical
`.selka` application/tooling work, even though no language change was necessary.
Guardian exposed maintainability duplication, not a missed application behavior.

Three exploratory blocks/nine participant sessions are now complete. Remaining
catalog tasks are planner input-boundary repair, planner cycle groups and EDA
rotation, followed by fresh repetitions under the fixed build policy. Broader
medium/large maintenance remains necessary to assess navigation and change impact;
these small blocks cannot answer that question. Scored pilot count stays zero.

[Machine-readable results](../../experiments/application_comparison/evidence/direct-agent-pin-roles-20260907.json)
retain clocks, source hashes, public outcomes, metrics, reuse counts and deviations.
Full baseline/final sources, patches, private results, public command logs,
configuration receipts and independent review notes are under
`/home/epentland/ai/canopy/application-trials/direct-20260907-pin-roles`.
Guardian feedback was committed as `44548d3`; its commit hook passed with zero
blocking findings. No retained current ROI subjects were available for labeling.
