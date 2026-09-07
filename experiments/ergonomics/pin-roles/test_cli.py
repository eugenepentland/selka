#!/usr/bin/env python3
"""Independent CLI cases. Python supplies fixtures/assertions only."""
import json
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
EXE = HERE.parents[2] / 'zig-out' / 'bin' / 'mylang-io'


def invoke(value, timeout=60):
    raw = value if isinstance(value, bytes) else json.dumps(value, separators=(',', ':')).encode()
    run = subprocess.run([str(EXE), '--project', str(HERE)], input=raw, capture_output=True, timeout=timeout)
    assert run.returncode == 0, run.stderr.decode(errors='replace')
    return json.loads(run.stdout)


def board(**kw):
    b = dict(version=1, unit='um', width=100, height=100, clearance=0, components=[], nets=[])
    b.update(kw)
    return b


def component(id, x=0, y=0, width=10, height=10, pins=None):
    return dict(id=id, x=x, y=y, width=width, height=height, pins=pins or [])


def result(b):
    return invoke({'cases': [b]})['results'][0]


def tests():
    assert invoke({'cases': []}) == {'results': []}
    empty = result(board())
    assert empty == {'unit': 'um', 'findings': [], 'nets': [], 'svg': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="0" y="0" width="100" height="100" fill="white" stroke="black"/></svg>'}
    invalid = [b'', b'null', b'{}', b'{"cases":[],"x":0}', b'{"cases":[],"cases":[]}',
               b'{"cases":[{"x":9223372036854775808}]}', b'{"cases":[{"x":-9223372036854775809}]}',
               b'{"cases":[{"x":1e309}]}', b'{"cases":[{"x":NaN}]}', b'{"cases":["\xff"]}',
               b'{"cases":[1.79769313486231589e308]}',
               b'{"cases":["\xc0\xaf"]}', b'{"cases":["\\ud800"]}', b'{"cases":["\\udc00"]}',
               b'{"cases":[{"x":0,"\\u0078":1}]}', b'{"cases":[01]}', b'{"cases":[1.]}', b'{"cases":[1e]}',
               b'{"cases":['+b'['*63+b'0'+b']'*63+b']}', b' '*1048577]
    for raw in invalid:
        assert invoke(raw) == {'error': 'invalid-request'}, raw[:80]
    for raw in [b'{"cases":[-9223372036854775808]}', b'{"cases":[9223372036854775807]}',
                b'{"cases":[1e308]}', b'{"cases":[0e999999]}', b'{"cases":[1e-999999]}',
                b'{"cases":[1.7976931348623158e308]}',
                b'{"cases":["\\ud83d\\ude00"]}', b'{"cases":["\xf0\x9f\x98\x80"]}',
                b'{"cases":['+b'['*62+b'0'+b']'*62+b']}']:
        assert invoke(raw) == {'results': [{'error': 'invalid-board'}]}, raw[:80]
    for b in [board(version=True), board(width=1.0), board(components=[component('A')]),
              board(components=[component('a', pins=['p','p'])]), board(extra=1)]:
        assert result(b) == {'error': 'invalid-board'}
    assert result(board(components=[component('z'),component('z'),component('a'),component('a')], nets=[{'id':'n','members':[]},{'id':'n','members':[]}])) == {'error':'duplicate-id','components':['a','z'],'nets':['n']}
    refs=[{'component':'z','pin':'x'},{'component':'a','pin':'missing'},{'component':'z','pin':'x'}]
    assert result(board(components=[component('a',pins=['p'])],nets=[{'id':'n','members':refs}])) == {'error':'unknown-pin','refs':[{'component':'a','pin':'missing'},{'component':'z','pin':'x'}]}
    refs=[{'component':'a','pin':'p'}]*3
    assert result(board(components=[component('a',pins=['p'])],nets=[{'id':'n','members':refs}])) == {'error':'reused-pin','refs':[{'component':'a','pin':'p'}]}
    touching=board(components=[component('b',x=10),component('a')])
    assert result(touching)['findings'] == []
    overlap=board(components=[component('b',x=9),component('a')])
    assert result(overlap)['findings'] == [{'code':'clearance','subjects':['a','b']}]
    equal=board(clearance=5,components=[component('a'),component('b',x=13,y=14)])
    assert result(equal)['findings'] == []
    equal['clearance']=6
    assert result(equal)['findings'] == [{'code':'clearance','subjects':['a','b']}]
    b=board(unit='mm',components=[component('z',x=99,width=2,pins=['q']),component('a',x=-1,width=1,pins=['p'])],nets=[{'id':'n','members':[{'component':'z','pin':'q'},{'component':'a','pin':'p'}]}])
    r=result(b)
    assert r['findings']==[{'code':'outside-board','subjects':['a']},{'code':'outside-board','subjects':['z']}]
    assert r['nets']==[{'id':'n','members':[{'component':'a','pin':'p'},{'component':'z','pin':'q'}],'span':100500}]
    assert r['svg']=='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100000 100000"><rect x="0" y="0" width="100000" height="100000" fill="white" stroke="black"/><rect id="a" x="-1000" y="0" width="1000" height="10000" fill="none" stroke="black"/><rect id="z" x="99000" y="0" width="2000" height="10000" fill="none" stroke="black"/></svg>'
    half=board(components=[component('a',width=1,pins=['p']),component('b',x=10,width=2,pins=['p'])],nets=[{'id':'n','members':[{'component':'a','pin':'p'},{'component':'b','pin':'p'}]}])
    assert result(half)['nets'][0]['span']==11
    b=board(components=[component('b',pins=['z','a']),component('a',x=-2)],nets=[{'id':'z','members':[]},{'id':'a','members':[]}])
    assert result(b)['findings']==[{'code':'clearance','subjects':['a','b']},{'code':'outside-board','subjects':['a']},{'code':'unconnected-pin','subjects':['b','a']},{'code':'unconnected-pin','subjects':['b','z']},{'code':'underconnected-net','subjects':['a']},{'code':'underconnected-net','subjects':['z']}]
    encoded = json.dumps({'cases': [board(components=[component('abc', pins=['p'])])]}).replace('abc', '\\u0061bc').replace('components', '\\u0063omponents')
    assert invoke(encoded.encode())['results'][0]['findings'] == [{'code': 'unconnected-pin', 'subjects': ['abc', 'p']}]
    threshold = 2**1024 - 2**970
    for delta in [-1, 0, 1]:
        raw = ('{"cases":[' + str(threshold + delta) + '.0]}').encode()
        expected = {'results': [{'error': 'invalid-board'}]} if delta < 0 else {'error': 'invalid-request'}
        assert invoke(raw) == expected
    print('independent CLI cases passed')


def stress():
    fixtures = [
        ('one-MiB whitespace', b'{"cases":[]}' + b' ' * (1048576 - 12), {'results': []}),
        ('50000 unique keys', ('{"cases":[{' + ','.join('"k' + str(i) + '":0' for i in range(50000)) + '}]}').encode(), {'results': [{'error': 'invalid-board'}]}),
        ('long duplicate keys', b'{"cases":[],"' + b'a' * 100000 + b'":0,"' + b'a' * 100000 + b'":1}', {'error': 'invalid-request'}),
    ]
    for name, raw, expected in fixtures:
        start = time.monotonic()
        assert invoke(raw, timeout=240) == expected
        print(name, len(raw), 'input bytes', round(time.monotonic() - start, 3), 'seconds', flush=True)
    repeated = board(components=[component('a', pins=['p'])], nets=[{'id': 'n' + str(i), 'members': [{'component': 'a', 'pin': 'p'}] * 128} for i in range(128)])
    assert result(repeated) == {'error': 'reused-pin', 'refs': [{'component': 'a', 'pin': 'p'}]}
    large = board(components=[component('c' + str(i).zfill(31), pins=['a', 'b', 'c', 'd']) for i in range(128)])
    raw = json.dumps({'cases': [large] * 64}, separators=(',', ':')).encode()
    assert len(raw) <= 1048576
    start = time.monotonic()
    run = subprocess.run([str(EXE), '--project', str(HERE)], input=raw, capture_output=True, timeout=240)
    assert run.returncode == 0, run.stderr.decode(errors='replace')
    assert len(run.stdout) >= 55 * 1024 * 1024, len(run.stdout)
    decoded = json.loads(run.stdout)
    assert len(decoded['results']) == 64
    for entry in decoded['results']:
        assert len(entry['findings']) == 8640
        assert entry['findings'][0] == {'code': 'clearance', 'subjects': ['c' + '0' * 31, 'c' + '0' * 30 + '1']}
        assert entry['findings'][-1] == {'code': 'unconnected-pin', 'subjects': ['c' + '0' * 28 + '127', 'd']}
        assert entry['nets'] == []
    print('output stress:', len(raw), 'input bytes,', len(run.stdout), 'output bytes,', round(time.monotonic() - start, 3), 'seconds', flush=True)


if __name__ == '__main__':
    tests()
    if '--stress' in sys.argv:
        stress()
