#!/usr/bin/env python3
"""Generate a searchable reference from a pinned compiler's feature and schema reports."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from bindings import file_digest, store, validate_schema_report

DEFAULT_MODULES = ('base64', 'hex', 'json', 'math', 'path', 'pool', 'random', 'sort', 'strings', 'time')
FILES = ('reference.md', 'api.md', 'features.json', 'schema.json')
MAX_REPORT_BYTES = 32 * 1024 * 1024


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def compiler_json(compiler, arguments):
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        result = subprocess.run([str(compiler), *arguments], stdout=output, stderr=errors, timeout=60)
        errors.seek(0)
        diagnostic = errors.read(8192).decode(errors='replace')
        if result.returncode:
            raise ValueError(f'compiler {arguments[0]} failed ({result.returncode}): {diagnostic.strip()}')
        output.seek(0)
        data = output.read(MAX_REPORT_BYTES + 1)
        if len(data) > MAX_REPORT_BYTES:
            raise ValueError('compiler report exceeds 32 MiB limit')
        return json.loads(data)


def identity_of(compiler):
    """The compiler's own build-time identity, as it reports it; not a hash of the executable."""
    features = compiler_json(compiler, ['--features'])
    if features.get('version') != 'language-features-v1' or not isinstance(features.get('compiler_sha256'), str):
        raise ValueError('unsupported feature report')
    return features['compiler_sha256'], features


def collect(compiler, selection):
    identity, features = identity_of(compiler)
    if selection['entry']:
        report = compiler_json(compiler, ['schema-project', selection['entry'], '--schema-report'])
    else:
        with tempfile.TemporaryDirectory(prefix='mylang-reference-') as temporary:
            entry = Path(temporary) / 'reference.my'
            entry.write_text('module reference\n' + ''.join('import ' + name + '\n' for name in selection['modules']) + '\ndef main() -> i64:\n    return 0\n')
            report = compiler_json(compiler, ['schema-project', str(entry), '--schema-report'])
    validate_schema_report(report)
    if report['source']['implementation']['compiler_sha256'] != identity or identity_of(compiler)[0] != identity:
        raise ValueError('compiler changed while generating reference')
    return identity, features, report


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def render(identity, features, report, selection):
    facts = features['features']
    schema = report['schema']
    modules = sorted({item['module'] for item in report['source']['sources'] if item['module'] != schema['entry']})
    scope = 'project ' + selection['entry'] if selection['entry'] else 'standard modules ' + ', '.join(selection['modules'])
    overview = ['# Compiler reference', '', 'Compiler SHA256: ' + identity, '',
                'Scope: ' + scope, '',
                'Generated from this executable; compiler source files and checkout documentation were not used.',
                'API coverage is reachable checked exports and reported generic templates, not every language builtin.',
                'Read api.md for signatures and types; features.json and schema.json preserve the full reports.',
                'Run this tool with --check to detect changed compiler, sources, or artifacts.', '',
                'Language version: ' + facts['language_version'],
                'Backend: ' + facts['primary_backend'] + ' native code (the only runtime)', '',
                '## Reported implemented features', '',
                'Each feature reports its kind, a one-line summary, and the checkout documentation',
                'section that demonstrates it; `mylang doc-coverage` keeps those pointers resolvable.', '']
    overview += [f"- {slug} [{entry['kind']}] — {entry['summary']} ({entry['doc']})"
                 for slug, entry in facts['implemented'].items()]
    overview += ['',
                '## Reported exclusions', '', 'Unsupported: ' + (', '.join(facts['unsupported']) or '(none reported)'),
                'Native exclusions: ' + (', '.join(facts['native_exclusions']) or '(none reported)'), '',
                '## Reported limits', '']
    overview += ['- ' + key + ': ' + str(value) for key, value in sorted(facts['limits'].items())]
    overview += ['', '## API coverage', '', 'Reachable imported modules: ' + ', '.join(modules),
                 f"Concrete functions: {len(schema['functions'])}; types: {len(schema['types'])}; generic templates: {len(schema.get('generic_templates', []))}.",
                 'Generic contracts retain the compiler-reported requirements and declared effect ceilings.',
                 'They are templates, not a claim that every specialization has been checked.', '']
    api = ['# Checked API reference', '', 'Compiler SHA256: ' + identity,
           'Schema SHA256: ' + report['schema_sha256'], 'Source SHA256: ' + report['source_sha256'], '',
           'Schema notation below is descriptive, not copy-paste language syntax.',
           'Parameter modes and generic contracts are preserved exactly; see schema.json for complete provenance.', '',
           '## Concrete functions', '']
    for function in sorted(schema['functions'], key=lambda item: item['name']):
        parameters = ', '.join(p['name'] + ': ' + p['type'] + ' [' + p['mode'] + ']' for p in function['parameters'])
        api.append(f"- {function['name']}({parameters}) -> {function['result']}; effects={compact(function['effects'])}")
    api += ['', '## Types', '']
    for item in sorted(schema['types'], key=lambda item: item['name']):
        api.append('- ' + item['name'] + ': ' + compact({key: value for key, value in item.items() if key != 'name'}))
    api += ['', '## Generic templates', '']
    for item in sorted(schema.get('generic_templates', []), key=lambda item: item['name']):
        api.append('- ' + item['name'] + ' [' + item['kind'] + ']: contract=' + compact(item['contract']) + '; shape=' + compact(item['shape']))
    api.append('')
    return {'reference.md': '\n'.join(overview).encode(), 'api.md': '\n'.join(api).encode(),
            'features.json': encoded(features), 'schema.json': encoded(report)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='directory containing reference.md, api.md, and evidence')
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument('--entry', type=Path, help='use checked project exports instead of default standard modules')
    selection.add_argument('--module', action='append', help='standard module to import (repeatable; defaults to a small common set)')
    parser.add_argument('--check', action='store_true', help='verify existing artifacts and recheck compiler/source freshness; write nothing')
    args = parser.parse_args()
    compiler, output = args.compiler.resolve(), args.output.resolve()
    try:
        if args.check:
            if args.entry or args.module:
                raise ValueError('--check uses the stored selection; omit --entry and --module')
            manifest = json.loads((output / 'manifest.json').read_text())
            if manifest.get('version') != 'agent-reference-v1' or set(manifest['artifacts']) != set(FILES):
                raise ValueError('invalid reference manifest')
            if identity_of(compiler)[0] != manifest['compiler_sha256']:
                raise ValueError('stale reference: compiler identity changed')
            for name, expected in manifest['artifacts'].items():
                if file_digest(output / name) != expected:
                    raise ValueError('reference artifact changed: ' + name)
            selected = manifest['selection']
        else:
            selected = {'entry': str(args.entry.resolve()) if args.entry else None,
                        'modules': sorted(set(args.module or DEFAULT_MODULES)) if not args.entry else []}
        if not isinstance(selected, dict) or set(selected) != {'entry', 'modules'}:
            raise ValueError('invalid reference selection')
        if selected['entry'] is not None and (not isinstance(selected['entry'], str) or not Path(selected['entry']).is_absolute()):
            raise ValueError('project entry must be an absolute path')
        if not isinstance(selected['modules'], list) or any(not isinstance(name, str) or not re.fullmatch(r'[a-z][a-z0-9_]*', name) for name in selected['modules']):
            raise ValueError('modules must be standard module names such as math')
        identity, features, report = collect(compiler, selected)
        artifacts = render(identity, features, report, selected)
        if args.check:
            if any(sha(data) != manifest['artifacts'][name] for name, data in artifacts.items()):
                raise ValueError('stale reference: compiler reports, project sources, or reference rendering changed; regenerate')
        else:
            output.mkdir(parents=True, exist_ok=True)
            for name, data in artifacts.items():
                store(output / name, data)
            store(output / 'manifest.json', encoded({'version': 'agent-reference-v1', 'compiler_sha256': identity,
                  'selection': selected, 'artifacts': {name: sha(data) for name, data in artifacts.items()}}))
        print(('Reference fresh' if args.check else 'Reference written') + ': ' + str(output / 'reference.md'))
        print('API: ' + str(output / 'api.md'))
        print('Compiler SHA256: ' + identity)
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print('reference: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
