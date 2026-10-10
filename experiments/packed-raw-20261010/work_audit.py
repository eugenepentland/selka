#!/usr/bin/env python3
"""Audit cached body replay and native module/function regeneration without builds."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import struct


PHASES = ('entry_edit', 'helper_edit', 'three_file_edit')
EXPECTED_SOURCE_EDITS = {'entry_edit': 1, 'helper_edit': 1, 'three_file_edit': 3}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def elf_functions(path):
    """Read exact defined ELF64 little-endian STT_FUNC ranges in their sections."""
    data = path.read_bytes()
    assert data[:6] == b'\x7fELF\x02\x01', path
    assert struct.unpack_from('<H', data, 16)[0] == 1, 'Expected relocatable object'
    section_offset = struct.unpack_from('<Q', data, 40)[0]
    section_size, section_count, _ = struct.unpack_from('<HHH', data, 58)
    assert section_size == 64 and section_count != 0
    assert section_offset + section_size * section_count <= len(data)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, section_offset + section_size * i)
                for i in range(section_count)]
    functions = {}
    for section in sections:
        if section[1] != 2:  # SHT_SYMTAB
            continue
        assert section[9] == 24 and section[5] % 24 == 0
        strings_section = sections[section[6]]
        strings = data[strings_section[4]:strings_section[4] + strings_section[5]]
        for offset in range(section[4], section[4] + section[5], 24):
            name_offset, info, _, owner, value, size = struct.unpack_from('<IBBHQQ', data, offset)
            if info & 15 != 2 or owner == 0:  # STT_FUNC, defined
                continue
            assert owner < len(sections) and name_offset < len(strings)
            name = strings[name_offset:].split(b'\0', 1)[0].decode()
            target = sections[owner]
            assert value <= target[5] and size <= target[5] - value
            assert target[4] + value + size <= len(data)
            text = data[target[4] + value:target[4] + value + size]
            assert name not in functions
            functions[name] = {'bytes': text, 'size': size, 'sha256': sha(text),
                               'section_index': owner, 'section_offset': value,
                               'binding': info >> 4}
    return {'path': str(path), 'sha256': sha(data), 'functions': functions}


def summarize_counts(row):
    cache = row['cache']
    stages = cache['stages']
    lower, optimizer, emission = stages['lowering'], stages['optimizer'], stages['emission']
    return {
        'raw_functions_total': lower['materialized'] + lower['unloaded'],
        'raw_bodies_materialized': lower['materialized'],
        'raw_bodies_unloaded': lower['unloaded'],
        'fresh_lowered_functions': lower['lowered'],
        'lowering_reused': lower['reused'],
        'final_bodies_materialized': optimizer['final_loaded'],
        'final_artifacts_restored': optimizer['restores']['final'],
        'checkpoint_artifacts_restored': optimizer['restores']['checkpoints'],
        'optimizer_active_functions': optimizer['active_functions'],
        'optimizer_fresh_final_functions': optimizer['fresh_work'],
        'optimizer_stage_hits': optimizer['hits'],
        'optimizer_stage_misses': optimizer['misses'],
        'emission_units_total': emission['units'],
        'emission_units_rendered': emission['rendered'],
        'emission_units_reused': emission['reused'],
        'emission_keys_built': emission['work']['keys_built'],
        'llvm_bytes_loaded': emission['work']['llvm_loaded_bytes'],
        'native_units_compiled': cache['compiled'],
        'native_units_reused': cache['reused'],
        'native_units_verified': cache['verified'],
        'frontend_bodies_checked': stages['frontend']['checked'],
    }


def object_group(row):
    objects, functions = [], {}
    for name in row['new_objects']:
        loaded = elf_functions(Path(name))
        guest = {name: info for name, info in loaded['functions'].items() if name.startswith('my.')}
        objects.append({'path': loaded['path'], 'sha256': loaded['sha256'],
                        'guest_function_symbols': len(guest),
                        'other_function_symbols': sorted(set(loaded['functions']) - set(guest))})
        for symbol, info in guest.items():
            assert symbol not in functions
            functions[symbol] = dict(info, object_path=loaded['path'], object_sha256=loaded['sha256'])
    return objects, functions


def comparison(before, after):
    objects_before, functions_before = object_group(before)
    objects_after, functions_after = object_group(after)
    symbols = []
    for name in sorted(set(functions_before) | set(functions_after)):
        left, right = functions_before.get(name), functions_after.get(name)
        equal = left is not None and right is not None and left['bytes'] == right['bytes']
        symbols.append({'symbol': name, 'instruction_bytes_equal': equal,
                        'before': {key: value for key, value in left.items() if key != 'bytes'} if left else None,
                        'after': {key: value for key, value in right.items() if key != 'bytes'} if right else None})
    return {'copies': before['copies'], 'phase': before['phase'],
            'samples_compared': [before['sample'], after['sample']],
            'objects_before': objects_before, 'objects_after': objects_after,
            'guest_function_symbols_before': len(functions_before),
            'guest_function_symbols_after': len(functions_after),
            'unchanged_instruction_byte_ranges': sum(symbol['instruction_bytes_equal'] for symbol in symbols),
            'changed_or_missing_instruction_byte_ranges': sum(not symbol['instruction_bytes_equal'] for symbol in symbols),
            'symbols': symbols}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    here = Path(__file__).resolve().parent
    parser.add_argument('--reports', type=Path, default=here / 'paired-raw.json.gz')
    parser.add_argument('--output', type=Path, default=here / 'work-audit.json')
    args = parser.parse_args()
    archived = args.reports.resolve()
    data = archived.read_bytes()
    report = json.loads(gzip.decompress(data) if archived.suffix == '.gz' else data)
    rows = [row for row in report['records'] if row['variant'] == 'candidate' and row['phase'] in PHASES]
    result = {
        'report_path': str(archived), 'report_archive_sha256': sha(data),
        'method': 'Read archived candidate work counters and the exact referenced existing ELF objects. Parse ELF64 SHT_SYMTAB STT_FUNC entries, extract each defined guest symbol from its owning section, and compare samples0→1 and1→2. No builds, cache mutation, compiler runs or LLVM inventory inference.',
        'counter_caveats': [
            'Materialized raw/final bodies include cached deserialization and fresh work; they are not counts of newly compiled functions.',
            'optimizer_fresh_final_functions counts final analysis/cache misses. Earlier optimizer passes can execute for other functions; their stage misses are reported separately.',
            'Lowering reused, deferred, raw materialization and optimizer restores describe different events and must not be added together.',
            'Native compiled counts whole source-module units. Defined native symbols omit LLVM functions eliminated or inlined by the native compiler.',
        ],
        'instruction_comparison_limitations': [
            'Raw function instruction-byte equality is not full relocation, literal-pool, debug-information or execution equivalence. Relocations and referenced data can change even with identical function bytes.',
            'The entry edit changes string data. Its required native object changes despite unchanged guest function instruction bytes; zero instruction changes does not mean the object can be reused.',
            'Unchanged function ranges demonstrate regeneration caused by module granularity, not a proof that arbitrary per-function object reuse would be safe.',
            'These comparisons use consecutive benchmark edits, not the original unedited source. They establish what stayed unchanged between those measured samples.',
        ],
        'source_edit_contract': {'entry_edit': 'One usage-string edit in c000/src/main.my.',
                                 'helper_edit': 'One is_upper body edit in c000/src/support_strs.my.',
                                 'three_file_edit': 'Entry usage string plus is_upper in c000 and c001 support_strs modules.',
                                 'benchmark_source': '../incremental-stages-20261009/benchmark.py'},
        'work': [], 'native_function_comparisons': []}
    for copies in sorted({row['copies'] for row in rows}):
        for phase in PHASES:
            samples = sorted([row for row in rows if row['copies'] == copies and row['phase'] == phase],
                             key=lambda row: row['sample'])
            counts = [summarize_counts(row) for row in samples]
            stable_fields = ('raw_bodies_materialized', 'final_bodies_materialized', 'fresh_lowered_functions',
                             'optimizer_fresh_final_functions', 'emission_units_rendered', 'native_units_compiled')
            assert all(all(value[field] == counts[0][field] for field in stable_fields) for value in counts)
            for row, count in zip(samples, counts):
                result['work'].append({'copies': copies, 'phase': phase, 'sample': row['sample'],
                                       'sources_changed_by_fixture': EXPECTED_SOURCE_EDITS[phase],
                                       'extra_native_units_over_changed_sources': count['native_units_compiled'] - EXPECTED_SOURCE_EDITS[phase],
                                       'command': row['command'], 'cwd': row['cwd'], 'counts': count})
            for left, right in zip(samples, samples[1:]):
                result['native_function_comparisons'].append(comparison(left, right))
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'{len(result["work"])} work rows and {len(result["native_function_comparisons"])} ELF comparisons → {args.output}')
    for item in result['native_function_comparisons']:
        print(item['copies'], item['phase'], item['samples_compared'],
              'unchanged', item['unchanged_instruction_byte_ranges'],
              'changed', item['changed_or_missing_instruction_byte_ranges'])


if __name__ == '__main__':
    main()
