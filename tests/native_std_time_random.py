"""Execute standard time/random vectors and explicit provider outcomes in native C."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def run(args, env=None):
    result = subprocess.run(list(map(str, args)), capture_output=True, timeout=120, env=env)
    return result


PROVIDER = r'''
#include "native_providers.h"
#include <stdlib.h>
static unsigned calls;
static int mode(void) { const char *s = getenv("TIME_RANDOM_MODE"); return s ? atoi(s) : 0; }
static MylangClockResult clock_read(void *context) {
    (void)context;
    int m = mode();
    return (MylangClockResult){m >= 2 && m <= 5 ? m - 1 : 0, -7};
}
static MylangRandomResult random_read(void *context) {
    (void)context;
    ++calls;
    return (MylangRandomResult){mode() == 1 && calls == 2 ? MYLANG_PROVIDER_FAILED : MYLANG_PROVIDER_OK, UINT64_C(0x0102030405060708)};
}
MylangNativeProviders mylang_native_providers(void) {
    MylangNativeProviders p = {0};
    if (mode() != 6) { p.clock_now = clock_read; p.random_u64 = random_read; }
    return p;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--cc', default='cc')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    compiler = args.compiler.resolve()
    comparisons = 0
    with tempfile.TemporaryDirectory(prefix='stdlib-time-random-') as temp:
        temp = Path(temp)
        adapter = temp / 'provider.c'
        adapter.write_text(PROVIDER)
        for name in ('time_random', 'time_random_provider'):
            source = temp / 'main.my'
            source.write_bytes((root / 'src/stdlib/fixtures' / (name + '.my')).read_bytes())
            if name == 'time_random':
                vm = run([compiler, 'run-project', source])
                assert (vm.returncode, vm.stdout) == (0, b'0\n'), vm.stderr
            emitted = run([compiler, 'emit-project-c', source])
            assert emitted.returncode == 0, emitted.stderr
            generated = temp / 'program.c'
            generated.write_bytes(emitted.stdout)
            for mode in ('-O0', '-O2'):
                exe = temp / 'program'
                built = run([args.cc, '-std=c11', mode, '-fsanitize=undefined',
                             '-fno-sanitize-recover=all', '-DMYLANG_NATIVE_PROVIDER=1',
                             '-I', root / 'src', generated, adapter, '-o', exe])
                assert built.returncode == 0, built.stderr
                outcomes = {0: 0} if name == 'time_random' else {0: 0, 1: 45, 2: 43, 3: 42, 4: 44, 5: 'OutOfMemory', 6: 'CapabilityUnavailable'}
                for setting, expected in outcomes.items():
                    env = dict(os.environ, TIME_RANDOM_MODE=str(setting))
                    actual = run([exe], env)
                    if isinstance(expected, int):
                        assert (actual.returncode, actual.stdout) == (0, f'{expected}\n'.encode()), actual.stderr
                    else:
                        assert actual.returncode == 2 and actual.stdout == b'' and expected.encode() in actual.stderr, actual.stderr
                    comparisons += 1
    print(f'standard time/random: {comparisons} native outcomes passed (O0/O2, UBSan)')


if __name__ == '__main__':
    main()
