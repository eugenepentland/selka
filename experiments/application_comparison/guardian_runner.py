"""Trusted isolated Guardian entry: enforce policy and discard participant cache claims."""
import os
from pathlib import Path
import shutil
import subprocess
import sys


def stage(source, policy, destination):
    source, policy, destination = Path(source), Path(policy), Path(destination)
    for name in ('guardian.toml', 'main.zig'):
        path = source / name
        if path.is_symlink() or not path.is_file() or path.read_bytes() != (policy / name).read_bytes():
            raise ValueError('protected Guardian policy or compile entry changed: ' + name)
    files = []
    for directory, directories, names in os.walk(source, followlinks=False):
        relative = Path(directory).relative_to(source)
        for name in list(directories):
            path = Path(directory) / name
            item = path.relative_to(source)
            if item == Path('.guardian/cache'):
                directories.remove(name)
                continue
            if path.is_symlink() or name == '.git':
                raise ValueError('unsupported candidate directory: ' + str(item))
            if item.parts[0] == '.guardian' and len(item.parts) > 1:
                raise ValueError('participant Guardian metadata is forbidden: ' + str(item))
        for name in names:
            path = Path(directory) / name
            item = relative / name
            if path.is_symlink() or not path.is_file():
                raise ValueError('candidate must contain regular source files')
            if item.parts[0] == '.guardian' or item.parts[0] == '.git' or name == '.gitattributes':
                raise ValueError('participant Guardian metadata is forbidden: ' + str(item))
            if path.suffix == '.zig' and item != Path('main.zig') and item.parts[0] != 'src':
                raise ValueError('Zig implementation must be under Guardian-scanned src/: ' + str(item))
            files.append((path, item))
    if not (source / 'src/main.zig').is_file():
        raise ValueError('Guardian-scanned application entry is required')
    destination.mkdir(exist_ok=False)
    for path, item in files:
        target = destination / item
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)


def main():
    if len(sys.argv) != 1:
        raise ValueError('Guardian trial entry accepts no participant arguments')
    project = Path('/cache/guardian-project')
    stage('/work', '/tools/guardian_policy', project)
    environment = dict(os.environ, PATH='/tools/zig:/usr/bin:/bin')
    # Guardian's diff-backed checks require Git metadata. Create it ourselves,
    # with an empty base and the entire candidate staged as additions. Candidate
    # hooks/config/attributes are never imported as trusted repository settings.
    git = ['/usr/bin/git', '-C', str(project)]
    for arguments in (['init', '--quiet', '--template=', '--initial-branch=main'],
                      ['-c', 'user.name=Trial coordinator', '-c', 'user.email=trial@invalid',
                       '-c', 'core.hooksPath=/dev/null', 'commit', '--quiet', '--allow-empty', '-m', 'empty analysis base'],
                      ['add', '--all', '--force']):
        subprocess.run(git + arguments, env=environment, check=True)
    result = subprocess.run(['/tools/guardian', 'all', str(project), '--against', 'HEAD'], env=environment, check=False)
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
