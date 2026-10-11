"""Private B7 composed frontend generations; native later passes/backend retained."""
import argparse
import json
from pathlib import Path
import sys

PROBES = Path('/home/epentland/.codex/worktrees/selka-compiler-probes/mylang')
sys.path.insert(0, str(PROBES/'selfhost/tests'))
import run_body_entry_qualification as E

MODES = ('LEXER', 'PARSER', 'DECLARATION', 'TYPE_INTERFACE', 'BODY_CHECK', 'TEST_INDEX', 'CACHE_PLAN')
original_environment = E.D.environment


def environment(mode, deployment, empty):
    result = original_environment(mode, deployment, empty)
    for name in MODES:
        result['MYLANG_'+name+'_MODE'] = mode
    return result


class Composed(E.Qualification):
    def checkpoint(self, complete=False):
        report = {'complete': complete,
                  'scope': 'two further component generations with all frontend component modes selected; native catalog/later semantic passes/backend/driver retained; not full compiler bootstrap',
                  'identity': self.identity, 'selected_modes': {name: 'component' for name in MODES},
                  'mode_scope': 'check/build exercises frontend boundaries; direct runtime probes independently exercise all seven package protocols',
                  'parent_generation': getattr(self, 'parent_generation', None),
                  'release_facts_leaks': True, 'operations': len(self.records),
                  'expected_operations': 119, 'records': self.records,
                  'captures': self.captures, 'generations': self.generations,
                  'compiler_build_limits': {'address_space': E.BUILD_ADDRESS_SPACE_BUDGET,
                                            'file_size': E.BUILD_FILE_SIZE_BUDGET}}
        if complete:
            report.update(failed=0, skipped=0)
        self.args.report.parent.mkdir(parents=True, exist_ok=True)
        self.args.report.write_text(json.dumps(report, indent=2)+'\n')

    def run_composed(self):
        parent = E.D.packages(self.args.parent_deployment, body_schema=E.SCHEMA)
        self.parent_generation = parent
        self.checkpoint()
        seed = E.F.execute([self.args.builder, '--root', self.args.source_root,
                            '--zig', self.args.zig, '--seed-only'],
                           E.D.coordinator_environment(), self.args.source_root, 600)
        lines = seed[1].decode().strip().splitlines()
        E.require(seed[0] == 0 and len(lines) == 1 and Path(lines[0]).is_file(), 'qualified seed verification failed')
        self.identity['qualified_seed_sha256'] = E.F.digest(Path(lines[0]))
        self.identity['capture_fixture_sha256'] = E.F.digest(E.FIXTURES/'exchange_capture.c')
        built = E.F.execute([self.args.zig, 'cc', E.FIXTURES/'exchange_capture.c', '-O2', '-o', self.wrapper],
                            E.D.coordinator_environment(), self.work, 180)
        E.require(built[0] == 0, 'capture wrapper compilation failed')
        baseline = {}
        checks = {}
        for name, relative in E.ENTRIES.items():
            baseline[name] = self.probes(self.args.component_dir/self.identity['packages'][name]['artifact'], name, 'reference')
            entry = self.args.source_root/'selfhost/components'/relative
            checks[name] = self.host('reference', ['check', entry, '--no-cache'],
                                     self.args.component_dir, self.work, name+'-native-check')
            E.require(checks[name][0] == 0, 'native source check failed: '+name)
        deployment = self.args.parent_deployment
        for generation in (3, 4):
            binaries = {}
            for name, relative in E.ENTRIES.items():
                phase = name+'-composed-generation'+str(generation)
                entry = self.args.source_root/'selfhost/components'/relative
                actual = self.host('component', ['check', entry, '--no-cache'], deployment,
                                   self.work, phase+'-check', True)
                E.require(actual == checks[name], 'composed check differs: '+phase)
                binary = self.work/phase
                command = ['build', entry, '--no-cache', *self.build_flags(), '-o', binary,
                           '--zig='+str(self.args.zig)]
                result = self.host('component', command, deployment, self.work, phase+'-build', True)
                E.require(result[0] == 0 and binary.is_file(), 'composed build failed: '+phase)
                E.require(self.probes(binary, name, 'component') == baseline[name], 'composed runtime differs: '+phase)
                E.require(E.F.digest(binary) == parent[name]['sha256'], 'composed artifact differs from qualified parent: '+phase)
                binaries[name] = binary
            destination = self.work/('generation'+str(generation))
            recipe = {'generation': generation, 'host': self.identity['host'],
                      'sources': self.identity['sources'], 'selected_modes': {name: 'component' for name in MODES},
                      'flags': ['--no-cache', *self.build_flags()],
                      'parent_packages': E.D.packages(deployment, body_schema=E.SCHEMA)}
            E.private_deployment(deployment, destination, binaries, recipe)
            self.generations.append({'generation': generation,
                                     'packages': E.D.packages(destination, body_schema=E.SCHEMA),
                                     'all_artifacts_identical_to_parent': True, 'recipe': recipe})
            self.checkpoint()
            deployment = destination
        E.require(len(self.records) == 119 and len(self.captures) == 28 and len(self.generations) == 2,
                  'incomplete composed generation inventory')
        expected = {(name+'-composed-generation'+str(generation)+'-'+phase, 'component')
                    for name in E.ENTRIES for generation in (3, 4) for phase in ('check', 'build')}
        E.require({(row['phase'], row['mode']) for row in self.captures} == expected,
                  'duplicate or missing composed capture')
        E.require(E.F.digest(self.args.compiler) == self.identity['host'] and
                  E.D.packages(self.args.component_dir, body_schema=E.SCHEMA) == self.identity['packages'],
                  'installed deployment changed')
        E.require(E.D.packages(self.args.parent_deployment, body_schema=E.SCHEMA) == parent,
                  'qualified parent deployment changed')
        E.require(E.source_identity(self.args.source_root) == self.identity['sources'] and
                  E.request_inventory(self.args.requests_dir) == self.requests,
                  'source or runtime request inventory changed')
        self.checkpoint(True)
        print('composed B7 generations: 119 operations, 28 fresh body exchanges, 2 generations of 7 byte-identical artifacts; 0 failed, 0 skipped')


def main():
    parser = argparse.ArgumentParser()
    for name in ('compiler', 'builder', 'component-dir', 'zig', 'source-root', 'requests-dir',
                 'work-dir', 'report', 'parent-deployment'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    for name in vars(args):
        setattr(args, name, getattr(args, name).resolve())
    args.release = True
    E.D.environment = environment
    Composed(args).run_composed()


if __name__ == '__main__':
    main()
