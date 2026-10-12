#!/usr/bin/env python3
"""Authenticate reviewed native producer closures; unknown contracts stay broad.

These are developer verification identities, not compiler/bootstrap seed receipts.
Artifact/source files must come from live Snapshot projections. Callers must retain
those snapshots through lookup, execution and publication; metadata is never a
substitute for mutation/ABA authority. Build/Guardian and Zig-library closures are
inherited from the coordinator's watched build_configuration and tools contexts.
"""
from __future__ import annotations

import hashlib
import json
import marshal
from pathlib import Path
import re
import sys

from verification_snapshot import Snapshot

VERSION = 1
DOMAIN = 'selka-qualified-native-producer-v1'
INTERFACE = 'guardian-zig-test-runner-v1'
ABI = 'zig-native-test-executable-v1'
MODES = {'Debug', 'ReleaseSafe', 'ReleaseFast', 'ReleaseSmall'}
CLOSURES = {
    'tooling-units': (
        'src/tooling_root_test.zig', 'src/doc_coverage_test.zig', 'src/doc_coverage.zig',
        'src/input_probe_test.zig', 'src/input_probe.zig', 'src/fix_plan_test.zig',
        'src/fix_plan.zig', 'src/timings_test.zig', 'src/timings.zig',
        'src/invalidation_test.zig', 'src/invalidation.zig',
    ),
    'text-scalar-units': (
        'src/text_scalar_root_test.zig', 'src/number_text_test.zig', 'src/number_text.zig',
        'src/format_spec_test.zig', 'src/format_spec.zig',
        'src/number_grammar.txt', 'src/format_spec_cases.tsv',
    ),
}


def digest(value: object) -> str:
    """Hash canonical metadata, independently of its storage location."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def closure_supported(root: Path, label: str) -> bool:
    """Reject unknown local imports/embedded inputs and nonliteral dependencies."""
    closure = set(CLOSURES.get(label, ()))
    if not closure:
        return False
    for name in closure:
        path = root / name
        if path.is_symlink() or not path.is_file():
            return False
        if not name.endswith('.zig'):
            continue
        source = path.read_text()
        calls = re.findall(r'@(import|embedFile)\s*\(\s*"([^"\\]*)"\s*\)', source)
        if len(calls) != len(re.findall(r'@(import|embedFile)\b', source)):
            return False
        for kind, value in calls:
            if kind == 'import' and value == 'std':
                continue
            dependency = (Path(name).parent / value).as_posix()
            if dependency not in closure:
                return False
    return True


def content(item: dict) -> dict:
    """Keep implementation bytes and executable permissions, excluding locations."""
    return {field: item[field] for field in ('sha256', 'size', 'mode')}


def producer_metadata(root: Path, label: str, artifact: Path, mode: str) -> dict | None:
    """Capture one reviewed producer, or decline narrowing for a changed closure."""
    if mode not in MODES:
        raise ValueError('unsupported producer optimize mode: ' + mode)
    if label not in CLOSURES or not closure_supported(root, label):
        return None
    with Snapshot(root, list(CLOSURES[label])) as sources, Snapshot(root, [], [artifact]) as binary:
        source_files = sources.identity['files']
        if any('resolved' in item for item in source_files):
            return None
        result = {
            'version': VERSION, 'domain': DOMAIN, 'label': label,
            'implementation': content(binary.identity['files'][0]),
            'sources': sorted((dict(path=item['path'], **content(item)) for item in source_files),
                              key=lambda item: item['path']),
            'interface': INTERFACE, 'abi': ABI, 'mode': mode, 'seed': None,
            'context': ['build_configuration', 'tools', 'options', 'action_controls'],
        }
        # Recheck the declaration scan inside the watched interval too.
        if not closure_supported(root, label) or not sources.unchanged() or not binary.unchanged():
            raise ValueError('producer changed while capturing metadata: ' + label)
        return result


def qualified_identity(record: dict, label: str, artifact_files: list[dict],
                       source_files: list[dict], context: dict) -> dict | None:
    """Authorize projection only when exact metadata agrees with watched bytes.

None requires retaining the whole prepared-artifact identity. Do not fall back to
an unauthenticated per-label identity. Inherited context includes all arbitrary
build code, Guardian runner/diagnostic source and pinned Zig tools/library bytes.
"""
    try:
        if type(record.get('version')) is not int or record['version'] != 2:
            return None
        metadata = record['producers'][label]
        fields = {'version', 'domain', 'label', 'implementation', 'sources',
                  'interface', 'abi', 'mode', 'seed', 'context'}
        if (label not in CLOSURES or not isinstance(metadata, dict) or set(metadata) != fields
                or type(metadata['version']) is not int or metadata['version'] != VERSION
                or metadata['domain'] != DOMAIN or metadata['label'] != label
                or metadata['interface'] != INTERFACE or metadata['abi'] != ABI
                or metadata['seed'] is not None or metadata['mode'] not in MODES
                or metadata['context'] != ['build_configuration', 'tools', 'options', 'action_controls']):
            return None
        inherited = {field: context[field] for field in metadata['context']}
        if (not all(isinstance(inherited[field], str) and re.fullmatch('[0-9a-f]{64}', inherited[field])
                    for field in ('build_configuration', 'tools'))
                or not isinstance(inherited['options'], list)
                or not all(isinstance(option, str) for option in inherited['options'])
                or metadata['mode'] != inherited['action_controls']['optimize']):
            return None
        if len(artifact_files) != 1 or metadata['implementation'] != content(artifact_files[0]):
            return None
        selected = [item for item in source_files if item['path'] in CLOSURES[label]]
        if (len(selected) != len(CLOSURES[label]) or any('resolved' in item for item in selected)
                or len({item['path'] for item in selected}) != len(selected)):
            return None
        expected = sorted((dict(path=item['path'], **content(item)) for item in selected),
                          key=lambda item: item['path'])
        if metadata['sources'] != expected:
            return None
        return dict(metadata, inherited=inherited)
    except (KeyError, TypeError, ValueError, AttributeError):
        return None


LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()
