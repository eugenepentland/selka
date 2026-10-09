"""Immutable, bounded source and typed-call snapshots for isolated workers."""
from dataclasses import dataclass
import hashlib
import json
from pathlib import PurePosixPath


@dataclass(frozen=True)
class Identity:
    compiler_sha256: str
    source_sha256: str
    request_sha256: str
    schema_sha256: str


def canonical(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()


def schema_identity(output):
    """Use the same canonical schema identity as the typed-call-v1 bindings."""
    return hashlib.sha256(canonical(json.loads(output))).hexdigest()


def sources_snapshot(sources, entry, limit):
    if not sources or len(sources) > 128:
        raise ValueError('a snapshot requires 1..128 source files')
    copied, total = {}, 0
    for name, source in sorted(sources.items()):
        path = PurePosixPath(name)
        if (not isinstance(name, str) or path.is_absolute() or '..' in path.parts or
                str(path) != name or '\\' in name or '\0' in name or not name.endswith('.selka')):
            raise ValueError('source paths must be canonical relative .selka paths')
        data = bytes(source)
        total += len(data) + len(name.encode())
        if total > limit:
            raise ValueError('source snapshot exceeds its byte limit')
        copied[name] = data
    if entry not in copied:
        raise ValueError('entry must belong to the source snapshot')
    manifest = {'version': 'worker-source-v1', 'entry': entry,
                'files': [[name, hashlib.sha256(data).hexdigest()] for name, data in copied.items()]}
    return copied, hashlib.sha256(canonical(manifest)).hexdigest()


def request_snapshot(request, limit):
    data = bytes(request)
    if len(data) > limit:
        raise ValueError('request exceeds its byte limit')

    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate request key')
            result[key] = value
        return result

    value = json.loads(data, object_pairs_hook=unique)
    if not isinstance(value, dict) or value.get('version') != 'typed-call-v1':
        raise ValueError('request must use typed-call-v1')
    schema = value.get('schema_sha256', '')
    if not isinstance(schema, str) or len(schema) != 64 or any(c not in '0123456789abcdef' for c in schema):
        raise ValueError('request must pin a lowercase SHA-256 schema identity')
    if not isinstance(value.get('function'), str) or not isinstance(value.get('arguments'), dict):
        raise ValueError('request requires a function and named arguments')
    return data, schema
