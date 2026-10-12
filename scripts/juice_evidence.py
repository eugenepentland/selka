#!/usr/bin/env python3
"""Bounded immutable native Juice measurements; comparisons remain native authority.

This cache certifies complete retained capture evidence, not fresh host state.
The coordinator binds source/tool/provider inputs and keeps its live input guard
through admission, measurement and publication. No threshold belongs to this API.
"""
from dataclasses import dataclass
import hashlib
import json
import verification_code_identity as code_identity
import math
import os
from pathlib import Path
import re
import shutil
import stat
import statistics
import sys
import tempfile
from types import MappingProxyType
from typing import Callable, Mapping

from fuzz_campaign_store import Store, InputsChanged, BLOB_MAX_BYTES
from juice_tool import collectors as collector_module, common as common_module
from juice_tool.collectors import parse_grind
from juice_tool.common import JuiceError

_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
PARSER_CODE_SHA256 = hashlib.sha256((collector_module.LOADED_CODE_SHA256 + ':'
                                     + common_module.LOADED_CODE_SHA256).encode()).hexdigest()
RECORD_MAX_BYTES = 16 * 1024 * 1024
FILE_MAX_BYTES = 64 * 1024 * 1024
EXECUTABLE_MAX_BYTES = 256 * 1024 * 1024
TOTAL_MAX_BYTES = 1024 * 1024 * 1024
MAX_FILES = 1000
_SHA = re.compile(r'[0-9a-f]{64}')
_NAME = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,254}')
_REQUIRED = {'workload', 'repeats', 'collector', 'profile'}
_OPTIONAL = {'contract', 'sources', 'build_config', 'context', 'tool_id', 'source_root'}
_METRICS = {'instructions', 'cycles', 'reference_cycles', 'data_reads', 'data_writes', 'atomics'}


class EvidenceError(ValueError):
    """A capture is incomplete, malformed, corrupt or outside the evidence bound."""


def _require(condition, message):
    if not condition:
        raise EvidenceError(message)


def _sha(value):
    _require(type(value) is str and _SHA.fullmatch(value) is not None,
             'expected lowercase SHA-256 identity')
    return value


def _name(value):
    _require(type(value) is str and _NAME.fullmatch(value) is not None
             and value not in ('.', '..'), 'unsafe evidence filename')
    return value


def _unique(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, 'duplicate JSON field')
        result[key] = value
    return result


def _json_tree(value, depth=0):
    _require(depth <= 64, 'JSON nesting exceeds bound')
    if type(value) is dict:
        _require(all(type(key) is str for key in value), 'invalid JSON object')
        for child in value.values():
            _json_tree(child, depth + 1)
    elif type(value) is list:
        for child in value:
            _json_tree(child, depth + 1)
    else:
        _require(value is None or type(value) in (str, bool, int)
                 or type(value) is float and math.isfinite(value), 'invalid JSON value')


def _decode(data):
    _require(type(data) is bytes and len(data) <= RECORD_MAX_BYTES, 'record size bound')
    try:
        value = json.loads(data, object_pairs_hook=_unique,
                           parse_constant=lambda _: (_ for _ in ()).throw(EvidenceError('nonfinite JSON')))
        _json_tree(value)
        _require(type(value) is dict, 'record must be an object')
        return value
    except (ValueError, TypeError, UnicodeError, RecursionError) as error:
        raise EvidenceError('invalid record JSON') from error


def _encode(value):
    _json_tree(value)
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def _bounded_read(path, maximum=FILE_MAX_BYTES):
    """Read a regular file using directory descriptors; never follow any symlink."""
    descriptor = None
    parent = None
    try:
        parts = Path(path).absolute().parts
        parent = os.open(parts[0], os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        for part in parts[1:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
                            dir_fd=parent)
            os.close(parent)
            parent = child
        descriptor = os.open(parts[-1], os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK | os.O_NOFOLLOW,
                             dir_fd=parent)
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > maximum:
            return None
        with os.fdopen(descriptor, 'rb') as stream:
            descriptor = None
            data = stream.read(maximum + 1)
        return data if len(data) <= maximum else None
    except OSError:
        return None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if parent is not None:
            os.close(parent)


def _mapping(value, maximum=MAX_FILES, allow_empty=True):
    _require(type(value) is dict and len(value) <= maximum and (allow_empty or value),
             'invalid bounded digest map')
    for digest in value.values():
        _sha(digest)
    return value


def _expected(value):
    _require(type(value) is dict and _REQUIRED <= value.keys()
             and value.keys() <= _REQUIRED | _OPTIONAL, 'unknown or missing expected contract field')
    _require(type(value['repeats']) is int and 2 <= value['repeats'] <= 30, 'repeats require 2..30')
    _require(value['profile'] in ('work', 'runtime'), 'unknown profile')
    _require(type(value['workload']) is dict and type(value['collector']) is dict,
             'invalid workload or collector contract')
    _name(value['workload'].get('name'))
    return _decode(_encode(value))


def _number(value, positive=False, count=False):
    _require(type(value) in (int, float) and math.isfinite(value)
             and (value > 0 if positive else value >= 0), 'invalid metric')
    if count:
        _require(value <= 2**53 and int(value) == value, 'inexact or excessive count')
    return value


def _metrics(value, positive_instructions=True):
    _require(type(value) is dict and 'instructions' in value
             and value.keys() <= _METRICS, 'invalid measured metric set')
    for key, count in value.items():
        _number(count, positive=key in ('cycles', 'reference_cycles') or key == 'instructions' and positive_instructions, count=True)
    return value


def _perf(data, collector):
    events = {'instructions': collector['event']}
    if collector.get('profile', 'work') == 'runtime':
        events.update(cycles=collector['event'].replace('instructions', 'cycles'),
                      reference_cycles=collector['event'].replace('instructions', 'ref-cycles'))
    result = {}
    for metric, event in events.items():
        matches = []
        for line in data.decode('utf-8').splitlines():
            fields = line.split(';')
            if len(fields) < 3 or fields[2].strip() != event:
                continue
            _require(len(fields) >= 5 and re.fullmatch(r'\d+', fields[0].strip()) is not None,
                     'incomplete perf count')
            count = int(fields[0].strip())
            _number(count, positive=True, count=True)
            _number(float(fields[3].strip()), positive=True)
            _require(float(fields[4].strip()) == 100, 'partial perf count')
            matches.append(count)
        _require(len(matches) == 1, 'missing or repeated perf event')
        result[metric] = matches[0]
    return result


def _summary(cell, samples):
    metrics = samples[0]['metrics']
    _require(type(cell['metrics']) is dict and cell['metrics'].keys() == metrics.keys(),
             'summary metric mismatch')
    for key in metrics:
        values = [sample['metrics'][key] for sample in samples]
        median = statistics.median(values)
        expected = {'samples': values, 'median': median, 'min': min(values), 'max': max(values),
                    'spread': (max(values) - min(values)) / median if median else 0}
        summary = cell['metrics'][key]
        _require(type(summary) is dict and summary.keys() == expected.keys(), 'invalid summary shape')
        _require(type(summary['samples']) is list, 'invalid summary samples')
        for value in summary['samples']:
            _number(value, count=True)
        for field in ('median', 'min', 'max', 'spread'):
            _number(summary[field], count=field in ('min', 'max'))
        _require(summary == expected, 'inconsistent summary')
    median = cell['metrics']['instructions']['median']
    chosen = min(samples, key=lambda sample: abs(sample['metrics']['instructions'] - median))
    for kind in ('functions', 'lines'):
        _require(cell[kind] == chosen[kind], 'attribution does not match chosen sample')


def _document(record, files, artifacts, expected, read):
    """Validate native capture certificates and reconcile retained raw counters."""
    original_read = read
    executable_only = set(artifacts.values()) - set(files.values())
    def read(digest):
        data = original_read(digest)
        maximum = EXECUTABLE_MAX_BYTES if digest in executable_only else FILE_MAX_BYTES
        _require(type(data) is bytes and len(data) <= maximum
                 and hashlib.sha256(data).hexdigest() == digest, 'missing or corrupt artifact')
        return data
    _require(record.get('version') == 'juice-v1' and record.get('identity_scheme') == 'mylang-juice-native-v1'
             and record.get('status') == 'complete' and 'error' not in record, 'not a complete native record')
    _sha(record['tool_id'])
    _name(record['name'])
    _require(type(record['source_root']) is str and Path(record['source_root']).is_absolute(),
             'invalid source root')
    _mapping(record['sources'], allow_empty=False)
    work = expected['workload']
    name = work['name']
    _require(record['contract']['name'] == record['manifest']['name']
             and record['contract']['environment'] == record['manifest']['environment'],
             'manifest and workload execution contract disagree')
    _mapping(record['contract']['inputs'])
    _require(record['contract']['workloads'] == [work]
             and type(record['workloads']) is dict and set(record['workloads']) == {name},
             'selected workload contract mismatch')
    _require(record['collector'] == expected['collector'] == record['context']['collector'],
             'collector identity mismatch')
    _require(record['collector'].get('profile', 'work') == expected['profile'], 'profile mismatch')
    collector = record['collector']
    _require(collector['kind'] in ('perf', 'callgrind', 'cachegrind'), 'unknown collector')
    _require(type(collector['event']) is str and collector['event'], 'missing collector event')
    if expected['profile'] == 'runtime':
        _require(collector['kind'] == 'perf' and type(collector.get('event_group')) is str,
                 'runtime profile requires grouped perf')
    for field in ('system', 'kernel', 'machine', 'execution_path'):
        _require(type(record['context'][field]) is str and record['context'][field], 'incomplete machine context')
    _require(type(record['context']['cpu']) is dict and record['context']['cpu'], 'incomplete CPU context')
    if expected['profile'] == 'runtime':
        _require(type(record['context']['scheduling_policy']) is dict, 'missing runtime scheduling context')
    _mapping(record['context']['libraries'])
    _require(all(Path(path).is_absolute() for path in record['context']['libraries']),
             'library identities must be absolute')
    for field in _OPTIONAL & expected.keys():
        _require(record[field] == expected[field], 'expected ' + field + ' mismatch')
    _require(record['build_config']['spec'] == record['manifest']['build'], 'build spec mismatch')
    adapter = record['manifest']['adapter']
    _require(adapter in ('native', 'mylang'), 'unknown build adapter')
    _sha(record['build']['key'])
    kinds = {'plain', 'counted'} if adapter == 'mylang' else {'plain'}
    _require(set(artifacts) == kinds and record['build']['artifacts'] == artifacts,
             'build artifact set or digest mismatch')
    _mapping(artifacts, maximum=2, allow_empty=False)
    _mapping(files, allow_empty=False)
    _require(record['evidence'] == files, 'raw evidence manifest mismatch')
    _require(len({path.casefold() for path in files}) == len(files), 'ambiguous raw filenames')
    for path in files:
        _name(path)
        _require(path.casefold() != 'record.json', 'record overlaps raw evidence')
    # Read each bounded object once for its checksum; parsing below rereads only
    # per-trial objects. The aggregate bound prevents giant manifest amplification.
    total = len(_encode(record))
    for digest in list(files.values()) + list(artifacts.values()):
        data = read(digest)
        # read() has already checked the exact returned bytes.
        total += len(data)
        del data
        _require(total <= TOTAL_MAX_BYTES, 'aggregate evidence size bound')
    cell = record['workloads'][name]
    _require(cell['units'] == work['units'] and cell['unit'] == work['unit'], 'work units mismatch')
    _number(cell['units'], positive=True)
    samples = cell['samples']
    _require(type(samples) is list and len(samples) == expected['repeats'], 'incomplete sample set')
    correctness = cell['correctness']
    _sha(correctness['stdout'])
    _sha(correctness['stderr'])
    _mapping(correctness['files'])
    _require(set(correctness['files']) == set(work['outputs']), 'incomplete correctness output map')
    _require(work.get('expected_stdout') is not None or work.get('stdout_sha256') is not None
             or work['check'], 'missing correctness oracle')
    if work.get('expected_stdout') is not None:
        _require(correctness['stdout'] == hashlib.sha256(work['expected_stdout'].encode()).hexdigest(),
                 'incorrect normalized stdout')
    if work.get('stdout_sha256') is not None:
        _require(correctness['stdout'] == _sha(work['stdout_sha256']), 'incorrect normalized stdout digest')
    expected_stderr = work['expected_stderr'].encode()
    _require(correctness['stderr'] == hashlib.sha256(expected_stderr).hexdigest(), 'incorrect stderr digest')
    # Native normalization and external check commands are capture certificates:
    # do not substitute Python regex semantics or rerun an oracle during lookup.
    normalization = work.get('stdout_regex')
    if normalization is not None:
        _require(type(normalization) is str and 0 < len(normalization.encode()) <= 4096,
                 'invalid native normalization contract')
    required = set()
    ordinary = int(collector['kind'] != 'perf')
    for index in range(ordinary + len(samples) + int(adapter == 'mylang')):
        kind = 'native' if index < ordinary else 'sample' if index < ordinary + len(samples) else 'counted'
        prefix = f'{name}-{index}-{kind}'
        out_name, err_name = prefix + '.stdout', prefix + '.stderr'
        required.update((out_name, err_name))
        _require(out_name in files and err_name in files, 'missing trial output')
        stdout, stderr = read(files[out_name]), read(files[err_name])
        _require(stdout is not None and stderr == expected_stderr, 'missing or incorrect trial output')
        if normalization is None:
            _require(hashlib.sha256(stdout).hexdigest() == correctness['stdout'], 'repeated stdout disagreement')
        del stdout, stderr
        if work['check']:
            required.update((prefix + '-oracle.stdout', prefix + '-oracle.stderr'))
        if kind != 'sample':
            continue
        sample = samples[index - ordinary]
        _require(type(sample) is dict and type(sample['exit_code']) is int and sample['exit_code'] == 0,
                 'unsuccessful measured trial')
        _number(sample['wall_seconds'])
        _require(sample['stdout_sha256'] == files[out_name] and sample['stderr_sha256'] == files[err_name],
                 'sample output digest mismatch')
        measured = _metrics(sample['metrics'])
        _require(measured.keys() == samples[0]['metrics'].keys(), 'inconsistent sample metric sets')
        for attribution in ('functions', 'lines'):
            _require(type(sample[attribution]) is list, 'missing sample attribution')
            for row in sample[attribution]:
                _require(type(row) is dict and all(type(row[field]) is str for field in ('file', 'function', 'object')),
                         'invalid attribution identity')
                for metric in row.keys() & _METRICS:
                    _number(row[metric], count=True)
        if collector['kind'] == 'perf':
            raw = prefix + '.perf'
            required.add(raw)
            _require(raw in files and _perf(read(files[raw]), collector) == measured, 'raw perf count mismatch')
        else:
            pattern = re.compile(re.escape(prefix) + r'\.collector\.\d+')
            profiles = [path for path in files if pattern.fullmatch(path)]
            _require(profiles, 'missing Valgrind profile')
            aggregate = {}
            for path in profiles:
                parsed = parse_grind(read(files[path]).decode('utf-8'))
                required.add(path)
                for metric, value in _metrics(parsed['metrics'], positive_instructions=False).items():
                    aggregate[metric] = aggregate.get(metric, 0) + value
                del parsed
            logs = [path for path in files if re.fullmatch(re.escape(prefix) + r'\.collector\.log\.\d+', path)]
            required.update(logs)
            _require(aggregate == measured, 'raw Valgrind count mismatch')
    if adapter == 'mylang':
        raw = name + '-counters.json'
        required.add(raw)
        _require(raw in files, 'missing semantic counter evidence')
        semantic = _decode(read(files[raw]))
        _require(semantic.get('version') == 'mylang-counters-v1' and type(semantic.get('totals')) is dict,
                 'invalid semantic counter document')
        project = str(Path(record['context']['execution_path']).parent / 'project') + '/'
        for site in semantic.get('sites', []):
            if type(site.get('path')) is str:
                site['path'] = site['path'].replace(project, '')
        _require(cell['semantic'] == semantic
                 and cell['counter_semantics'] == record['manifest']['build']['counter_semantics'],
                 'semantic counter mismatch')
    _require(required == files.keys(), 'raw evidence is incomplete or contains unexpected files')
    _summary(cell, samples)


@dataclass(frozen=True)
class Evidence:
    """Exact original record bytes and immutable digest maps for a measurement."""
    record_bytes: bytes
    record_digest: str
    files: Mapping[str, str]
    build_artifacts: Mapping[str, str]
    expected: Mapping
    _read: Callable[[str], bytes | None]

    @property
    def record(self):
        return _decode(self.record_bytes)

    @property
    def recorded_libraries(self):
        """Exact native library map; caller validates current provider files."""
        return dict(self.record['context']['libraries'])

    def read_file(self, name):
        return self._checked(self.files[name])

    def read_artifact(self, kind):
        return self._checked(self.build_artifacts[kind])

    def _checked(self, digest):
        data = self._read(digest)
        _require(data is not None and hashlib.sha256(data).hexdigest() == digest,
                 'retained artifact changed or disappeared')
        return data


def _evidence(record_bytes, files, artifacts, expected, read):
    expected = _expected(expected)
    record = _decode(record_bytes)
    try:
        _document(record, files, artifacts, expected, read)
    except (KeyError, TypeError, ValueError, UnicodeError, JuiceError, OverflowError, RecursionError) as error:
        raise EvidenceError('invalid native evidence: ' + str(error)) from error
    return Evidence(record_bytes, hashlib.sha256(record_bytes).hexdigest(),
                    MappingProxyType(dict(files)), MappingProxyType(dict(artifacts)),
                    MappingProxyType(expected), read)


def _artifact_paths(record_path):
    """Locate emitted binaries using native cache/records/name/record.json layout."""
    path = Path(record_path)
    record = _decode(_bounded_read(path, RECORD_MAX_BYTES))
    _require(path.name == 'record.json' and path.parent.parent.name == 'records',
             'artifact_paths requires the original native cache layout')
    _sha(record['build']['key'])
    _require(set(record['build']['artifacts']) <= {'plain', 'counted'}, 'unknown build artifact')
    return {kind: path.parent.parent.parent / 'builds' / record['build']['key'] / kind
            for kind in record['build']['artifacts']}


def _validate_record(record_path, build_artifacts, expected):
    """Validate an immutable capture directly, without requiring an action alias."""
    path = Path(record_path)
    _require(path.name == 'record.json', 'native record filename must be record.json')
    data = _bounded_read(path, RECORD_MAX_BYTES)
    record = _decode(data)
    files = _mapping(record['evidence'], allow_empty=False)
    artifacts = _mapping(record['build']['artifacts'], maximum=2, allow_empty=False)
    _require(type(build_artifacts) is dict and build_artifacts.keys() == artifacts.keys(),
             'supply every exact native build artifact')
    artifact_locations = [Path(os.path.abspath(location)) for location in build_artifacts.values()]
    _require(len(set(artifact_locations)) == len(artifact_locations)
             and all(Path(os.path.abspath(path.parent)) not in location.parents for location in artifact_locations),
             'executable paths overlap raw evidence or one another')
    paths = {}
    for name, digest in files.items():
        _name(name)
        paths[digest] = path.parent / name
    for kind, digest in artifacts.items():
        _require(kind in ('plain', 'counted'), 'unknown executable kind')
        paths[digest] = Path(build_artifacts[kind])
    # Direct inventory is bounded and exact; omitted files cannot silently become
    # a complete evidence set, and non-regular entries are rejected rather than read.
    names = set()
    with os.scandir(path.parent) as entries:
        for entry in entries:
            _require(len(names) <= MAX_FILES and entry.is_file(follow_symlinks=False),
                     'unexpected or excessive raw directory entries')
            names.add(entry.name)
    _require(names == set(files) | {'record.json'}, 'incomplete raw directory inventory')
    # Equal digests can occur at multiple filenames. Verify every original path
    # before grouping by digest; one intact duplicate must not hide a corrupt file.
    for name, digest in files.items():
        value = _bounded_read(path.parent / name, FILE_MAX_BYTES)
        _require(value is not None and hashlib.sha256(value).hexdigest() == digest,
                 'missing or corrupt raw file')
        del value
    for kind, digest in artifacts.items():
        value = _bounded_read(build_artifacts[kind], EXECUTABLE_MAX_BYTES)
        _require(value is not None and hashlib.sha256(value).hexdigest() == digest,
                 'missing or corrupt executable')
        del value
    executable_only = set(artifacts.values()) - set(files.values())
    def read(digest):
        maximum = EXECUTABLE_MAX_BYTES if digest in executable_only else FILE_MAX_BYTES
        return _bounded_read(paths[digest], maximum)
    return _evidence(data, files, artifacts, expected, read)


def artifact_paths(record_path):
    """Locate binaries from a bounded original native cache record."""
    try:
        return _artifact_paths(record_path)
    except (KeyError, TypeError, ValueError, OverflowError, RecursionError) as error:
        raise EvidenceError('invalid native build layout: ' + str(error)) from error


def validate_record(record_path, build_artifacts, expected):
    """Validate a capture directly; malformed or incomplete evidence raises EvidenceError."""
    try:
        return _validate_record(record_path, build_artifacts, expected)
    except (KeyError, TypeError, ValueError, OverflowError, RecursionError) as error:
        raise EvidenceError('invalid native evidence: ' + str(error)) from error


def reusable_artifacts(evidence):
    """Whether validated executables fit the unchanged shared-store blob ceiling.

    Larger fresh compiler captures remain readable; their executable evidence
    cannot be published into the existing smaller bounded reuse store.
    """
    return all(len(evidence.read_artifact(kind)) <= BLOB_MAX_BYTES for kind in evidence.build_artifacts)


class EvidenceStore:
    """Exact-action measurement aliases over the existing bounded blob store."""
    def __init__(self, root):
        self.backend = Store(Path(root))

    def lease(self):
        """Protect all lazy evidence reads/materialization from local shared GC."""
        return self.backend.lease()

    def _lock(self, key, domain):
        _sha(key)
        identity = hashlib.sha256((domain + ':' + key).encode()).hexdigest()
        return self.backend.coordinator_lock(identity)

    def coordinator_lock(self, key):
        """Serialize a workload outside shared server admission."""
        return self._lock(key, 'juice-coordinator-v1')

    def lookup(self, key, expected):
        """Return complete exact evidence; malformed, foreign or missing is a miss."""
        _sha(key)
        expected = _expected(expected)
        try:
            result = self.backend.load_success(key)
            if type(result) is not dict or set(result) != {'version', 'record', 'files', 'artifacts', 'expected'}:
                return None
            if result['version'] != 'juice-evidence-v1' or result['expected'] != expected:
                return None
            data = self.backend.read_blob(_sha(result['record']))
            return _evidence(data, result['files'], result['artifacts'], expected, self.backend.read_blob)
        except (EvidenceError, KeyError, TypeError, OSError, UnicodeError, RecursionError):
            return None

    def publish(self, key, record_path, build_artifacts, expected, validate):
        """Retain the first valid capture; caller guards inputs before and after."""
        _sha(key)
        if not validate():
            raise InputsChanged('inputs changed before validating measurement')
        evidence = validate_record(record_path, build_artifacts, expected)
        if not reusable_artifacts(evidence):
            if not validate():
                raise InputsChanged('inputs changed while checking fresh-only executable bounds')
            return False
        with self._lock(key, 'juice-publication-v1'):
            existing = self.lookup(key, expected)
            if existing is not None:
                if not validate():
                    raise InputsChanged('inputs changed while checking retained measurement')
                return True
            saved = self.backend.load_success(key)
            if type(saved) is dict and type(saved.get('expected')) is dict:
                try:
                    foreign = self.lookup(key, saved['expected'])
                except EvidenceError:
                    foreign = None
                if foreign is not None:
                    if not validate():
                        raise InputsChanged('inputs changed while checking foreign first writer')
                    return False
            # A malformed alias cannot block a sound replacement. All facade
            # writers/discards share this lock; backend also serializes atomic I/O.
            self.backend.discard_success(key)
            refs = [self.backend.put_blob(evidence.record_bytes)]
            for name, digest in evidence.files.items():
                _require(self.backend.put_blob(evidence.read_file(name)) == digest, 'raw digest changed')
                refs.append(digest)
            for kind, digest in evidence.build_artifacts.items():
                _require(self.backend.put_blob(evidence.read_artifact(kind)) == digest, 'executable digest changed')
                refs.append(digest)
            result = {'version': 'juice-evidence-v1', 'record': evidence.record_digest,
                      'files': dict(evidence.files), 'artifacts': dict(evidence.build_artifacts),
                      'expected': dict(evidence.expected)}
            return self.backend.publish_success(key, result, list(dict.fromkeys(refs)), validate)

    def discard(self, key):
        """Forget one exact action; immutable blobs remain available for other records."""
        with self._lock(key, 'juice-publication-v1'):
            self.backend.discard_success(key)

    @staticmethod
    def materialize(evidence, destination):
        """Atomically create a new record/raw directory and exact executable copies."""
        destination = Path(destination)
        _require(not destination.exists() and not destination.is_symlink(), 'destination already exists')
        # Revalidate before writing, including evidence objects supplied by callers.
        evidence = _evidence(evidence.record_bytes, dict(evidence.files), dict(evidence.build_artifacts),
                             dict(evidence.expected), evidence._read)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = Path(tempfile.mkdtemp(prefix='.juice-evidence-', dir=destination.parent))
        try:
            (temporary / 'record').mkdir()
            (temporary / 'build').mkdir()
            (temporary / 'record' / 'record.json').write_bytes(evidence.record_bytes)
            for name in evidence.files:
                (temporary / 'record' / name).write_bytes(evidence.read_file(name))
            for kind in evidence.build_artifacts:
                binary = temporary / 'build' / kind
                binary.write_bytes(evidence.read_artifact(kind))
                binary.chmod(0o755)
            _require(not destination.exists() and not destination.is_symlink(), 'destination appeared during materialization')
            os.rename(temporary, destination)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)
        return destination / 'record' / 'record.json'


def materialize(evidence, destination):
    """Materialize validated evidence without requiring a cache/action alias."""
    return EvidenceStore.materialize(evidence, destination)
