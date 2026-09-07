"""Independent, unscored contract tests. Python is only the test process driver."""
import json
import os
import subprocess
import unittest
from pathlib import Path
def byte_io_host(project):
    """Resolve an explicit host, the isolated tool, or the nearest built checkout."""
    override = os.environ.get('MYLANG_IO')
    if override is not None:
        candidate = Path(override).expanduser().resolve()
        if not override.strip() or not candidate.is_file() or not os.access(candidate, os.X_OK):
            raise RuntimeError(f'MYLANG_IO must name an executable file: {override!r}')
        return candidate
    for candidate in (Path('/tools/byte_io'), *(parent / 'zig-out/bin/mylang-io'
                                               for parent in (project, *project.parents))):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    raise RuntimeError('Cannot find mylang-io; set MYLANG_IO to an executable file, '
                       'provide /tools/byte_io, or build the enclosing checkout.')

ROOT=Path(__file__).resolve().parent
HOST=byte_io_host(ROOT)
def call(value, raw=False):
    data=value if raw else json.dumps(value).encode()
    p=subprocess.run([str(HOST),'--project',str(ROOT)], input=data,capture_output=True,timeout=60)
    assert p.returncode==0, p.stderr.decode()
    return json.loads(p.stdout)
def job(id,duration=1,needs=()):return dict(id=id,duration=duration,needs=list(needs))
def manifest(jobs):return dict(version=1,jobs=jobs)
def run(jobs):return call(dict(cases=[manifest(jobs)]))['results'][0]
class Contract(unittest.TestCase):
    def test_example(self):
        self.assertEqual(run([job('z',5),job('b',2),job('a',3,['b'])]),dict(order=['b','a','z'],layers=[['b','z'],['a']],timings=[dict(id='a',start=2,finish=5),dict(id='b',start=0,finish=2),dict(id='z',start=0,finish=5)],makespan=5))
    def test_empty(self):self.assertEqual(run([]),dict(order=[],layers=[],timings=[],makespan=0))
    def test_priority(self):
        self.assertEqual(run([job('a',needs=['missing','missing']),job('a')]),dict(error='duplicate-id',ids=['a']))
        self.assertEqual(run([job('z',needs=['missing','missing']),job('a',needs=['x','x'])]),dict(error='duplicate-dependency',jobs=['a','z']))
        self.assertEqual(run([job('z',needs=['z','x','a'])]),dict(error='unknown-dependency',ids=['a','x']))
    def test_cycle(self):self.assertEqual(run([job('a',needs=['b']),job('b',needs=['a']),job('c',needs=['b']),job('d')]),dict(error='cycle',blocked=['a','b','c']))
    def test_schema(self):
        for x in [None,True,1,[],{},dict(version=1,jobs=[job('A')]),dict(version=1.0,jobs=[]),dict(version=True,jobs=[]),dict(version=1,jobs=[job('a',True)]),dict(version=1,jobs=[job('a',1000001)]),dict(version=1,jobs=[job('a')],extra=1)]:
            with self.subTest(x=x):self.assertEqual(call(dict(cases=[x])),dict(results=[dict(error='invalid-manifest')]))
    def test_invalid(self):
        for x in [b'',b'{}',b'{"cases":[],"cases":[]}',b'{"cases":[],"\\u0063ases":[]}',b'{"cases":[9223372036854775808]}',b'{"cases":[-9223372036854775809]}',b'{"cases":[1e999]}',b'{"cases":[NaN]}',b'{"cases":["\xff"]}',b'{"cases":["\\ud800"]}',b'{"cases":["\\udc00"]}',b'{"cases":[]} trailing',b'{"cases":[01]}',b'{"cases":["\\x00"]}',b'{"cases":["\xc0\xaf"]}',b'{"cases":["\xed\xa0\x80"]}',b'{"cases":[]}'+b' '*1048576]:
            with self.subTest(x=x[:70]):self.assertEqual(call(x,True),dict(error='invalid-request'))
    def test_depth(self):
        self.assertEqual(call(b'{"cases":['+b'['*62+b'0'+b']'*62+b']}',True),dict(results=[dict(error='invalid-manifest')]))
        self.assertEqual(call(b'{"cases":['+b'['*63+b'0'+b']'*63+b']}',True),dict(error='invalid-request'))
    def test_numbers(self):
        for s in ['-9223372036854775808','9223372036854775807','1.7976931348623158e308','1e-9999','0e9999']:
            self.assertEqual(call(('{"cases":['+s+']}').encode(),True),dict(results=[dict(error='invalid-manifest')]))
        self.assertEqual(call(b'{"cases":[1.7976931348623159e308]}',True),dict(error='invalid-request'))
        self.assertEqual(call(b'{"cases":[{"version":1,"jobs":[{"id":"a","duration":-0,"needs":[]}]}]}',True)['results'][0]['makespan'],0)
    def test_escaped(self):
        self.assertEqual(call(b'{"cases":[{"version":1,"jobs":[{"id":"\\u0061","duration":0,"needs":[]}]}]}',True),call(dict(cases=[manifest([job('a',0)])])))
    def test_standard_transport_boundaries(self):
        # General transport must validate values before manifest schema rejection.
        valid = [b'"\\ud83d\\ude00"', '"é"'.encode(), b'1e-9999', b'0e9999',
                 b'-9223372036854775808', b'1.7976931348623158e308']
        for value in valid:
            with self.subTest(value=value):
                self.assertEqual(call(b'{"cases":[' + value + b']}', True),
                                 {'results': [{'error': 'invalid-manifest'}]})
        for value in [b'{"x":0,"\\u0078":1}', b'"\\ud800"', b'"\\udc00"',
                      b'9223372036854775808', b'1.7976931348623159e308']:
            with self.subTest(value=value):
                self.assertEqual(call(b'{"cases":[false,' + value + b']}', True),
                                 {'error': 'invalid-request'})
        prefix = b'{"cases":[]}'
        self.assertEqual(call(prefix + b' ' * (1048576-len(prefix)), True),
                         {'results': []})
    def test_source_order_permutations(self):
        import itertools
        jobs = [job('z',5), job('b',2), job('a',3,['b']), job('c',0,['a','z'])]
        expected = run(jobs)
        for order in itertools.permutations(jobs):
            self.assertEqual(run(list(order)), expected)
    def test_limits(self):
        self.assertEqual(len(call(dict(cases=[manifest([])]*64))['results']),64)
        self.assertEqual(call(dict(cases=[manifest([])]*65)),dict(error='invalid-request'))
        jobs=[job('j'+str(i).zfill(3),1000000,[] if i==0 else ['j'+str(i-1).zfill(3)]) for i in range(128)]
        result=run(jobs[::-1]);self.assertEqual(result['makespan'],128000000);self.assertEqual(len(result['layers']),128)
        self.assertEqual(run(jobs+[job('extra')]),dict(error='invalid-manifest'))
if __name__=='__main__':unittest.main()
