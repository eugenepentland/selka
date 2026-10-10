#!/usr/bin/env python3
"""Summarize saved profile.py text evidence without invoking perf or a compiler."""
import argparse
import hashlib
import json
from pathlib import Path
import re


ROW = re.compile(r'^\s*([\d.]+)%\s+([\d.]+)%\s+(\S+)\s+(.+?)\s+\[(.)\]\s+(.+)$')


def read(path):
    return json.loads(path.read_text())


def parse_rows(text):
    rows = []
    for line in text.splitlines():
        if not re.match(r'^\s*[\d.]+%', line):
            continue
        match = ROW.match(line)
        if match is None:
            raise ValueError(f'unrecognized perf row: {line}')
        children, own, command, dso, privilege, tail = match.groups()
        rows.append({'children_pct': float(children), 'self_pct': float(own),
                     'command': command, 'dso': dso.strip(), 'privilege': privilege,
                     'symbol': re.split(r'\s{2,}', tail.strip(), maxsplit=1)[0]})
    if not rows:
        raise ValueError('perf report contains no flat percentage rows')
    # One report may contain multiple events with separate denominators. Never
    # combine their percentages into a seemingly meaningful aggregate.
    if len(re.findall(r'^# Samples:', text, re.MULTILINE)) > 1:
        raise ValueError('multiple perf events need separate reports/denominators')
    return rows


def self_groups(rows):
    def total(predicate):
        return round(sum(row['self_pct'] for row in rows if predicate(row)), 2)
    groups = {
        'blake3': total(lambda r: 'crypto.blake3.' in r['symbol']),
        'sha2': total(lambda r: 'crypto.sha2.' in r['symbol']),
        'treehash': total(lambda r: 'lowering_cache.TreeHash.' in r['symbol']),
        'unresolved_including_zig': total(lambda r: r['symbol'].startswith('0x') or
                                         r['symbol'] == '[unknown]' or r['dso'] == '[unknown]'),
        'memfd_planner': total(lambda r: 'memfd:mylang-planner' in r['dso']),
        'mylang_host_dso': total(lambda r: Path(r['dso']).name == 'mylang'),
        'zig': total(lambda r: r['command'] == 'zig'),
    }
    groups['blake3_plus_sha2'] = round(groups['blake3'] + groups['sha2'], 2)
    groups['hashing_plus_named_treehash_self'] = round(groups['blake3_plus_sha2'] + groups['treehash'], 2)
    return groups


def summarize_profile(directory, record, top):
    label = record['label']
    report_path = directory / f'{label}.perf-report.txt'
    report = report_path.read_text()
    rows = parse_rows(report)
    stderr = (directory / f'{label}.stderr.txt').read_text()
    exact = re.findall(r'\((\d+) samples\)', stderr)
    headers_path = directory / f'{label}.perf-headers.txt'
    headers = headers_path.read_text() if headers_path.exists() else ''
    lost = re.findall(r'^# Total Lost Samples:\s*(\d+)', report, re.MULTILINE)
    item = {key: record[key] for key in ['label', 'wall_s', 'user_s', 'system_s', 'peak_rss_kb', 'exit', 'counts']}
    item.update(recorded_samples=sum(map(int, exact)) if exact else None,
                lost_samples=sum(map(int, lost)) if lost else None,
                event_headers=re.findall(r'^# Samples:.*$', report, re.MULTILINE),
                self_pct_groups=self_groups(rows),
                top_self=sorted(rows, key=lambda r: -r['self_pct'])[:top],
                flat_row_count=len(rows), rounded_self_pct_total=round(sum(r['self_pct'] for r in rows), 2),
                host_hash_rows_with_distinct_children=sum(
                    r['children_pct'] != r['self_pct'] for r in rows
                    if Path(r['dso']).name == 'mylang' and
                    ('crypto.blake3.' in r['symbol'] or 'crypto.sha2.' in r['symbol'])),
                stack_coverage=None,
                header_diagnostics=[line for line in headers.splitlines()
                                    if line.startswith('Invalid ') or 'event desc: not available' in line],
                perf_exits={key: value for key, value in record.items() if key.startswith('perf_') and key.endswith('_exit')},
                raw_report=str(report_path), raw_report_sha256=hashlib.sha256(report_path.read_bytes()).hexdigest())
    return item


def summarize(directory, admission=None, top=12):
    evidence_path = directory / 'results.json'
    evidence = read(evidence_path)
    if evidence.get('mode') != 'perf' or 'completed_utc' not in evidence:
        raise ValueError('completed perf profile evidence is required')
    if len(evidence['records']) != 2 or any(record['exit'] != 0 for record in evidence['records']):
        raise ValueError('both successful edit and restore profiles are required')
    if evidence['original_source_sha256'] != evidence['restored_source_sha256']:
        raise ValueError('profile source restoration did not match original bytes')
    result = {key: evidence[key] for key in ['started_utc', 'completed_utc', 'compiler', 'benchmark',
              'variant', 'phase', 'token', 'affinity', 'queue_s', 'held_s',
              'original_source_sha256', 'restored_source_sha256']}
    result['evidence'] = str(evidence_path)
    result['evidence_sha256'] = hashlib.sha256(evidence_path.read_bytes()).hexdigest()
    result['method'] = ('Diagnostic inherited-process profile. Categories sum flat event-weighted self percentages only; '
                        'children percentages are retained for context and never summed. Report percentages are rounded, '
                        'not wall-time percentages. GNU time RSS is maximum individual process RSS.')
    result['profiles'] = [summarize_profile(directory, record, top) for record in evidence['records']]
    result['symbolization'] = evidence.get('symbols', [])
    result['limitations'] = [
        'Flat reports cannot recover per-event DWARF stack coverage or establish hash callers; stack_coverage is null. '
        'Equal children/self percentages on host hash rows provide no cumulative caller attribution.',
        'Unresolved and planner memfd self samples cannot be attributed to component functions. '
        'Category totals overlap except the combined hashing categories, whose inputs are disjoint; do not sum all categories.',
        'CPU and wall include perf/snapshot overhead. Paired uninstrumented benchmarks are required for performance claims.',
    ]
    if any(item['header_diagnostics'] for item in result['profiles']):
        result['limitations'].append('Perf header decoding diagnostics are retained; successful flat decoding does not repair missing event metadata.')
    if any(symbol.get('buildid_cache_exit', 0) != 0 or symbol.get('buildid_cache_stderr')
           for symbol in result['symbolization']):
        result['limitations'].append('Symbol-cache diagnostics are retained even when buildid-cache exits zero; exit zero alone does not prove symbol indexing succeeded.')
    if admission is not None:
        path = admission / 'results.json' if admission.is_dir() else admission
        admitted = read(path)
        if admitted['wrapper_exit'] != 0:
            raise ValueError('admission wrapper did not complete successfully')
        result['admission'] = {'evidence': str(path), 'method': admitted['method'],
                               **{key: admitted[key] for key in ['kind', 'queue_s', 'held_s', 'command_wall_s', 'wrapper_exit']},
                               'command_metrics': admitted['completion']['metrics']}
        result['queue_s'] = admitted['queue_s']
        result['held_s'] = admitted['held_s']
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True, help='completed profile.py output directory')
    parser.add_argument('--admission', type=Path, help='optional wrapper directory or results.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--top', type=int, default=12)
    args = parser.parse_args()
    if args.top < 1:
        parser.error('--top must be positive')
    result = summarize(args.profile.resolve(), args.admission, args.top)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'profiles': len(result['profiles'])}))


if __name__ == '__main__':
    main()
