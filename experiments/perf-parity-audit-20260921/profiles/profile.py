#!/usr/bin/env python3
"""Self-PC profiles of the retained SVG and s-expression benchmark binaries.

Adapted from the sampling half of experiments/svg-gap-audit-20260921/audit.py.
Hardware counters are unavailable on this host (perf_event_paranoid=4), so the
only instrument is the repository's LD_PRELOAD SIGPROF sampler,
experiments/svg-slowdown-20260921/sample.c: a process-CPU interval timer whose
handler records the interrupted instruction pointer relative to the main
executable's load base.  A sample taken inside a shared library (libc.so,
ld.so) is counted but not located; it is reported as `outside_main_executable`.
The kernel evaluates POSIX CPU timers on the tick, so with CONFIG_HZ=1000 the
effective period is 1 ms however short an interval the sampler requests.
"""
import argparse
import bisect
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import random
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/perf-audit-20260921/profiles'
BENCH = ROOT / '.tmp/full-svg-benchmark-20260921'
SEXPR_INPUT = ROOT / '.tmp/runtime-audit-20260919/input8.sexp'
SAMPLERS = {'repo': ROOT / 'experiments/svg-slowdown-20260921/sample.c',
            'dense': OUT / 'sample_dense.c'}
CPU = 6
SEED = 20260921
DOCS = ('lib/modules/straps-synth-lmx2595.sexp', 'lib/pinouts/lmx2595rhar.sexp',
        'lib/interfaces/spi.sexp')
# experiments/svg-gap-fixes-20260921/qualification.json, case "fixture".
SVG_SHA256 = '68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388'

TARGETS = {
    'svg-o3-lto': {
        'binary': '.tmp/svg-gap-fixes-20260921/gc-lto', 'kind': 'svg',
        'note': 'guest GC policy, LLVM -O3 + LTO, emitted with --drop-step-checks '
                '--drop-frame-checks (no step accounting); the "gc-lto" arm of '
                'experiments/svg-gap-fixes-20260921, fixture project'},
    'sexpr-o3-lto-census': {
        'binary': '.tmp/perf-audit-20260921/sexpr-o3-lto', 'kind': 'sexpr', 'args': (),
        'note': 'LLVM -O3 + LTO, --keep-symbols; census of input8.sexp'},
    'sexpr-o3-lto-render': {
        'binary': '.tmp/perf-audit-20260921/sexpr-o3-lto', 'kind': 'sexpr', 'args': ('--render',),
        'note': 'LLVM -O3 + LTO, --keep-symbols; parse and reprint input8.sexp'},
    'sexpr-qbe-census': {
        'binary': '.tmp/perf-audit-20260921/sexpr-qbe', 'kind': 'sexpr', 'args': (),
        'note': 'production QBE backend; census of input8.sexp'},
    'sexpr-qbe-render': {
        'binary': '.tmp/perf-audit-20260921/sexpr-qbe', 'kind': 'sexpr', 'args': ('--render',),
        'note': 'production QBE backend; parse and reprint input8.sexp'},
}

# C function definitions start in column zero in these sources; a line that ends
# in a semicolon is a declaration, not a definition.
DEFINITION = re.compile(
    r'^(?:static\s+|inline\s+)*[A-Za-z_][A-Za-z0-9_]*[\w\s\*]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*\(')
ZIG_DEFINITION = re.compile(r'^\s*(?:pub\s+|export\s+|inline\s+)*fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(')
LOCAL_SUFFIX = re.compile(r'\.\d+$')
STARTUP = {'_start', '_dl_relocate_static_pie', 'atexit', 'entry_run', '_init', '_fini',
           '__libc_csu_init', '__libc_csu_fini'}
# The QBE backend statically links Zig's compiler-rt, so these land in the
# executable; in an LLVM build the same calls go to libc.so and are `outside`.
LIBC = {'memcpy', 'memmove', 'memset', 'memcmp', 'bcmp', 'strlen', 'strcmp', 'sqrt',
        'malloc', 'free', 'realloc', 'calloc', 'qsort', 'abort'}
# `literal` is a one-line static in native_print.c that the definition regex
# skips; addr2line on the QBE build (which keeps debug info) confirms the file.
EXTRA_SOURCES = {'literal': ('runtime-c', 'native_print.c')}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def clean_environment():
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_') or key in (
                'LD_PRELOAD', 'GOGC', 'GOMEMLIMIT', 'GODEBUG', 'GOMAXPROCS',
                'NETLISP_LIB_DIR', 'NETLISP_STDLIB_DIR'):
            del env[key]
    return env


def invoke(name, env_extra=None):
    """Run one target once, pinned to CPU 6, and verify the output it produced."""
    target = TARGETS[name]
    binary = ROOT / target['binary']
    env = clean_environment()
    command = ['taskset', '-c', str(CPU), str(binary)]
    if target['kind'] == 'svg':
        env['MYLANG_MEMORY_LIMIT'] = '268435456'
        output, issue = WORK / f'{name}.svg', WORK / f'{name}.issue'
        output.write_bytes(b''); issue.write_bytes(b'')
        declared = Path(str(binary) + '.declared')
        env.update(MYLANG_SCHEMATIC_DECLARED=declared.read_text(),
                   MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(BENCH / 'projects/fixture' / path)
                    for i, path in enumerate(DOCS)})
        command += ['--print-result']
    else:
        command += [str(SEXPR_INPUT), *target['args']]
    env.update(env_extra or {})
    if 'LD_PRELOAD' in env:
        # Preload the target, not taskset: an inherited CPU timer can fire after
        # exec resets signal handlers and before the target's constructor runs.
        assignments = [f'{key}={env.pop(key)}'
                       for key in ('LD_PRELOAD', 'MYLANG_AUDIT_SAMPLES') if key in env]
        command[3:3] = ['/usr/bin/env', *assignments]
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=120)
    assert result.returncode == 0 and not result.stderr, (name, result.returncode, result.stderr[:400])
    if target['kind'] == 'svg':
        assert result.stdout == b'0\n', (name, result.stdout)
        assert not issue.read_bytes(), (name, issue.read_bytes()[:200])
        digest = sha(output)
        assert digest == SVG_SHA256, (name, digest)
        return digest
    return hashlib.md5(result.stdout).hexdigest()


def provider_symbols(binary):
    """Names the host provider object defines, which outrank same-named runtime statics."""
    names = set()
    for candidate in sorted(binary.parent.glob('*schematic*.o')):
        for line in subprocess.check_output(
                ['nm', '-S', '--defined-only', str(candidate)], text=True).splitlines():
            fields = line.split()
            if len(fields) == 4 and fields[2] in ('t', 'T'):
                names.add(fields[3])
    return names


def source_symbols(binary):
    """Map each runtime C/Zig function name to the file that defines it.

    The runtime sources the build published sit beside the build cache, so the
    map is the one that build used.  `nm` cannot read the LTO builds' archives
    (LLVM bitcode) and the QBE backend's archive is one amalgamated runtime.o,
    so the definition sites come from the sources instead.
    """
    mapping = dict(EXTRA_SOURCES)
    for directory in sorted(path for path in binary.parent.glob('*cache*/runtime/*')
                            if (path / 'qbe_runtime.c').is_file()):
        for source in sorted(directory.glob('*.c')):
            for line in source.read_text().splitlines():
                match = DEFINITION.match(line)
                if match and not line.rstrip().endswith(';'):
                    mapping.setdefault(match.group(1), ('runtime-c', source.name))
        for source in sorted(directory.glob('*.zig')):
            for line in source.read_text().splitlines():
                match = ZIG_DEFINITION.match(line)
                if match:
                    mapping.setdefault(match.group(1), ('runtime-c', source.name))
    return mapping


def classify(symbol, friendly, sources, providers):
    """Sort one text symbol into guest / runtime C / libc / host provider / startup."""
    if symbol in friendly:
        return 'guest', friendly[symbol]
    if symbol.startswith('myl_f_'):
        return 'guest', symbol + ' (absent from the manifest)'
    if symbol.startswith('myl_r_'):
        return 'runtime-c', symbol[:14] + '.. (generated aggregate renderer)'
    if symbol in providers:
        return 'host-provider', f'{symbol} [native_schematic.c]'
    plain = LOCAL_SUFFIX.sub('', symbol)
    if plain in LIBC or plain.startswith('compiler_rt.'):
        return 'libc', symbol
    if symbol in sources:
        kind, source = sources[symbol]
        return kind, f'{symbol} [{source}]'
    if plain in sources:
        # A linker-renamed duplicate: two translation units defined the name.
        kind, source = sources[plain]
        return kind, f'{symbol} [{source}?]'
    if plain in providers:
        return 'host-provider', f'{symbol} [native_schematic.c?]'
    if symbol.startswith(('myl_native_', 'myl_qbe_', 'qbe_', 'mylang_')):
        return 'runtime-c', symbol
    if plain in STARTUP:
        return 'startup', symbol
    return 'unclassified', symbol


def symbol_table(binary):
    symbols = []
    for line in subprocess.check_output(
            ['nm', '-n', '-S', '--defined-only', str(binary)], text=True).splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[2] in ('t', 'T'):
            symbols.append((int(fields[0], 16), int(fields[1], 16), fields[3]))
    return symbols


def disassemble(binary, start, address, window=4, after=3):
    """Instructions around one hot address, with the sampled one marked.

    Disassembly starts at the containing symbol so the instruction boundaries are
    the real ones; starting mid-instruction desynchronises x86 decoding.
    """
    text = subprocess.check_output(
        ['objdump', '-d', '--no-show-raw-insn', f'--start-address=0x{start:x}',
         f'--stop-address=0x{address + 32:x}', str(binary)], text=True)
    lines = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if ':' not in stripped:
            continue
        head, rest = stripped.split(':', 1)
        try:
            value = int(head, 16)
        except ValueError:
            continue
        lines.append({'address': hex(value), 'text': rest.strip(), 'sampled': value == address})
    hot = next((i for i, line in enumerate(lines) if line['sampled']), len(lines) - 1)
    window_lines = lines[max(0, hot - window):hot + after + 1]
    while window_lines and window_lines[-1]['text'].startswith('.byte'):
        window_lines.pop()  # the stop address cut the last instruction in half
    return window_lines


def aggregate(name, expected_runs, label=''):
    target = TARGETS[name]
    binary = ROOT / target['binary']
    manifest = json.loads(Path(str(binary) + '.qbe-manifest.json').read_text())
    friendly = {f['symbol']: f['name'] for f in manifest['functions']}
    sources, providers = source_symbols(binary), provider_symbols(binary)
    symbols = symbol_table(binary)
    addresses = [item[0] for item in symbols]

    def locate(pc):
        index = bisect.bisect_right(addresses, pc) - 1
        if index < 0 or pc >= symbols[index][0] + symbols[index][1]:
            return None
        return symbols[index]

    totals, classes, pcs = Counter(), Counter(), Counter()
    function_class = {}
    outside = overflow = runs = samples = unmapped = 0
    for line in (WORK / f'samples-{name}{label}.txt').read_text().splitlines():
        fields = line.split()
        if fields[0] == 'run':
            runs += 1
            samples += int(fields[3]); outside += int(fields[5]); overflow += int(fields[7])
            continue
        pc, hits = int(fields[0], 16), int(fields[1])
        pcs[pc] += hits
        found = locate(pc)
        if found is None:
            unmapped += hits
            continue
        kind, label = classify(found[2], friendly, sources, providers)
        totals[label] += hits
        classes[kind] += hits
        function_class[label] = kind
    assert overflow == 0 and samples > 0 and runs == expected_runs, (name, runs, samples, overflow)
    top_pcs = []
    for pc, hits in pcs.most_common(15):
        found = locate(pc)
        kind, label = classify(found[2], friendly, sources, providers) if found else ('unmapped', '?')
        top_pcs.append({'address': hex(pc), 'samples': hits,
                        'percent_all_samples': hits * 100 / samples, 'function': label,
                        'class': kind,
                        'offset_in_function': hex(pc - found[0]) if found else None,
                        'function_bytes': found[1] if found else None})
    for entry in top_pcs[:5]:
        address = int(entry['address'], 16)
        found = locate(address)
        entry['disassembly'] = disassemble(binary, found[0], address)
    return {'binary': target['binary'], 'binary_sha256': sha(binary),
            'note': target.get('note', ''), 'argv_tail': list(target.get('args', ())),
            'runs': runs, 'samples': samples,
            'outside_main_executable': outside,
            'percent_outside_main_executable': outside * 100 / samples,
            'unmapped_inside': unmapped,
            'percent_unmapped_inside': unmapped * 100 / samples,
            'located_samples': samples - outside - unmapped,
            'class_totals': {kind: {'samples': hits, 'percent_all_samples': hits * 100 / samples}
                             for kind, hits in classes.most_common()},
            'functions': [{'name': function, 'class': function_class[function],
                           'samples': hits, 'percent_all_samples': hits * 100 / samples}
                          for function, hits in totals.most_common()],
            'top_pcs': top_pcs}


METHOD = ('LD_PRELOAD SIGPROF (ITIMER_PROF) userspace self-PC sampling of unmodified '
          'binaries; 500us requested, kernel tick (CONFIG_HZ=1000) limited; no stack '
          'attribution, no hardware counters (perf_event_paranoid=4). The `dense` '
          'sampler is the repository sampler with the first expiration moved inside the '
          'first tick, so no prefix of a short run goes unsampled. A sample inside a '
          'shared library counts in `samples` and is reported only as '
          '`outside_main_executable`, so libc memcpy/malloc in the LLVM builds is inside '
          'that share. LTO inlines many guest functions into their callers, so a sample '
          'is attributed to the surviving outer symbol. Every run is pinned to CPU 6 and '
          'its output hash is verified; no wall-time claim is made from profiled runs.')


def report(name, count, sampler, label=''):
    """Write one target's JSON from the raw samples already collected."""
    summary = aggregate(name, count, label)
    summary.update(method=METHOD, sampler=sampler,
                   sampler_source=str(SAMPLERS[sampler].relative_to(ROOT)),
                   sampler_source_sha256=sha(SAMPLERS[sampler]),
                   sampler_sha256=sha(WORK / f'sample-{sampler}.so'), cpu=CPU, seed=SEED)
    (OUT / f'{name}{label}.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(name + label, summary['samples'], 'samples,',
          f"{summary['percent_outside_main_executable']:.1f}% outside", flush=True)
    return summary


def run(count, names, sampler, label=''):
    WORK.mkdir(parents=True, exist_ok=True)
    library = WORK / f'sample-{sampler}.so'
    subprocess.run(['cc', '-shared', '-fPIC', '-O2', str(SAMPLERS[sampler]),
                    '-o', str(library), '-ldl'], check=True)
    digests = {}
    for name in names:
        (WORK / f'samples-{name}{label}.txt').write_text('')
        digests[name] = invoke(name)
    rng = random.Random(SEED)
    order = list(names)
    for number in range(count):
        rng.shuffle(order)
        for name in order:
            actual = invoke(name, env_extra={
                'LD_PRELOAD': str(library),
                'MYLANG_AUDIT_SAMPLES': str(WORK / f'samples-{name}{label}.txt')})
            assert actual == digests[name], (name, actual, digests[name])
        if (number + 1) % 250 == 0:
            print(f'{number + 1} profiled runs per target', flush=True)
    for name in names:
        assert invoke(name) == digests[name], name
    for name in names:
        summary = report(name, count, sampler, label)
        summary.update(output_digest=digests[name], interleaved_with=list(names))
        (OUT / f'{name}{label}.json').write_text(json.dumps(summary, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--count', type=int, default=400)
    parser.add_argument('--target', action='append', choices=list(TARGETS))
    parser.add_argument('--sampler', choices=list(SAMPLERS), default='dense')
    parser.add_argument('--label', default='', help='suffix for the raw samples and the JSON')
    parser.add_argument('--aggregate', action='store_true',
                        help='re-read the raw samples already under .tmp and rewrite the JSON')
    options = parser.parse_args()
    chosen = options.target or list(TARGETS)
    if options.aggregate:
        for target in chosen:
            existing = json.loads((OUT / f'{target}{options.label}.json').read_text())
            summary = report(target, existing['runs'],
                             existing.get('sampler', options.sampler), options.label)
            for key in ('output_digest', 'interleaved_with'):
                if key in existing:
                    summary[key] = existing[key]
            (OUT / f'{target}{options.label}.json').write_text(json.dumps(summary, indent=2) + '\n')
    else:
        run(options.count, chosen, options.sampler, options.label)
