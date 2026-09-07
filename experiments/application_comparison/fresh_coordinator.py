"""Fresh, isolated-Python entry point; pin coordinator imports to verified source bytes.

Invoke with Python -I -S -B. This is a trusted coordinator entry, never a
participant tool. Scored model launches are disabled.
"""
import hashlib
import importlib.abc
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import types


def digest(value):
    raw = json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()
    return hashlib.sha256(raw).hexdigest()


def sources(receipt):
    root = Path(__file__).resolve().parent
    if receipt['source']['root'] != str(root):
        raise ValueError('fresh coordinator source root mismatch')
    expected = receipt['source']['files']
    if set(expected) != {path.name for path in root.glob('*.py')}:
        raise ValueError('fresh coordinator source inventory mismatch')
    buffers = {}
    for name, identity in expected.items():
        if Path(name).name != name or not name.endswith('.py'):
            raise ValueError('invalid coordinator module name')
        path = root / name
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or before.st_size > 4 * 1024**2:
                raise ValueError('invalid or oversized coordinator module')
            with os.fdopen(fd, 'rb', closefd=False) as stream:
                data = stream.read(4 * 1024**2 + 1)
            after = os.fstat(fd)
            if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                raise ValueError('coordinator module changed during read')
        finally:
            os.close(fd)
        record = {'.': {'kind': 'file', 'mode': stat.S_IMODE(before.st_mode), 'size': len(data),
                        'sha256': hashlib.sha256(data).hexdigest(), 'uid': before.st_uid, 'gid': before.st_gid}}
        if identity != {'path': str(path), 'sha256': digest(record), 'entries': 1, 'bytes': len(data)}:
            raise ValueError('coordinator module bytes differ from receipt')
        buffers[name] = data
    return root, buffers


class VerifiedImports(importlib.abc.MetaPathFinder, importlib.abc.Loader):
    prefix = 'experiments.application_comparison'

    def __init__(self, root, buffers):
        self.root, self.buffers = root, buffers

    def find_spec(self, fullname, path=None, target=None):
        if fullname == self.prefix:
            name, package = '__init__.py', True
        elif fullname.startswith(self.prefix + '.'):
            name, package = fullname[len(self.prefix) + 1:] + '.py', False
        else:
            return None
        if name not in self.buffers:
            raise ImportError('coordinator import is outside verified inventory: ' + fullname)
        spec = importlib.util.spec_from_loader(fullname, self, origin=str(self.root / name), is_package=package)
        spec.loader_state = name
        return spec

    def create_module(self, spec):
        return None

    def exec_module(self, module):
        name = module.__spec__.loader_state
        module.__file__ = str(self.root / name)
        if name == '__init__.py':
            module.__path__ = [str(self.root)]
        exec(compile(self.buffers[name], module.__file__, 'exec'), module.__dict__)


def main():
    if not (sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode):
        raise ValueError('fresh coordinator requires Python -I -S -B')
    request = json.loads(Path(sys.argv[1]).read_text())
    if request.get('operation') not in ('probe', 'fixture', 'calibration', 'grade-fixture', 'grade-calibration'):
        raise ValueError('unsupported coordinator operation')
    api_key = None
    if request['operation'] == 'calibration':
        if len(sys.argv) != 3:
            raise ValueError('calibration requires a private credential descriptor')
        with os.fdopen(int(sys.argv[2]), 'rb') as credential:
            raw = credential.read(4097)
        if not 0 < len(raw) <= 4096:
            raise ValueError('invalid credential length')
        api_key = raw.decode('utf-8')
    receipt = request['coordinator']
    if digest({key: value for key, value in receipt.items() if key != 'sha256'}) != receipt['sha256']:
        raise ValueError('coordinator receipt changed')
    root, buffers = sources(receipt)
    parent = types.ModuleType('experiments')
    parent.__path__ = [str(root.parent)]
    sys.modules['experiments'] = parent
    importer = VerifiedImports(root, buffers)
    importer.receipt_sha256 = receipt['sha256']
    sys.meta_path.insert(0, importer)
    from experiments.application_comparison import coordinator_receipt, scheduled_driver
    coordinator_receipt.verify(receipt, transport_identity=request['transport_identity'])
    result = None
    model_calls = 0
    if request['operation'] in ('fixture', 'calibration', 'grade-fixture', 'grade-calibration'):
        from experiments.application_comparison import cohort
        manifest = cohort.load(request['cohort'])
        if manifest.get('coordinator') is not None and manifest['coordinator'] != receipt:
            raise ValueError('fresh coordinator differs from frozen cohort')
    if request['operation'] == 'calibration':
        from experiments.application_comparison.responses_transport import ResponsesTransport
        if receipt['version'] != 'application-coordinator-v2':
            raise ValueError('calibration requires a frozen recovery policy in coordinator v2')
        if manifest['record_kind'] != 'calibration' or manifest['version'] != 'application-cohort-v5':
            raise ValueError('calibration execution requires a v5 calibration cohort')
        limit = manifest['model_settings'].get('max_reported_tokens_per_phase')
        if type(limit) is not int or limit <= 0:
            raise ValueError('calibration requires a frozen reported-token limit per phase')
        transport = ResponsesTransport(api_key, endpoint=request.get('endpoint', 'https://api.openai.com/v1/responses'))
        if transport.identity != request['transport_identity']:
            raise ValueError('calibration transport differs from frozen identity')
        def complete(body, timeout):
            nonlocal model_calls
            model_calls += 1
            return transport(body, timeout=timeout)
        result = scheduled_driver.run_calibration(request['cohort'], request['envelope'], complete,
                    transport_identity=request['transport_identity'])
    if request['operation'] in ('grade-fixture', 'grade-calibration'):
        from experiments.application_comparison import scheduled_grading
        grader = scheduled_grading.run_fixture if request['operation'] == 'grade-fixture' else scheduled_grading.run_calibration
        result = grader(request['cohort'], request['roots'], request['directory'],
                    transport_identity=request['transport_identity'])
    if request['operation'] == 'fixture':
        responses = request['responses']
        if not isinstance(responses, list) or not 1 <= len(responses) <= 1000:
            raise ValueError('bounded fixture response list required')
        if request['transport_identity'] != 'fixture-replay:' + digest(responses):
            raise ValueError('fixture transport does not match frozen responses')
        iterator = iter(responses)
        def complete(body, timeout):
            try:
                return next(iterator)
            except StopIteration as error:
                raise ValueError('fixture responses exhausted') from error
        result = scheduled_driver.run_fixture(request['cohort'], request['envelope'], complete,
                    transport_identity=request['transport_identity'])
    coordinator_receipt.verify(receipt, transport_identity=request['transport_identity'])
    print(json.dumps({'version': 'fresh-coordinator-result-v1', 'operation': request['operation'],
                      'coordinator_sha256': receipt['sha256'], 'verified_source_modules': len(buffers),
                      'source_imports': 'verified-in-memory-bytes', 'result': result, 'model_calls': model_calls}))


if __name__ == '__main__':
    main()
