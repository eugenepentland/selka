from pathlib import Path
import hashlib, json, os, re, subprocess, sys
root = Path(__file__).resolve().parents[4]
evidence = Path(__file__).resolve().parent
out = root / '.tmp/memory-closeout/coordinator/native-platform'
out.mkdir(parents=True, exist_ok=True)
config = (root / 'src/config_core_tool_platform.zig').read_text()
rows = re.findall(r'\.path = "([^"]+)",\s*\.resolved = "([^"]+)",\s*\.sha256 = "([^"]+)"', config)
report = {'before_config_sha256': hashlib.sha256(config.encode()).hexdigest(), 'files': [], 'commands': []}
for name, resolved, expected in rows:
    p = Path(name)
    report['files'].append({'path': name, 'resolved': str(p.resolve()), 'expected_resolved': resolved, 'expected_sha256': expected, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'size': p.stat().st_size, 'mtime_ns': p.stat().st_mtime_ns})
report['preload'] = {'exists': Path('/etc/ld.so.preload').exists()}
def run(argv, env=None):
    result = subprocess.run(argv, cwd=root, env=env, text=True, capture_output=True)
    report['commands'].append({'argv': list(map(str, argv)), 'status': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    return result
run(['ldconfig', '-p'])
for name, _, _ in rows:
    if name != '/etc/ld.so.cache': run(['readelf', '-d', name])
for mode, opt in [('debug', '-O0'), ('release', '-O3')]:
    binary = out / mode
    result = run([os.environ['ZIG'], 'cc', '-target', 'x86_64-linux-gnu.2.31', '-march=native', opt, str(evidence / 'probe.c'), '-pthread', '-lm', '-o', str(binary)])
    if result.returncode: continue
    run(['readelf', '-d', str(binary)])
    run(['/lib64/ld-linux-x86-64.so.2', '--list', str(binary)])
    env = {k:v for k,v in os.environ.items() if not k.startswith('LD_')}
    env['LD_DEBUG'] = 'libs,files'
    run([str(binary), '0.5'], env)
    report[mode+'_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
(evidence / 'qualification.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({'files':report['files'], 'statuses':[c['status'] for c in report['commands']]}))
if any(c['status'] for c in report['commands']): sys.exit(1)
