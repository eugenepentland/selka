#!/usr/bin/env python3
"""Check the CLI diagnostic protocol independently of the Zig renderer."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def records(text):
    values = [json.loads(line) for line in text.splitlines()]
    assert all(value['version'] == 'diagnostic-v1' for value in values), values
    return values


def invoke(compiler, command, path, *options, status=0):
    result = subprocess.run([compiler, command, str(path), '--diagnostics=json', *options], capture_output=True, text=True, timeout=30)
    assert result.returncode == status, (command, result)
    return result.stdout, records(result.stderr)


def problem(messages, code):
    found = [item['diagnostic'] for item in messages if item['kind'] == 'diagnostic' and item['diagnostic']['code'] == code]
    assert len(found) == 1, (code, messages)
    return found[0]


def single_files(compiler, root):
    path = root / 'quoted"é.my'
    path.write_text('fn main()->i64{let unused=1;return 7;}')
    stdout, messages = invoke(compiler, 'run', path)
    assert stdout == '7\n'
    warning = problem(messages, 'W_UNUSED_BINDING')
    assert warning['severity'] == 'warning' and warning['location']['path'] == str(path)
    text = subprocess.run([compiler, 'run', str(path)], capture_output=True, text=True, timeout=30)
    explicit = subprocess.run([compiler, 'run', str(path), '--diagnostics=text'], capture_output=True, text=True, timeout=30)
    assert (text.returncode, text.stdout, text.stderr) == (explicit.returncode, explicit.stdout, explicit.stderr)
    assert text.stdout == stdout and 'warning[W_UNUSED_BINDING]' in text.stderr
    path.write_text('fn main()->i64{return absent;}')
    for command in ('check', 'run', 'dump-bytecode', 'report-quality', 'discover-duplicates'):
        stdout, messages = invoke(compiler, command, path, status=1)
        assert stdout == ''
        data = problem(messages, 'E_UNKNOWN_NAME')
        span = data['location']['bytes']
        assert path.read_bytes()[span['start']:span['end']] == b'absent'
    path.write_text('fn main(')
    for command in ('check', 'fmt', 'fmt-module'):
        _, messages = invoke(compiler, command, path, status=1)
        assert messages[0]['diagnostic']['code'] == 'E_SYNTAX'
    path.write_text('fn divide(n:i64)->i64{return 7/n;}fn main()->i64{return divide(0);}')
    _, messages = invoke(compiler, 'run', path, status=1)
    trap = problem(messages, 'R_DIVISION_BY_ZERO')
    assert [frame['function'] for frame in trap['stack']['frames']] == ['divide', 'main']
    path.write_text('fn recur(n:i64)->i64{return recur(n+1);}fn main()->i64{return recur(0);}')
    _, messages = invoke(compiler, 'run', path, '--max-frames=20', status=1)
    stack = problem(messages, 'R_FRAME_LIMIT')['stack']
    assert len(stack['frames']) == 16 and stack['omitted'] > 0
    path.write_text('fn main()->i64{return 7;}')
    _, messages = invoke(compiler, 'fmt', path, '--check', status=1)
    assert messages == [{'version': 'diagnostic-v1', 'kind': 'message', 'message': 'formatting differs\n'}]
    _, messages = invoke(compiler, 'check', root / 'missing.my', status=2)
    assert messages[0]['kind'] == 'message' and 'FileNotFound' in messages[0]['message']
    for options in (['--diagnostics=xml'], ['--diagnostics=json', '--diagnostics=text']):
        invalid = subprocess.run([compiler, 'check', str(path), *options], capture_output=True, text=True, timeout=30)
        assert invalid.returncode == 2 and invalid.stdout == '' and invalid.stderr.startswith('usage:')


def export_placement(compiler, root):
    entry = root / 'main.my'
    for declaration in ('fn value()->i64{return 42;}', 'struct Value { n:i64 }'):
        name = 'value' if declaration.startswith('fn') else 'Value'
        late = 'module main;\n' + declaration + '\nexport ' + name + ';\nfn main()->i64{return 42;}'
        entry.write_text(late)
        assert invoke(compiler, 'check-project', entry) == ('', [])
        assert invoke(compiler, 'run-project', entry) == ('42\n', [])
        entry.write_text('module main;export ' + name + ';' + declaration + 'fn main()->i64{return 42;}')
        assert invoke(compiler, 'run-project', entry) == ('42\n', [])
        duplicate = late + '\nexport ' + name + ';'
        entry.write_text(duplicate)
        _, messages = invoke(compiler, 'check-project', entry, status=1)
        error = problem(messages, 'E_DUPLICATE_EXPORT')
        span = error['location']['bytes']
        assert duplicate.encode()[span['start']:span['end']] == name.encode()
        assert span['start'] == duplicate.rindex(name)


def modules(compiler, root):
    entry, helper = root / 'main.my', root / 'helper.my'
    entry.write_text('module main;import helper;fn main()->i64{return helper::work::<bool>(9);}')
    bad = 'module helper;\nexport work;\nresult R{ok:i64,err:i64}\nfn work<T:copy>(input:i64)->i64{\nlet pending=new R.ok(input);\nreturn input;\n}'
    helper.write_text(bad)
    _, messages = invoke(compiler, 'check-project', entry, status=1)
    data = problem(messages, 'E_RESULT_UNHANDLED')
    assert data['location']['path'] == 'helper.my'
    assert [note['role'] for note in data['notes']] == ['related']
    span = data['notes'][0]['location']['bytes']
    assert bad.encode()[span['start']:span['end']] == b'pending'
    helper.write_text(bad.replace('let pending=new R.ok(input);\n', ''))
    assert invoke(compiler, 'run-project', entry) == ('9\n', [])
    entry.write_text('module main;import missing;fn main()->i64{return 0;}')
    _, messages = invoke(compiler, 'check-project', entry, status=1)
    assert messages[0]['kind'] == 'diagnostic' and messages[0]['diagnostic']['code'].startswith('E_')
    entry.write_text('module main;import helper;fn main()->i64{return 0;}')
    helper.write_text('module helper;import main;')
    _, messages = invoke(compiler, 'list-modules', entry, status=1)
    cycle = messages[0]['diagnostic']
    assert cycle['notes'] and cycle['location']['path'] != cycle['notes'][0]['location']['path']
    entry.write_text('module main;fn main()->i64{return 1/0;}')
    for command in ('run-project', 'eval-project'):
        _, messages = invoke(compiler, command, entry, status=1)
        assert problem(messages, 'R_DIVISION_BY_ZERO')['location']['path'] == 'main.my'
    request, messages = invoke(compiler, 'eval-project', entry, '--evaluation-request')
    assert json.loads(request)['evaluation'] == 'not-executed' and messages == []
    entry.write_text('module main;fn main(c:clock_cap)->i64{_ = c;return 7;}')
    _, messages = invoke(compiler, 'eval-project', entry, '--evaluation-request', status=1)
    problem(messages, 'E_EVAL_INPUT')
    entry.write_text('module main;fn main()->i64{let unused=1;return 7;}')
    result = subprocess.run([compiler, 'check-session', str(entry), '--diagnostics=json'], input='check\ncheck\nclear\ncheck\nquit\n', capture_output=True, text=True, timeout=30)
    assert result.returncode == 0
    replies = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(replies) == 5 and all(reply['status'] == 0 for reply in replies)
    assert replies[1]['semantic']['hits'] == 1 and replies[3]['semantic']['stored'] == 2
    warnings = records(result.stderr)
    assert len(warnings) == 3 and warnings[0] == warnings[1] == warnings[2]
    problem(warnings[:1], 'W_UNUSED_BINDING')
    manifest = root / 'bad.json'
    manifest.write_text('{}')
    _, messages = invoke(compiler, 'schema-project', entry, '--inputs=' + str(manifest), status=2)
    assert messages[0]['kind'] == 'message' and 'manifest' in messages[0]['message']
    for command, option in (('input-module', None), ('check-value-project', '--value='), ('invoke-project', '--request=')):
        _, messages = invoke(compiler, command, manifest if option is None else entry, *([] if option is None else [option + str(manifest)]), status=2 if option is None else 1)
        assert messages and all(item['kind'] == 'message' for item in messages if item.get('diagnostic', {}).get('severity') != 'warning')
    entry.write_text('module main;export missing;fn main()->i64{return 0;}')
    _, messages = invoke(compiler, 'list-interfaces', entry, status=1)
    assert messages[0]['kind'] == 'diagnostic' and messages[0]['diagnostic']['location']['path'] == 'main.my'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-diagnostic-output-') as directory:
        root = Path(directory)
        single_files(compiler, root)
        export_placement(compiler, root)
        modules(compiler, root)
    print('JSON diagnostics: source errors, warnings, module notes, VM traces, auxiliary failures, text compatibility and cached session replay passed')


if __name__ == '__main__':
    main()
