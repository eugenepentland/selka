"""Read-only replay of independent metadata, ELF, arithmetic and archive checks."""
import base64
import contextlib
import gzip
import hashlib
import io
import json
from pathlib import Path
import runpy

HERE = Path(__file__).resolve().parent
review = json.loads((HERE / 'review.json').read_bytes())


def sha(data):
    return hashlib.sha256(data).hexdigest()


for group in ['reviewed_script_sha256', 'reviewed_results_sha256']:
    for name, digest in review[group].items():
        assert sha((HERE / name).read_bytes()) == digest
archive = (HERE / 'inputs.json.gz').read_bytes()
assert sha(archive) == review['inputs_archive_sha256']
inputs = json.loads(gzip.decompress(archive))
assert len(inputs) == review['saved_input_copies'] == 47
assert set(inputs) == set(review['input_paths_sha256'])
for path, row in inputs.items():
    data = base64.b64decode(row['base64'], validate=True)
    assert sha(data) == row['sha256'] == review['input_paths_sha256'][path]
    assert Path(path).read_bytes() == data
assert sha((HERE / 'partial-check.json').read_bytes()) == review['preserved_historical_reads']['partial_check_sha256']
assert sha((HERE / 'wall-check.json').read_bytes()) == review['preserved_historical_reads']['completed_wall_check_sha256']
output = io.StringIO()
with contextlib.redirect_stdout(output):
    runpy.run_path(str(HERE / 'full-check.py'))
actual = json.loads(output.getvalue())
assert actual == json.loads((HERE / 'full-check.stdout').read_bytes())
assert actual['completed_coverage'] == review['completed_coverage'] == dict(smoke=156, screen=104, wall=468, counters=468)
assert actual['completed_total'] == review['completed_total'] == sum(review['completed_coverage'].values()) == 1196
assert actual['screen_plus_full_PMU_events_at100'] == review['PMU_events_at100'] == 2288
assert actual['computed_counter_metrics'] == review['counter_metrics']
assert actual['archive_manifest_sha256'] == review['archive_manifest_sha256']
assert actual['archive_originals'] == 375 and actual['archive_objects'] == 276
assert not review['performance_selection_main_merge_or_parity_inferred']
print(json.dumps(dict(verified=True, saved_input_copies=47,
    actual_source37_guests_sidecars_runtime_ELFs_checked=True,
    prospective_preparation_inputs=1038, exact_guard_inventory=252, actual_native_runtime_roles=6,
    completed_coverage=review['completed_coverage'], completed_total=1196,
    PMU_four_event_rates100=2288, all_paired_arithmetic_verified=True,
    archive_manifest_sha256=review['archive_manifest_sha256'],
    archive_original_paths=375, archive_objects=276,
    historical_partial_reads_and_refusals_preserved=True,
    no_compiler_guest_native_or_performance_execution=True,
    selection_main_merge_or_parity_inferred=False), indent=2))
