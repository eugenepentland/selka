#!/usr/bin/env python3
"""Price runtime visibility with matched non-LTO/LTO toolchain recipes."""
import json
from pathlib import Path
import re
from build_probes import ROOT, WORK, run, sha


def main():
    receipt = json.loads((WORK / 'unit-o3.qbe-manifest.json').read_text())
    guests = [Path(f['object']) for f in receipt['functions']]
    entry = next(p for p in guests[0].parent.glob('*.o') if p not in guests and re.search(r' T main$', run(['nm', p]), re.M))
    assets = next((WORK / 'cache-o3/runtime').glob('*'))
    text = (ROOT / 'src/qbe_build.zig').read_text()
    units = re.findall(r'"([a-z_]+\.c)"', text.split('const runtime_units =')[1].split('};', 1)[0])
    results = {}
    for mode in ('zlink', 'lto'):
        directory = WORK / mode
        directory.mkdir(exist_ok=True)
        flag = ['-flto'] if mode == 'lto' else []
        cflags = ['zig', 'cc', *flag, '-O2', '-std=c11', '-fPIC', '-g0', '-ffunction-sections', '-fdata-sections', '-I', assets]
        runtime = []
        for unit in units:
            obj = directory / (unit + '.o')
            run([*cflags, '-c', assets / unit, '-o', obj])
            runtime.append(obj)
        provider = directory / 'provider.o'
        run([*cflags, '-c', ROOT / 'src/schematic/native_schematic.c', '-o', provider])
        guest = directory / 'guest.o'
        run(['zig', 'cc', *flag, '-O3', '-fPIC', '-g0', '-c', WORK / 'whole.ll', '-o', guest])
        for bridge in ('regenerated', 'both'):
            meta = directory / f'metadata-{bridge}.o'
            run([*cflags, '-c', WORK / f'metadata-{bridge}.c', '-o', meta])
            name = mode+'-plain' if bridge == 'regenerated' else mode+'-both'
            binary = WORK / name
            run(['zig', 'cc', *flag, '-O3', '-fPIC', '-g0', guest, meta, entry, provider,
                 *runtime, '-lm', '-Wl,--gc-sections', '-o', binary])
            results[name] = {'path': str(binary), 'sha256': sha(binary), 'bytes': binary.stat().st_size}
            print('built', name, flush=True)
    result = {'binaries': results, 'runtime_sources': {n: sha(assets / n) for n in units},
              'scope': 'same checked guest IR, C sources and O2 flags; -flto and O3 at link; original native entry object'}
    (Path(__file__).parent / 'lto-builds.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
