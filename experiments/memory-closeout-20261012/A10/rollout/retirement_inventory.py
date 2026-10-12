#!/usr/bin/env python3
"""Pin retirement hunk anchors and test callers; this is never a pass census."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

parser = argparse.ArgumentParser()
parser.add_argument('--source-revision', required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[4]
archive = subprocess.check_output(['git', 'archive', args.source_revision, 'src', 'selfhost', 'scripts', 'build.zig', 'build_test_inputs.zig'], cwd=root)
with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
    sources = {entry.name: tree.extractfile(entry).read().decode(errors='replace') for entry in tree if entry.isfile()}

groups = []


def group(id, owner, files, pattern, action, preserve, dependency):
    members = []
    for path in files.split():
        source = sources[path]
        matches = [{'line': n, 'source': line.strip()} for n, line in enumerate(source.splitlines(), 1) if re.search(pattern, line)]
        members.append({'path': path, 'sha256': hashlib.sha256(source.encode()).hexdigest(), 'anchors': matches})
    groups.append(dict(id=id, owner=owner, status='UNAPPLIED', files=members, action=action, preserve=preserve, dependency=dependency))


group('mandatory-abi', 'A07; coordinator shared declarations',
      'src/core/ir.zig src/core/build.zig src/core/zero_rc.zig src/core/verify_ir.zig',
      r'single_owner|zero_rc|shared_lists|kindOffset|exclusiveList|\.retain|\.is_unique|enableSnapshots|myl_core_s2_sort_keyed',
      'Remove optional Module/build.Input ownership modes and shared_lists. Add core/guest_abi.zig Abi { checked_owned_v1 }. Make checking, helper contracts, owned map/sort/resource lowering and invalid retain/is_unique refusal unconditional. No implicit unchecked-source entry.',
      'Direct destruction represented by IR release; deep-copy, ownership checks, source spans and invalid-IR diagnostics.',
      'Exact agreed API: enum(u32) checked_owned_v1=0x4f574e31 (OWN1), guest_abi.current and identity="mylang-checked-owned-v1"; mandatory validate/check replace validateMode/checkMode. Every direct build/hand-IR caller in internal-api-calls.json must migrate. Negative old IR can remain only as refused input.')
group('ownership-pass', 'A07',
      'src/core/own.zig src/core/single_owner.zig src/core/single_owner_copy.zig src/core/runtime/core_owned_copy.c',
      r'zero_rc|single_owner|shared_lists|enableSnapshots|\.retain|\.is_unique|MYL_ZERO_RC|count_|snapshot|copy.on.write',
      'Remove lists-only/RC source contract, snapshot-family opt-in and count/uniqueness execution paths. Retain diagnostics for forbidden IR; never generate executable retain/is_unique. Simplify independent copies and transfers under one ABI.',
      'Owned phi copies, direct cleanup at returns/branches/replacements, recursive box-shell traversal, source borrow and provider checks.',
      'Atomic with mandatory-abi and emitter/runtime groups. Counting IR may not escape through hand-built, cached or unoptimized emission.')
group('llvm-runtime-boundary', 'A07; extra emitter files require coordinator assignment',
      'src/core/emit_llvm.zig src/core/emit_release.zig src/core/emit_cap.zig src/core/emit_text_split.zig src/core/emit_homes.zig',
      r'zero_rc|single_owner|myl_core_(retain|release|share)|countedValue|is_unique|count|one.count',
      'Delete counted header emission/RC helper declarations, countedValue, uniqueness and legacy descriptor callback generation. Emit one kind-at-zero ABI and owned entry/Result cleanup. Invalid RC operations always refuse.',
      'Static-storage kind bit, home/stack destruction, child-layout metadata and direct owned drop calls. Release names are not automatically RC.',
      'A02 header and A05 dictionary layout walkers; A08 mandatory artifact marker before native linking.')
group('container-lowering', 'A07 proposed; A02 owns build_list_methods; A04 owns build_values',
      'src/core/build_bytes.zig src/core/build_cap.zig src/core/build_dict.zig src/core/build_text.zig src/core/build_borrowed_view.zig src/core/fuse_slice_key.zig',
      r'zero_rc|single_owner|snapshot|one counted|counted leaf',
      'Select existing independent copy/take/default/provider/view paths unconditionally. Remove old alias-producing text/bytes copy and dictionary key/value reuse alternatives. Make owned update-fusion proof mandatory.',
      'Borrow selection and aggregate provider validators; scalar operations, take flags, selected-copy semantics, deliberate direct-root-rebind iteration snapshots.',
      'Confirm reservations with coordinator. Source .snapshot() remains explicitly refused; physical fresh copies required for supported independent returns.')
group('list-runtime', 'A02; coordinator shared header approval',
      'src/core/runtime/core_rt.c src/core/runtime/core_bytes.c src/core/build_list_methods.zig',
      r'MYL_ZERO_RC|MYL_SATURATED|MYL_SHARED|MYL_PLAIN_MAX|count_|retain_block|myl_core_(release|share)|core_release|zero_rc|single_owner|copy.on.write',
      'Keep count-free header/static marker and direct traversals. Delete count storage/helpers/saturation/COW arms and conditional buffer_own. Preserve owned rotate/reverse/same_block and deep-child copies; simplify list method forks.',
      'Growth/reserve/overflow guards, allocator live statistics, child visitor, task/provider finalization and counted instrumentation hooks for allocation traffic.',
      'A07 emit descriptors, A05 child walkers, A09 count_runtime anchors must change together. Shared layout remains 32-byte aligned; count-free does not imply zero allocation.')
group('parallel-runtime', 'A01',
      'src/core/runtime/core_tasks.c src/core/build_parallel.zig',
      r'MYL_ZERO_RC|count_retain|myl_core_(release|share)|task_result|task_group_close|owned_task|owned_map|atomic|pending',
      'Remove five RC branches and make owned submit/take/end/map available without selector. Privatize or remove old result/group-close aliases after all generated callers migrate. build_parallel already contains owned chunks only.',
      'Pending-work/ready/futex atomics, mandatory joins, ordered output, environment lifetime and exactly-once untaken-result destruction.',
      'A01 retirement/integration-44947 owns exact three-patch set; A07 build.zig map selector request must integrate. Native stress/TSan after real application.')
group('text-render-runtime', 'A04',
      'src/core/runtime/core_text.c src/core/runtime/core_values.c src/core/build_values.zig',
      r'MYL_ZERO_RC|zero_rc|count_is_unique|retain_block|myl_core_release|one.count',
      'Keep static-literal append copy, fresh text encode bytes, owned float-render cleanup and independent list repetition; delete legacy count/share alternatives.',
      'Unicode/invalid-input behavior, round/format helper contracts, rendering caller-destination work and numeric runtime ABI.',
      'A02 header and A07 emitter/contract agreement; rerun text/JSON allocation controls on exact C3 compiler.')
group('collections-providers-runtime', 'A05',
      'src/core/runtime/core_dict.c src/core/runtime/core_sort.c src/core/runtime/core_io.c src/core/runtime/core_host.c src/core/runtime/core_durable.c',
      r'MYL_ZERO_RC|count_unique|count_retain|count_is_unique|core_release|myl_core_release|cap_retain|s2_sort_keyed|owned_sort_keyed|snapshot',
      'Delete counted dictionary child copies/descriptors, legacy keyed sort, provider retain/root-sharing branches and now-useless cap retain calls. Retain owned transfer paths.',
      'Resource closes, direct cleanup, persistence snapshots as independent storage, filesystem locks and native provider buffers. Host file snapshots are not COW.',
      'A05 retirement previews; A07 lowering selects owned keyed sort; A02 traversal callbacks/header; resource support and protocol gates remain mandatory.')
group('cache-link-abi', 'A08 with A07 mandatory ABI',
      'src/core/lowering_cache.zig src/core/optimization_cache.zig src/core/emission_cache.zig src/core/emission_key.zig src/core/canonical_ir.zig src/core/ir_snapshot.zig src/core/emit_units.zig src/core/driver.zig',
      r'zero_rc|single_owner|shared_lists|MYL_ZERO_RC|runtimeFor|mylang-zero-rc|version|format|schema',
      'Use mandatory checked_owned_v1 in fresh text and compact native receipts. Remove OR aggregation of per-unit mode bits and runtime RC selection. Reject missing/old/foreign/mixed ABI; bump persisted layouts and keys so old false/zero cannot decode as owned.',
      'Complete compiler/source identities, invalid-marker cache misses, no stale green-source replay, debug source origins, counters choice independent of memory ABI.',
      'Root newly assigns driver/emit_units/ir_snapshot to A08; additional key files require exact reservation confirmation. Retained C0 caches must remain frozen for negative transitions.')
group('commands-and-analysis', 'A10; A07 owns allocation_contract narrow validation; coordinator compiler declaration',
      'src/main.zig src/core/main.zig src/core/cli.zig src/core/cli_args.zig src/core/check_command.zig src/core/pipeline.zig src/core/frontend.zig src/core/allocation_contract.zig src/core/cost.zig src/core/cost_command.zig src/core/test_runner.zig src/core/test_runner_affected.zig src/core/test_runner_directory.zig src/doctest_command.zig src/compiler.zig',
      r'zero_rc|single_owner|experimental-single-owner|experimental-zero-rc|one.count|copy.on.write',
      'C2 enable checked ordinary commands only after qualification. C3 remove selectors and internal mode bypasses, keep eager checking across sessions/receipts/portable keys, remove RC encode-noalloc exception, update docs/help and directory/doctest forwarding. Retired flags exit2 including =value; tokens after guest -- remain data.',
      'Diagnostic dump-ir --facts can show failing intermediate IR; its status is not executable qualification. Unsupported-only guest test status0 remains existing contract; qualify only unsupported==0.',
      'CLI patches regenerated at44947 are narrower than full C3 API deletion and must combine with A07/A08 contract. Internal modes cannot remain writable escape hatches.')
group('runtime-instrumentation', 'A09; coordinate emit_count with A07/root',
      'src/core/count_runtime.zig src/core/emit_count.zig src/core/cost_dynamic.zig',
      r'myl_core_(retain|release|share)|count_retain|count_release|retain_block|rc\.|runtime_retains|runtime_releases|release_unique|unique|shared',
      'Remove active RC instrumentation anchors and legacy helper declarations as runtime disappears. Preserve counters-v1 zero RC telemetry fields; direct release_unique is destruction, not a reference decrement.',
      'Allocation/growth/copy/peak/exit-live hooks and exact recursive managed-copy traffic; static cleanup site labels are separate from dynamic RC events.',
      'A09 count runtime/test previews; counter replay adapter must be re-reviewed/requalified for changed C3 runtime recipe, never relabel Support6 controls.')
group('installed-components', 'A10; root build/verify files',
      'selfhost/components.zig selfhost/test_component_native.py selfhost/test_components.py build.zig build_test_inputs.zig src/component_launch.zig src/component_adapter.zig src/cache_plan_adapter.zig scripts/verify_cache.py scripts/affected_tests.py scripts/fuzz_campaign.py',
      r'owned_pin|component_owned_pin|component-seed|memory_mode|ownership_selection|experimental-zero-rc|seed-compiler|affected-compiler|MYLANG_COMPONENT_DIR|artifactSnapshot|artifact_paths|artifact_providers|build.lock|const Manifest',
      'Select a real independently qualified checked-default source pin by default. Pin and manifests require memory_mode=zero-rc-v1, ownership_selection=checked-default-v1 and guest_abi=mylang-checked-owned-v1. Retire legacy fallback and selector forwarding in installed tools/selka-components. Validate these fields at both launch and verification inventory boundaries; refuse stale MYLANG_COMPONENT_DIR deployments.',
      'Immutable historical component-seed.json/commits, independent seed-compiler target, reviewed toolchain, source/hash/protocol evidence, installed bin/libexec/tools layout and newly added build.lock.',
      'Support6 opt-in pin is real and qualified, but is not a selector-free C3 pin. Need actual C3 source commit/archive, RF seed, both fresh protocols/ABI audits and fresh installed package proof.')
group('source-boundary-wording', 'coordinator; exact helper reservations as needed',
      'src/record_layouts.zig src/buffer_operations.zig src/collection_lower.zig',
      r'shared through immutable boxes|\.snapshot|"snapshot"',
      'Update recursive owning-provider diagnostics to owned boxed values; preserve refusal. Remove executable list snapshot lowering/offerings or retain syntax solely for a clear retired/unsupported diagnostic; never permit a COW path.',
      'Persistent/durable semantic snapshots and root-rebinding entry copies retain their independent-storage contracts.',
      'SPEC current clauses and public export documentation must match tested source behavior; historical diagnostics/reports remain immutable.')


def context(source, line):
    names = list(re.finditer(r'(?m)^test "([^"]+)"|^\s*(?:pub )?fn (\w+)\(', '\n'.join(source.splitlines()[:line])))
    return (names[-1].group(1) or names[-1].group(2)) if names else None


def owner(path):
    filename = Path(path).name
    for id in ['a01', 'a02', 'a04', 'a06']:
        if filename.startswith(id + '_'):
            return id.upper()
    if filename.startswith(('task_', 'zero_rc_task')):
        return 'A01'
    if filename in {'count_test.zig', 'ce_lists_test.zig'}:
        return 'A09'
    if filename in {'durable_test.zig', 'durable_fixture.c'}:
        return 'A05'
    if filename in {'single_owner_test.zig', 'zero_rc_test.zig', 'borrow_summary_test.zig', 'own_test.zig', 'row_cow_test.zig', 'shared_counts_test.zig', 'runtime_threads_fixture.c', 'share_walk_fixture.c'}:
        return 'A07/coordinator dispatch'
    if filename.startswith(('test_runner', 'cli_', 'cost_command', 'doctest')):
        return 'A10'
    if 'cache' in filename or filename.startswith(('emit_units', 'driver_')):
        return 'A08/coordinator dispatch'
    if filename in {'component_launch.zig', 'component_protocol_test.zig', 'cache_plan_protocol_test.zig'}:
        return 'A10/root'
    return 'coordinator dispatch'


test_sources = {p: s for p, s in sources.items() if p.startswith('src/') and (re.search(r'(?m)^test ', s) or p.endswith('_fixture.c'))}
selectors = []
controls = []
control_files = {'src/core/own_test.zig', 'src/core/row_cow_test.zig', 'src/core/single_owner_test.zig', 'src/core/shared_counts_test.zig', 'src/core/runtime_threads_fixture.c', 'src/core/share_walk_fixture.c', 'src/core/consume_test.zig', 'src/core/count_test.zig', 'src/core/cost_test.zig', 'src/core/f1_facts_test.zig', 'src/core/ce_records_test.zig', 'src/core/ce2_results_test.zig', 'src/core/iteration_test.zig', 'src/core/dict_test.zig', 'src/core/s3_ir_test.zig'}
for path, source in sorted(test_sources.items()):
    references = [p for p, text in sources.items() if p.endswith('.zig') and ('@import("' + Path(path).name + '")') in text]
    for n, line in enumerate(source.splitlines(), 1):
        if re.search(r'experimental-(?:zero-rc|single-owner)|\b(?:zero_rc_flag|single_owner_flag)\b|-[DU]MYL_ZERO_RC', line):
            selectors.append(dict(path=path, line=n, context=context(source, n), source=line.strip(), owner=owner(path), imported_by=references,
                                  action='Migrate positive invocations to ordinary commands at C3; preserve/add retired-selector negative tests. Do not blanket-delete assertions.'))
    if path in control_files:
        tests = [{'line': n, 'name': line.split('"')[1]} for n, line in enumerate(source.splitlines(), 1) if line.startswith('test "')]
        controls.append(dict(path=path, owner=owner(path), sha256=hashlib.sha256(source.encode()).hexdigest(), imported_by=references, tests=tests,
                             action='Review every listed test. Replace executable RC/COW/implicit-sharing controls with explicit-copy independence, borrow/refusal and direct-cleanup tests retaining outputs/traps. Keep unrelated optimization assertions. Wrong-ABI hand IR may remain only as negative input.'))

report = dict(source_revision=args.source_revision, status='retirement inventory and UNAPPLIED patches only; not milestone completion',
              api_decision='Root: remove optional RC/single_owner/shared_lists; A07 adds guest_abi.Abi.checked_owned_v1; A08 bumps persisted formats and rejects missing/foreign units.',
              groups=groups, registered_selector_sites=selectors, registered_control_suites=controls,
              registration_scope='Direct import references are recorded, including registration roots. They establish registration paths, not executed tests. internal-api-calls.json separately enumerates all API callers, including inline guest sources without RC words.',
              false_positives=['Zig allocator retain_capacity/retained analysis trees are compiler memory, not guest RC.', 'Protocol/cache snapshot digests and sealed byte snapshots are not COW.', 'Task pending/ready counters synchronize work.', 'IR release/direct owned destruction and resource release remain necessary.', 'Independent persistence snapshots and literal static storage remain supported.', 'counters-v1 zero RC labels are telemetry compatibility; release_unique counts direct destruction.'])
args.output_dir.mkdir(parents=True, exist_ok=True)
(args.output_dir / 'retirement-inventory.json').write_text(json.dumps(report, indent=2) + '\n')
lines = ['# Pinned retirement implementation checklist', '', f'Source: `{args.source_revision}`. Every item below is unapplied. C1 and C2 qualification remain prerequisites.', '',
         'Root froze one mandatory `guest_abi.Abi.checked_owned_v1` contract. Remove optional modes and shared-list state; reject missing or foreign ABI at restored-artifact and native-link boundaries. Bump formats/keys so old numeric zero cannot become the new enum accidentally.', '']
for item in groups:
    lines += ['## ' + item['id'], '', '**Owner:** ' + item['owner'] + '.', '', item['action'], '', 'Preserve: ' + item['preserve'], '', 'Dependency: ' + item['dependency'], '', '| File | Pinned hunk anchors |', '| --- | --- |']
    for file in item['files']:
        points = ', '.join(str(x['line']) for x in file['anchors']) or 'semantic audit: no active matching branch'
        lines.append(f"| `{file['path']}` | {points} |")
    lines.append('')
lines += ['## Registered tests and internal callers', '',
          '`retirement-inventory.json` preserves every current selector site, enclosing test/helper, owner suggestion and importing registration file. It also lists every test name in the legacy-control suites; this is a review obligation, not permission to drop a suite. `internal-api-calls.json` includes the remaining inline-source and hand-IR drivers even when their text has no RC word.', '',
          'C2 must run ordinary guest commands across the full registered suite and repair source semantics/expected default diagnostics. C3 removes the selector from positive tests, replaces counted/COW assertions with owned/refusal assertions, and migrates all direct API constructors. Preserve every existing output, error-path and trap oracle unless the retired source contract itself is the negative assertion. Never set an active test back to RC to make the gate pass.', '',
          'High-risk suites: own_test, row_cow_test, single_owner_test snapshot families, shared_counts/runtime_threads/share_walk, consume_test borrowed-alias controls, count_test snapshot comparison, cost_test RC sites, f1/CE record/result/iteration/dictionary controls. Keep zero_rc negative snapshots, borrow_summary invalid count-op cases, and wrong-ABI tests as explicit refusals.', '',
          'The raw site/call totals are inventory sizes only. They are not remaining-bug counts or measured test completion.', '',
          '## Package blockers beyond flags', '',
          'The pinned default component builder still reads historical component-seed.json when no owned override is supplied. tools/selka-components is installed and therefore that route itself must retire. Root build and native component test forwarding are optional today; affected-compiler and verification preparation inherit that choice. scripts/affected_tests.py and fuzz fallback component directories must observe the resulting installed owned package.', '',
          'Both component adapters call component_launch.artifactSnapshot, whose current Manifest ignores memory_mode and ownership_selection. MYLANG_COMPONENT_DIR can therefore choose a digest-valid legacy package. The prepared C3 launch patch rejects missing/legacy/opt-in markers and revalidates warm planner bindings. Synthetic manifest tests are boundary tests, never ABI proof.', '',
          'scripts/verify_cache.py artifact_paths/artifact_providers currently admit filename-only component manifests; coordinator must add matching owned package proof and fixture coverage. Component reference/shadow modes select host Zig oracle implementations and remain legitimate; they are not guest memory modes.', '',
          'Support6 independent RF seed/compiler and both exact component sources have real protocol/count/ABI evidence, but still select ownership with a prototype flag. A real selector-free C3 source pin, archive, compiler, component receipts/binaries and installed layout must be freshly qualified. Historical seeds remain unchanged. Preserve the newly integrated components build.lock.', '',
          '## Deliberate non-RC matches', '']
lines += ['- ' + item for item in report['false_positives']]
(args.output_dir / 'retirement-checklist.md').write_text('\n'.join(lines) + '\n')
print(json.dumps({'groups': len(groups), 'selector_sites': len(selectors), 'control_suites': len(controls), 'status': 'inventory, not qualification'}))
