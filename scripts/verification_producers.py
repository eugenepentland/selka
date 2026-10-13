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
import verification_code_identity as code_identity
from pathlib import Path
import re
import sys

from verification_snapshot import Snapshot

VERSION = 2
DOMAIN = 'selka-qualified-native-producer-v2'
INTERFACE = 'guardian-zig-test-runner-v1'
ABI = 'zig-native-test-executable-v1'
MODES = {'debug', 'release_safe', 'release_fast', 'release_small'}
MODE_ALIASES = dict(Debug='debug', ReleaseSafe='release_safe',
                    ReleaseFast='release_fast', ReleaseSmall='release_small')
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
    mode = MODE_ALIASES.get(mode, mode)
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


NATIVE_DOMAIN = 'selka-native-producer-recipes-v1'
NATIVE_FIELDS = frozenset({'recipes', 'optimize', 'zig_version', 'test_runner'})


class ProducerError(ValueError):
    """A declared producer cannot be identified soundly; never an empty identity."""


def native_producer(record: dict | None, label: str) -> tuple[dict | None, str]:
    """Return the version-3 recipe producer of `label`, or None and why not.

    `artifacts.json` version 3 declares it beside the artifact, as
    `artifacts[label] = {"path": ..., "producer": {...}}`, or in
    `producers[label]` when that object has `recipes`. The producer must hold
    exactly `recipes` (relative, nonempty, unique), `optimize`, `zig_version`
    and `test_runner`; anything else falls back to the artifact's bytes.
    """
    if not isinstance(record, dict) or type(record.get('version')) is not int or record['version'] != 3:
        return None, 'artifact inventory is not version 3'
    entry = record.get('artifacts', {}).get(label) if isinstance(record.get('artifacts'), dict) else None
    beside = entry.get('producer') if isinstance(entry, dict) else None
    listed = record.get('producers', {}).get(label) if isinstance(record.get('producers'), dict) else None
    if not (isinstance(listed, dict) and 'recipes' in listed):
        listed = None
    if beside is not None and listed is not None:
        return None, 'producer declared twice'
    producer = beside if beside is not None else listed
    if producer is None:
        return None, 'no producer declared'
    if not isinstance(producer, dict) or set(producer) != NATIVE_FIELDS:
        return None, 'producer fields are not exactly ' + ', '.join(sorted(NATIVE_FIELDS))
    recipes = producer['recipes']
    if (not isinstance(recipes, list) or not recipes or len(set(map(str, recipes))) != len(recipes)
            or not all(isinstance(recipe, str) and recipe and not recipe.startswith('/') for recipe in recipes)):
        return None, 'producer recipes must be unique nonempty relative strings'
    if not all(isinstance(producer[field], str) and producer[field] for field in ('optimize', 'zig_version')):
        return None, 'producer optimize and zig_version must be nonempty strings'
    if producer['test_runner'] in (None, '', [], {}):
        return None, 'producer test_runner is empty'
    return producer, ''


def native_identity(label: str, producer: dict, select) -> dict:
    """Identify a native artifact by what produced it instead of its bytes.

    `select(recipe)` returns the watched, hashed records (preparation sources
    and build configuration) that one recipe selects. The identity binds each
    selected file's content and permissions, the recipes themselves and the
    producer's optimize mode, Zig version and test-runner identity; it holds no
    location. A recipe that selects nothing is an error: the recipe is wrong or
    lies outside the watched inputs, and an incomplete closure must not
    silently identify the artifact.
    """
    sources = {}
    for recipe in producer['recipes']:
        selected = select(recipe)
        if not selected:
            raise ProducerError('producer recipe of %s selects no watched input: %s' % (label, recipe))
        for item in selected:
            row = dict(path=item['path'], **content(item))
            if 'resolved' in item:
                row['resolved'] = item['resolved']
            sources[item['path']] = row
    return {'domain': NATIVE_DOMAIN, 'label': label, 'recipes': list(producer['recipes']),
            'optimize': producer['optimize'], 'zig_version': producer['zig_version'],
            'test_runner': producer['test_runner'],
            'sources': [sources[path] for path in sorted(sources)]}


def qualified_identity(record: dict, label: str, artifact_files: list[dict],
                       source_files: list[dict], context: dict) -> dict | None:
    """Authorize projection only when exact metadata agrees with watched bytes.

For these opted-in producers, None requires the whole prepared-artifact identity.
Preexisting independently reviewed providers retain their original contracts;
unknown new narrowing still needs proof. Inherited context includes all arbitrary
build code, Guardian runner/diagnostic source and pinned Zig tools/library bytes.
"""
    try:
        if type(record.get('version')) is not int or record['version'] not in (2, 3):
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
                or metadata['mode'] != MODE_ALIASES.get(inherited['action_controls']['optimize'],
                                                       inherited['action_controls']['optimize'])):
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


_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
