"""Adapt private diagram contracts to an exact frozen C3 module prefix.

Prepare after the coordinator supplies the common compiler/source identities.
Execute the generated five commands through shared build admission separately.
"""
from pathlib import Path
import argparse, hashlib, json, re, shutil

HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source-root', type=Path, required=True)
p.add_argument('--common-receipt', type=Path)
p.add_argument('--compiler', type=Path)
p.add_argument('--work', type=Path, required=True)
a = p.parse_args()
def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()
if a.common_receipt:
    common = json.loads(a.common_receipt.read_text())
    assert sha(common['compiler']) == common['compiler_sha256']
    installed = common['installation_files']
    expected = {v['path']: v['sha256'] for v in installed} if isinstance(installed, list) else installed
    assert all(sha(Path(common['installation']) / name) == digest for name, digest in expected.items())
else:
    assert a.compiler, 'provide the anticipated path; execution must await common identity binding'
    common = {'compiler': str(a.compiler.resolve()), 'compiler_sha256': None, 'installation': str(a.compiler.resolve().parents[1])}
    expected = {}
source = a.source_root.resolve()
pins = {str(f.relative_to(source)): sha(f) for f in sorted(source.rglob('*')) if f.is_file() and (f.suffix == '.my' or f.name == 'mylang.json')}
work = a.work.resolve()
assert not work.exists(), 'preserve an existing contract attempt'
private = work / 'eda'
shutil.copytree(source, private)
module = private / 'diagram_membership.my'
prefix = module.read_bytes()
assert sha(source / module.name) == hashlib.sha256(prefix).hexdigest()
fixture = (HERE / 'p3_dm_tests.my').read_text()
fixture = fixture.replace('import diagram_membership as m\n', '').replace('import eval_env as env\n', '')
fixture = fixture.replace('m.compute_sub_block_attachments', 'compute_sub_block_attachments').replace('env.', 'env_mod.')
fixture = fixture.replace('public func test_', 'func test_')
fixture = re.sub(r'\bsub\b', 'p3_contract_sub', fixture)
fixture = fixture.replace('same_attachment_input', 'p3_contract_same_attachment_input')
assert not re.search(r'^public\s', fixture, re.M), 'contract suffix must add no public exports'
module.write_bytes(prefix + b'\n\n# Private P3 contracts; canonical module prefix is byte-identical.\n' + fixture.encode())
assert hashlib.sha256(module.read_bytes()[:len(prefix)]).hexdigest() == pins[module.name]
assert all(sha(source / name) == digest for name, digest in pins.items())
modes = {'verified-release': ['--release', '--verify-facts'], 'release': ['--release'],
         'debug': ['--unoptimized'], 'optimized-debug': ['--optimize-debug'],
         'no-facts': ['--release', '--no-facts']}
commands = {}
for name, flags in modes.items():
    commands[name] = ['scripts/build-slot.sh', 'build', str(common['compiler']), 'test', str(module),
                      '--experimental-zero-rc', *flags, '--force', '--jobs', '4',
                      '--max-steps', '1000000000', '--max-frames', '40000', '--max-memory', '2G',
                      '--timeout-ms', '120000', '--cache-dir', str(work / ('cache-' + name)), '--json']
receipt = {'canonical_source_root': str(source), 'workdir': str(HERE.parents[3]), 'canonical_source_pins': pins,
           'common_receipt': str(a.common_receipt.resolve()) if a.common_receipt else None, 'common_receipt_sha256': sha(a.common_receipt) if a.common_receipt else None,
           'compiler': common['compiler'], 'compiler_sha256': common['compiler_sha256'],
           'installation': common['installation'], 'installation_files': expected,
           'private_module': str(module), 'prefix_bytes': len(prefix), 'prefix_sha256': pins[module.name],
           'adapted_module_sha256': sha(module), 'fixture_sha256': sha(HERE / 'p3_dm_tests.my'),
           'additional_public_exports': 0, 'expected_private_tests': 3, 'commands': commands,
           'environment': {'MYL_CORE_LEAKCHECK': '1', 'MYLANG_JOBS': '4', 'MYLANG_COMPONENT_DIR': str(Path(common['installation']) / 'libexec/mylang/components')},
           'status': 'prepared; no native command executed; bind common compiler/install identities before execution' if not a.common_receipt else 'prepared; no native command executed'}
(work / 'contract-plan.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(work / 'contract-plan.json')
