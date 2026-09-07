"""Coordinator source/runtime identity; does not certify transport access or loaded code."""
from pathlib import Path
import hashlib
import os
import stat
import sys
import sysconfig
from .environment_receipt import tree_identity
from .storage import digest

ROOT = Path(__file__).resolve().parent


def source_inventory(root):
    root = Path(root).resolve(strict=True)
    paths = sorted(root.glob('*.py'))
    if not paths or len(paths) > 1000:
        raise ValueError('invalid coordinator source inventory')
    if any(path.is_symlink() or not path.is_file() for path in paths):
        raise ValueError('coordinator modules must be regular files')
    files = {path.name: tree_identity(path) for path in paths}
    if sorted(root.glob('*.py')) != paths:
        raise ValueError('coordinator source inventory changed during capture')
    return {'root': str(root), 'files': files}


def capture(transport_identity, *, source_root=ROOT):
    return _capture(transport_identity, source_root=source_root, version='application-coordinator-v2')


def _capture(transport_identity, *, source_root, version):
    if not isinstance(transport_identity, str) or not transport_identity.strip():
        raise ValueError('explicit transport identity required')
    # Top-level modules include the gateway, transport worker, namespace setup and
    # grading implementation. V2 also captures recovery policy; task data has
    # separate cohort receipts.
    body = {'version': version,
            'source': source_inventory(source_root),
            'python': {'executable': tree_identity(sys.executable),
                       'stdlib': tree_identity(sysconfig.get_path('stdlib')),
                       'version': sys.version, 'implementation': sys.implementation.name,
                       'cache_tag': sys.implementation.cache_tag},
            'transport_identity': transport_identity,
            'scope': 'on-disk top-level coordinator modules and Python runtime',
            'loaded_code_attested': False}
    if version == 'application-coordinator-v2':
        path = Path(source_root) / 'recovery-policy.md'
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise ValueError('recovery policy must be a regular file')
            data = stream.read(256 * 1024 + 1)
        if len(data) > 256 * 1024:
            raise ValueError('recovery policy exceeds byte limit')
        body['recovery_policy'] = {'content': data.decode('utf-8'), 'sha256': hashlib.sha256(data).hexdigest()}
        body['scope'] += ' and recovery policy'
    return dict(body, sha256=digest(body))


def validate(receipt, *, transport_identity):
    fields = {'version', 'source', 'python', 'transport_identity', 'scope', 'loaded_code_attested', 'sha256'}
    if isinstance(receipt, dict) and receipt.get('version') == 'application-coordinator-v2':
        fields.add('recovery_policy')
    if not isinstance(receipt, dict) or set(receipt) != fields:
        raise ValueError('invalid coordinator receipt fields')
    body = {key: value for key, value in receipt.items() if key != 'sha256'}
    if receipt['version'] not in ('application-coordinator-v1', 'application-coordinator-v2') or digest(body) != receipt['sha256']:
        raise ValueError('coordinator receipt changed')
    if receipt['transport_identity'] != transport_identity:
        raise ValueError('coordinator transport identity mismatch')
    if receipt['loaded_code_attested'] is not False:
        raise ValueError('receipt cannot attest loaded coordinator code')
    if receipt['version'] == 'application-coordinator-v2':
        policy = receipt['recovery_policy']
        if (not isinstance(policy, dict) or set(policy) != {'content', 'sha256'} or
                not isinstance(policy['content'], str) or len(policy['content'].encode()) > 256 * 1024 or
                hashlib.sha256(policy['content'].encode()).hexdigest() != policy['sha256']):
            raise ValueError('invalid frozen recovery policy')


def verify(receipt, *, transport_identity, source_root=ROOT):
    validate(receipt, transport_identity=transport_identity)
    if receipt['source']['root'] != str(Path(source_root).resolve(strict=True)):
        raise ValueError('coordinator source root mismatch')
    current = _capture(transport_identity, source_root=source_root, version=receipt['version'])
    if current['sha256'] != receipt['sha256']:
        raise ValueError('coordinator source, recovery policy or Python runtime changed')
    return current
